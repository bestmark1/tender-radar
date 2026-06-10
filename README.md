# 🎯 Тендер-радар

> Self-hosted веб-сервис мониторинга госзакупок (44-ФЗ) для поставщиков: автоматически находит релевантные закупки по правилам пользователя и присылает подборку с дедлайнами. Ядро автоматизации — **n8n**, веб-часть — **Next.js**, данные — **Supabase**.

**Стек:** Next.js 16 · TypeScript · Supabase (Postgres + Auth + RLS) · n8n (self-hosted, Docker, queue mode) · Telegram Bot API

---

## Зачем это

Тысячи компаний-поставщиков живут за счёт госзаказа, но чтобы получить контракт, тендер нужно **найти вовремя** — до окончания приёма заявок. Сегодня это либо ручной ежедневный обход `zakupki.gov.ru` (медленно, пропуски), либо дорогие агрегаторы (15–50 т.р./мес, негибкие).

**Тендер-радар** закрывает нишу «дёшево + гибко + self-hosted»: пользователь задаёт «радары» (регион, ОКПД2, ключевые слова, цена), а сервис сам тянет свежие закупки, фильтрует под правила и шлёт дайджест + напоминания о дедлайнах.

Пилотная вертикаль MVP: **клининг (ОКПД2 81.2), Москва + Московская область.**

---

## Архитектура

```
┌──────────────────────────────┐        ┌──────────────────────────────┐
│  ФРОНТ — Next.js (Vercel)     │        │  N8N — self-hosted (Docker,   │
│  • CRUD «радаров» (правил)    │        │       queue mode + Redis)     │
│  • Дашборд закупок/совпадений │        │                               │
│  • Auth: Supabase magic link  │        │  WF1 Ingest → WF2 Filter →    │
└───────────────┬──────────────┘        │  WF3 Notify / WF4 Deadline    │
                │ RLS, Realtime          │  WF0 Error Handler (глобальн.)│
                ▼                         └───────────┬───────────────────┘
┌──────────────────────────────┐  upsert/read        │  read/write (service_role)
│  SUPABASE (Postgres + Auth)   │◄────────────────────┘
│  users · radars · tenders ·   │            │ send
│  matches · notifications      │            ▼
└──────────────────────────────┘   ┌──────────────────────┐   ┌──────────────────┐
                                    │ ЕИС (источник, Ф.3)  │   │ Telegram (демо), │
                                    │ SOAP getDocsIP+токен │   │ email/MAX (далее)│
                                    └──────────────────────┘   └──────────────────┘
```

**Принцип:** вся интеграционная/фоновая логика — в n8n-воркфлоу (версионируются как JSON). Фронт не содержит бизнес-логики: делает CRUD радаров в Supabase под RLS и читает результаты.

Подробнее: [`SPEC_PLAN/ARCHITECTURE.md`](SPEC_PLAN/ARCHITECTURE.md).

---

## Возможности (реализовано)

| # | Возможность | Где |
|---|---|---|
| US-1 | Настройка «радаров»: регион, ОКПД2, ключевые слова (incl/excl), цена, закон | Веб + `radars` |
| US-2 | Загрузка закупок в `tenders` (скелет на мок-данных; реальный ЕИС — Ф.3) | n8n **WF1** |
| US-3 | Фильтрация закупок по радарам → `matches` | n8n **WF2** |
| US-4 | Дайджест новых совпадений + напоминания о дедлайнах в Telegram | n8n **WF3/WF4** |

---

## N8N-воркфлоу

| Воркфлоу | Триггер | Что делает |
|---|---|---|
| `WF0_error` | Error Trigger | Глобальный обработчик ошибок (лог/алерт) |
| `WF1_ingest` | Schedule / Manual | Загрузка закупок → upsert в Supabase `tenders` (идемпотентно по `reg_number+version`) |
| `WF2_filter` | Manual | Матчинг закупок с активными радарами → upsert `matches` |
| `WF3_notify` | Manual | Дайджест новых совпадений → Telegram → пометка `notified` |
| `WF4_deadline` | Schedule / Manual | Напоминания за N дней до дедлайна по «interested» → Telegram → `reminded` |

Воркфлоу лежат в [`n8n/workflows/`](n8n/workflows/) как версионируемый JSON. Секреты — только в `.env` (через `{{ $env.* }}`), в git их нет.

### Каналы уведомлений

Уведомления построены как набор взаимозаменяемых каналов — добавить новый значит дописать одну ноду по той же схеме. Статус:

| Канал | Статус |
|---|---|
| Telegram | ✅ реализовано |
| Email (SMTP) | 🔜 нода готова, доставку включаем на проде |
| ВКонтакте | 🔧 заложен в архитектуру |
| MAX | 🔧 заложен в архитектуру |

**Демонстрируемые приёмы n8n:** self-hosted в Docker (queue mode + worker + Redis), HTTP-интеграции (Supabase REST, Telegram Bot API), Code-ноды с бизнес-логикой, sub-workflow-связи, глобальный Error Workflow, идемпотентный upsert, версионирование воркфлоу в git.

---

## Локальный запуск

### 1. Supabase
- Создать проект на [supabase.com](https://supabase.com), применить миграцию [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) (SQL Editor).
- Auth → URL Configuration: Site URL `http://localhost:3000`, Redirect `http://localhost:3000/**`.

### 2. Веб (Next.js)
```bash
cd web
cp .env.example .env.local   # вписать NEXT_PUBLIC_SUPABASE_URL / ANON_KEY
npm install
npm run dev                  # http://localhost:3000
```

### 3. N8N (Docker)
```bash
cd n8n
cp .env.example .env         # вписать секреты (см. n8n/README.md)
docker compose up -d         # UI: http://localhost:5678
docker compose exec n8n n8n import:workflow --separate --input=/workflows
```
Подробно про воркфлоу/секреты/прогон — [`n8n/README.md`](n8n/README.md).

---

## Структура репозитория

```
web/                 # Next.js 16 (App Router, TS strict): Auth, CRUD радаров
n8n/                 # docker-compose (n8n+worker+Postgres+Redis) + workflows/*.json
supabase/migrations/ # SQL-схема + RLS
SPEC_PLAN/           # продуктовые и инженерные артефакты (см. ниже)
docs/                # правила исполнения, tech-debt, quality score
PROJECT_INDEX.md     # навигация по репозиторию
```

Проект ведётся по дисциплинированному пайплайну (Narrative → MRD → PRD → Architecture → план по фазам → исполнение). Артефакты — в [`SPEC_PLAN/`](SPEC_PLAN/): Narrative, MRD, PRD, ARCHITECTURE, CONSTITUTION, IMPLEMENTATION_PLAN, cross-artifact-analysis.

---

## Статус проекта

| Фаза | Содержание | Статус |
|---|---|---|
| 0 | Каркас (Next.js + Docker N8N) | ✅ |
| 1 | Схема БД + Auth + CRUD радаров (US-1) | ✅ |
| 2 | N8N-инфра + ingest-скелет + Error Workflow (US-2 скелет) | ✅ |
| 4 | Фильтрация (US-3) | ✅ |
| 5 | Уведомления: Telegram-дайджест + напоминания (US-4) | ✅ (email/MAX — далее) |
| 3 | Реальная загрузка из ЕИС | ⏸️ см. ниже |
| 6 | Дашборд + календарь дедлайнов (US-5) | ⏳ |
| 7 | Hardening + деплой на VPS | ⏳ |

### Почему ЕИС — отдельная фаза
С 01.01.2025 FTP ЕИС закрыт; данные — только через SOAP-сервисы отдачи с **токеном потребителя машиночитаемых данных**, который теперь требует **квалифицированную ЭЦП (КЭП)**. Поэтому источник данных абстрагирован: пайплайн построен и проверен на мок-данных, а подключение реального ЕИС (официальный SOAP+КЭП либо сторонний JSON-API) — отдельный шаг. Это сознательное архитектурное решение, а не недоделка (см. `docs/tech-debt-tracker.md`, TD-9).

---

## Дисклеймер

Учебный/портфолио-проект. Не аффилирован с ЕИС/zakupki.gov.ru. Данные госзакупок общедоступны. n8n используется под Sustainable Use License (self-host для собственных нужд).
