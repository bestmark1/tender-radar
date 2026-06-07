# ARCHITECTURE — Тендер-радар

> Роль: Architect. Источник истины для технической структуры: компоненты, потоки данных, схема БД, N8N-воркфлоу, безопасность, решения и их обоснование.

## 1. Принцип

**N8N — движок автоматизации в бэкенде. Фронт не содержит бизнес-логики.** Фронт делает простой CRUD радаров в Supabase и читает результаты. Вся интеграционная/фоновая логика (загрузка ЕИС, парсинг, фильтрация, уведомления) живёт в N8N-воркфлоу, версионируемых в git как JSON.

## 2. Компоненты

```
┌─────────────────────────────────────────────────────────────┐
│  ФРОНТЕНД — Next.js (App Router, TS) на Vercel               │
│  • CRUD радаров (US-1)                                        │
│  • Дашборд закупок + календарь дедлайнов (US-5)              │
│  • Auth: Supabase Auth (magic link)                          │
└───────────┬──────────────────────────────┬──────────────────┘
            │ (A) CRUD radars / read tenders│ (B) Realtime подписка
            │     через Supabase JS client  │     на matches/tenders
            ▼              (RLS)             ▼
┌─────────────────────────────────────────────────────────────┐
│  SUPABASE  — БИЗНЕС-ДАННЫЕ (Postgres + Realtime + Auth)      │
│  Таблицы: users, radars, tenders, matches,                  │
│           notifications, deadline_reminders                  │
│  RLS: пользователь видит только свои радары/совпадения       │
└───────▲──────────────────────────────────────▲──────────────┘
        │ (C) upsert tenders/matches            │ (D) read active radars
        │     write notifications               │
┌───────┴──────────────────────────────────────┴──────────────┐
│  N8N — self-hosted (Docker, queue mode)                      │
│                                                               │
│  WF1 Ingest (Schedule 2×/день)                               │
│    Schedule → для региона[77,50] + тип notification:         │
│    HTTP(SOAP getDocsByOrgRegionRequest, token) →             │
│    получить archiveUrl → HTTP download (token) →             │
│    Unzip → Parse XML (Code) → Normalize →                    │
│    Upsert tenders (Supabase) → Execute WF2                   │
│                                                               │
│  WF2 Filter (sub-workflow)                                   │
│    Read active radars (Supabase) → match each tender →       │
│    upsert matches (new only) → Execute WF3                   │
│                                                               │
│  WF3 Notify (sub-workflow)                                   │
│    Group new matches by user/channel → render digest →       │
│    Email(SMTP) ‖ VK ‖ MAX(HTTP) ‖ Telegram → write           │
│    notifications (Supabase)                                  │
│                                                               │
│  WF4 Deadline reminder (Schedule daily)                      │
│    Read «interested» matches with deadline ≤ N дней →        │
│    Notify → mark reminded                                    │
│                                                               │
│  WF0 Error Workflow (global)                                 │
│    Любой сбой WF1–WF4 → лог + алерт администратору           │
└───────┬───────────────────────────┬─────────────────────────┘
        │                           │
        ▼ (E) SOAP + download       ▼ (F) send
┌──────────────────┐   ┌──────────────────────────────────────┐
│ ЕИС              │   │ Каналы: SMTP / VK API / MAX Bot API / │
│ int44.zakupki... │   │         Telegram Bot API             │
│ getDocsIP (SOAP) │   └──────────────────────────────────────┘
└──────────────────┘

  N8N служебная Postgres (execution history) + Redis (queue) —
  отдельно от Supabase, внутри docker-compose.
```

## 3. Поток данных (happy path)

1. **Schedule** (08:00/18:00 МСК) запускает WF1.
2. Для каждого региона (77, 50) и типа документа `notification` за период `[last_run, now]`: SOAP-запрос `getDocsByOrgRegionRequest` с `individualPerson_token` в заголовке.
3. Ответ содержит ссылку(и) на ZIP-архив(ы). Скачиваем тем же токеном.
4. Распаковка ZIP → XML-файлы извещений. Code-нода парсит XML в нормализованные записи.
5. Upsert в `tenders` (Supabase) по ключу `reg_number + version` (идемпотентность, R7).
6. WF2 читает активные `radars`, сопоставляет новые tenders, пишет новые `matches`.
7. WF3 группирует новые matches по пользователю/каналам, рендерит дайджест, шлёт по включённым каналам, пишет `notifications`.
8. Фронт через Supabase Realtime показывает новые tenders/matches без перезагрузки.
9. WF4 (раз в день) шлёт напоминания по «interested»-закупкам с близким дедлайном.

## 4. Схема БД (Supabase Postgres)

```sql
-- Пользователи (MVP: один; завязка на Supabase Auth)
users (
  id uuid pk references auth.users,
  email text,
  channels jsonb,        -- {email:bool, vk:{enabled,peer_id}, max:{...}, telegram:{chat_id}}
  created_at timestamptz default now()
)

-- Радары (правила мониторинга) — US-1
radars (
  id uuid pk default gen_random_uuid(),
  user_id uuid references users(id),
  name text not null,
  regions text[] not null,          -- ['77','50']
  okpd_prefixes text[] not null,    -- ['81.2']
  keywords_include text[],
  keywords_exclude text[],
  price_min numeric,
  price_max numeric,
  law text not null default '44',   -- '44' | '223' | 'both'
  reminder_days int not null default 2,
  is_active bool not null default true,
  created_at timestamptz default now()
)

-- Закупки (нормализованные из ЕИС) — US-2
tenders (
  id uuid pk default gen_random_uuid(),
  reg_number text not null,
  version int not null default 1,
  title text,
  customer text,
  region text,
  okpd text,
  price numeric,                    -- НМЦК
  published_at timestamptz,
  submission_deadline timestamptz,
  eis_url text,
  law text,
  raw jsonb,                        -- исходные поля на всякий случай
  created_at timestamptz default now(),
  unique (reg_number, version)
)

-- Совпадения закупка↔радар — US-3
matches (
  id uuid pk default gen_random_uuid(),
  tender_id uuid references tenders(id),
  radar_id uuid references radars(id),
  user_id uuid references users(id),
  status text not null default 'new',  -- 'new'|'interested'|'hidden'
  notified bool not null default false,
  reminded bool not null default false,
  created_at timestamptz default now(),
  unique (tender_id, radar_id)
)

-- Лог уведомлений — US-4
notifications (
  id uuid pk default gen_random_uuid(),
  user_id uuid references users(id),
  channel text not null,            -- 'email'|'vk'|'max'|'telegram'
  kind text not null,               -- 'digest'|'deadline'
  payload jsonb,
  status text not null,             -- 'sent'|'failed'
  error text,
  created_at timestamptz default now()
)
```

RLS: все таблицы с `user_id` — policy `user_id = auth.uid()`. N8N пишет через service_role (минует RLS) — ключ только в N8N credential store.

## 5. N8N-воркфлоу (реестр)

| WF | Тип | Триггер | Назначение |
|---|---|---|---|
| WF0 | Error Workflow | глобальный | Лог + алерт о сбоях любого WF |
| WF1 | Main | Schedule 2×/день | Загрузка из ЕИС → upsert tenders |
| WF2 | Sub-workflow | Execute от WF1 | Фильтрация по радарам → matches |
| WF3 | Sub-workflow | Execute от WF2 | Рендер дайджеста → отправка по каналам |
| WF4 | Main | Schedule 1×/день | Напоминания о дедлайнах |

Все воркфлоу экспортируются в `n8n/workflows/*.json` и версионируются в git (AC-6.4).

## 6. Безопасность

- **Токен ЕИС** и `service_role` Supabase — в N8N credential store / `.env`, НЕ в git (AC-6.2). `.env.example` с пустыми ключами — в git.
- **Вебхуки** (если используются для ручного триггера/фронта) — Header Auth секретом, неавторизованные отклоняются (AC-6.1).
- **Reverse-proxy** (Caddy/Traefik) перед N8N: HTTPS, корректный `WEBHOOK_URL`, таймауты под долгие загрузки.
- **RLS** в Supabase для пользовательских данных.
- **Идемпотентность** загрузки (R4/R7): upsert по `reg_number+version`, ретраи с backoff.

## 7. Деплой

- **Фронт:** Vercel (Next.js).
- **Supabase:** managed (бесплатный тариф).
- **N8N + Postgres(служебная) + Redis:** `docker-compose.yml`. Локально для разработки; для демо — дешёвый VPS (Selectel/Timeweb) + Caddy.
- **Queue mode:** `EXECUTIONS_MODE=queue`, отдельный worker-контейнер, Redis (AC-6.5).

## 8. Ключевые архитектурные решения (ADR-кратко)

| ADR | Решение | Обоснование | Альтернатива (отклонена) |
|---|---|---|---|
| ADR-1 | Бизнес-данные в Supabase, не в БД N8N | Фронт читает напрямую (Realtime+RLS), развязка ролей; БД N8N — только execution-история | Всё в одной Postgres N8N → фронт не может удобно читать, нет RLS |
| ADR-2 | Фронт пишет радары прямо в Supabase | Простой CRUD, не нужен вебхук-слой; N8N только читает радары | CRUD через вебхуки N8N → лишняя сложность |
| ADR-3 | Загрузка по региону+тип+период, фильтрация у нас | Ограничение API ЕИС (нет поиска по слову); сужаем регион/ОКПД | Сторонний JSON-API → платно, не портфолийно (оставлен как fallback) |
| ADR-4 | Только 44-ФЗ в MVP | Однородность данных для клининга, меньше схем | 44+223 сразу → удвоение парсеров |
| ADR-5 | LLM-скоринг отложен в Фазу 2 | Правил достаточно для клининга; не блокировать MVP | LLM в MVP → лишняя зависимость и стоимость |
| ADR-6 | N8N в queue mode с Redis | Прод-готовность, портфолио-галочка, объём Москва+МО | single-process → упирается на больших архивах |

## 9. Трассировка к PRD

- US-1 → таблица `radars`, фронт CRUD (поток A).
- US-2 → WF1 (потоки E, C), таблица `tenders`.
- US-3 → WF2, таблица `matches`.
- US-4 → WF3/WF4 (поток F), таблица `notifications`.
- US-5 → фронт-дашборд (потоки A, B).
- US-6 → раздел 6 (безопасность), docker-compose, Error Workflow, git-экспорт.
