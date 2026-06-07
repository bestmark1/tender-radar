# IMPLEMENTATION_PLAN — Тендер-радар

> Роль: Tech Lead. Разбивка на изолированные фазы. Каждая фаза: цель, скоуп, файлы, зависимости, DoD, верификация, rollback, формат отложенного.
> Исполнять строго по одной фазе (phase isolation, см. CONSTITUTION §3).

## Обзор фаз

| Фаза | Название | Зависит от | Нужен токен ЕИС? | Покрывает |
|---|---|---|---|---|
| 0 | Каркас и инфраструктура | — | нет | структура репо |
| 1 | Схема БД + Auth + CRUD радаров | 0 | нет | US-1 |
| 2 | N8N: инфра + Error WF + ingest-скелет (мок) | 0 | нет | US-6 (часть), US-2 (скелет) |
| 3 | Реальная загрузка из ЕИС | 2, **Задача 0** | **да** | US-2 |
| 4 | Фильтрация по радарам | 1, 3 | да | US-3 |
| 5 | Уведомления + напоминания | 4 | да | US-4 |
| 6 | Дашборд + календарь дедлайнов | 1, 4 | нет | US-5 |
| 7 | Hardening + портфолио-полировка | 2–6 | да | US-6 (финал) |

> **Задача 0 (блокер фазы 3):** получить токен потребителя машиночитаемых данных ЕИС на Госуслугах (физлицо/ИП), положить в `n8n/.env` как `EIS_TOKEN`. Фазы 0–2 идут без токена.

---

## Фаза 0 — Каркас и инфраструктура

**Цель:** репозиторий с рабочими скелетами фронта, N8N и Supabase-конфигом; всё поднимается локально.

**Скоуп (in):** инициализация Next.js, docker-compose для N8N, структура папок, `.env.example`.
**Скоуп (out):** любая бизнес-логика, схема БД, воркфлоу.

**Файлы:**
- Create: `web/` (Next.js App Router, TS strict) — `package.json`, `tsconfig.json`, `app/page.tsx`, `next.config.js`, `.eslintrc`.
- Create: `n8n/docker-compose.yml` (n8n + Postgres служебная + Redis, queue mode).
- Create: `n8n/.env.example`, `web/.env.example`.
- Create: `supabase/.gitkeep`, `n8n/workflows/.gitkeep`.
- Modify: `.gitignore` (node_modules, .env, .n8n).

**Зависимости:** нет.

**Definition of Done:**
- `web` собирается и стартует (`npm run dev` отдаёт страницу).
- `docker compose -f n8n/docker-compose.yml up -d` поднимает n8n (UI на :5678), Postgres, Redis; `docker compose ps` — все healthy.
- `.env.example` содержит все ключи без значений.

**Верификация:**
- `cd web && npm install && npm run build` → exit 0.
- `cd web && npm run lint && npx tsc --noEmit` → exit 0.
- `docker compose -f n8n/docker-compose.yml config` → exit 0 (валидный compose).
- `docker compose -f n8n/docker-compose.yml up -d && docker compose -f n8n/docker-compose.yml ps` → n8n/redis/postgres up.

**Rollback:** `git revert HEAD`; `docker compose down -v`.

**Формат отложенного:** `Deferred to Phase N: <причина>` в `docs/tech-debt-tracker.md`.

---

## Фаза 1 — Схема БД + Auth + CRUD радаров (US-1)

**Цель:** пользователь создаёт/редактирует/удаляет радары; данные в Supabase под RLS. Без ЕИС.

**Скоуп (in):** SQL-миграции всех таблиц + RLS; Supabase Auth (magic link); фронт-страницы CRUD радаров; генерация типов из схемы.
**Скоуп (out):** загрузка закупок, фильтрация, уведомления, дашборд закупок.

**Файлы:**
- Create: `supabase/migrations/0001_init.sql` (таблицы users, radars, tenders, matches, notifications + RLS — по ARCHITECTURE §4).
- Create: `web/lib/supabase.ts` (клиент), `web/types/db.ts` (сген. типы).
- Create: `web/app/(auth)/login/page.tsx` (magic link).
- Create: `web/app/radars/page.tsx` (список), `web/app/radars/[id]/page.tsx` (форма), `web/components/RadarForm.tsx`.
- Test: `web/__tests__/radarForm.test.tsx` (валидация AC-1.4).

**Зависимости:** Фаза 0.

**Definition of Done:**
- Все AC US-1 выполнены (создание/редактирование/удаление/toggle/валидация).
- RLS: пользователь видит только свои радары (проверка с двумя пользователями).
- Типы БД сгенерированы и используются.

**Верификация:**
- `cd web && npm run build && npm run lint && npx tsc --noEmit && npm test` → exit 0.
- Тест валидации US-1.4 (нельзя сохранить без региона/критерия) — PASS.
- Ручная проверка: создать радар «Клининг МСК» (regions=['77','50'], okpd=['81.2']) → виден в списке, недоступен другому пользователю.

**Rollback:** `git revert HEAD`; откатить миграцию `supabase migration repair` / drop таблиц.

**Формат отложенного:** как в Фазе 0.

---

## Фаза 2 — N8N: инфра + Error Workflow + ingest-скелет с моком (US-6 часть, US-2 скелет)

**Цель:** рабочий скелет конвейера загрузки на N8N с заглушкой вместо реального SOAP; глобальный Error Workflow; запись в Supabase подтверждена. Готово к подстановке токена.

**Скоуп (in):** WF0 Error Workflow; WF1 со структурой нод (Schedule → [мок-данные вместо SOAP] → parse → normalize → upsert в Supabase); credential Supabase service_role; экспорт воркфлоу в JSON.
**Скоуп (out):** реальный SOAP-вызов ЕИС (Фаза 3), фильтрация (Фаза 4), уведомления (Фаза 5).

**Файлы:**
- Create: `n8n/workflows/WF0_error.json`.
- Create: `n8n/workflows/WF1_ingest.json` (с Code-нодой-заглушкой, отдающей 2–3 фейковых извещения по клинингу).
- Create: `n8n/README.md` (как импортировать/экспортировать воркфлоу, queue mode).
- Modify: `n8n/.env.example` (SUPABASE_URL, SUPABASE_SERVICE_ROLE, EIS_TOKEN placeholder).

**Зависимости:** Фаза 0 (инфра), Фаза 1 (таблица tenders должна существовать).

**Definition of Done:**
- Ручной прогон WF1 с мок-данными → 2–3 записи появились в `tenders` (Supabase), идемпотентно (повторный прогон не плодит дубли — AC-2.4).
- WF0 ловит искусственно вызванную ошибку и логирует/алертит (AC-6.3).
- Воркфлоу экспортированы в `n8n/workflows/*.json` (AC-6.4).
- N8N работает в queue mode (AC-6.5).

**Верификация:**
- Ручной прогон WF1 в N8N → проверить вход/выход каждой ноды; строки в Supabase (SQL `select count(*) from tenders`).
- Повторный прогон → count не вырос (идемпотентность).
- Триггер ошибки (битый вход) → запись в Error Workflow.
- `docker compose ps` показывает worker-контейнер (queue mode).

**Rollback:** удалить импортированные воркфлоу; `git revert HEAD`; `truncate tenders`.

**Формат отложенного:** как выше.

---

## Фаза 3 — Реальная загрузка из ЕИС (US-2)

**Цель:** заменить мок на реальный SOAP-вызов ЕИС, скачивание/распаковку архива, парсинг XML извещений клининга по Москва+МО.

**Скоуп (in):** SOAP `getDocsByOrgRegionRequest` (HTTP Request с XML-телом, токен в заголовке `individualPerson_token`); получение archiveUrl; download с токеном; Unzip; парсинг XML (Code-нода, Python/JS) → нормализация (AC-2.3); инкрементальная загрузка по периодам; ретраи+backoff.
**Скоуп (out):** фильтрация, уведомления.

**Файлы:**
- Modify: `n8n/workflows/WF1_ingest.json` (замена заглушки на реальные ноды SOAP/download/unzip/parse).
- Create: `n8n/docs/eis-soap.md` (примеры запроса/ответа, структура XML извещения, маппинг полей).
- Create: `n8n/workflows/samples/` (сохранённые реальные XML-образцы для тестов парсинга).

**Зависимости:** Фаза 2, **Задача 0 (токен)**.

**Definition of Done:**
- WF1 реально тянет извещения 44-ФЗ по регионам [77,50] за период, фильтрует тип notification, парсит и пишет в `tenders` (AC-2.1..2.3).
- Идемпотентность по `reg_number+version` (AC-2.4).
- Один битый документ не валит весь прогон; ошибка → Error Workflow (AC-2.5).
- Backfill 14 дней при первом запуске (Q4), далее инкремент.

**Верификация:**
- Прогон WF1 с реальным токеном → в `tenders` появились реальные клининговые закупки МСК/МО; поля заполнены (SQL-выборка, ручная сверка 2–3 записей с сайтом zakupki.gov.ru).
- Повторный прогон → без дублей.
- Подсунуть битый XML из samples → запись в Error Workflow, остальные обработаны.

**Rollback:** `git revert HEAD` (вернёт мок-версию WF1); `truncate tenders`.

**Формат отложенного:** напр. `Deferred to Phase 2(fix): MAX-канал` — в tech-debt-tracker.

---

## Фаза 4 — Фильтрация по радарам (US-3)

**Цель:** сопоставление новых закупок с активными радарами, создание уникальных совпадений.

**Скоуп (in):** WF2 sub-workflow: чтение активных `radars`, матчинг по региону/ОКПД-префиксу/ключевым словам(incl/excl)/диапазону НМЦК/закону; upsert `matches` только для новых (AC-3.1..3.4); вызов WF2 из WF1.
**Скоуп (out):** уведомления, дашборд.

**Файлы:**
- Create: `n8n/workflows/WF2_filter.json`.
- Modify: `n8n/workflows/WF1_ingest.json` (Execute Workflow → WF2 после upsert).
- Create: `n8n/docs/matching-rules.md` (логика фильтра, edge-cases).

**Зависимости:** Фаза 1 (radars), Фаза 3 (реальные tenders).

**Definition of Done:**
- Для радара «Клининг МСК» новые подходящие закупки создают `matches`; неподходящие — нет (AC-3.2).
- Одна закупка под несколько радаров → один match-набор на пользователя, без повторов (AC-3.3, unique tender_id+radar_id).
- Повторный прогон не создаёт повторных matches (AC-3.4).

**Верификация:**
- Прогон WF1→WF2 → в `matches` корректные совпадения; проверка include/exclude ключевых слов (напр. exclude «вывоз мусора»).
- Повторный прогон → count matches не вырос.
- Радар с узким price_max → отсечение дорогих закупок подтверждено SQL-выборкой.

**Rollback:** `git revert HEAD`; `truncate matches`.

---

## Фаза 5 — Уведомления + напоминания (US-4)

**Цель:** рассылка дайджеста новых совпадений по каналам и напоминания о дедлайнах.

**Скоуп (in):** WF3 sub-workflow: группировка новых matches по пользователю/каналам, рендер дайджеста (HTML email + текст для мессенджеров), отправка Email(SMTP) ‖ VK ‖ MAX(HTTP) ‖ Telegram, запись в `notifications`, отметка `notified`; WF4 Schedule daily: напоминания по `status='interested'` с дедлайном ≤ reminder_days, отметка `reminded`. Ретраи; сбой канала не блокирует другие.
**Скоуп (out):** UI-настройка каналов сверх минимального (можно через таблицу users).

**Файлы:**
- Create: `n8n/workflows/WF3_notify.json`, `n8n/workflows/WF4_deadline.json`.
- Modify: `n8n/workflows/WF2_filter.json` (Execute → WF3).
- Create: `n8n/docs/notification-templates.md` (шаблоны дайджеста).
- Modify: `n8n/.env.example` (SMTP_*, VK_TOKEN, MAX_TOKEN, TELEGRAM_TOKEN).

**Зависимости:** Фаза 4.

**Definition of Done:**
- Новые matches → дайджест уходит по включённым каналам, поля по AC-4.2; пустой дайджест не шлётся (AC-4.3).
- Напоминание за reminder_days по «interested» (AC-4.4).
- Ретраи; сбой одного канала логируется, другие доставлены (AC-4.5); запись в `notifications`.
- **MAX:** если Bot API недоступен — `Deferred to Phase 2` в tech-debt (TD-5), MVP-каналы email+VK+Telegram.

**Верификация:**
- Тестовый прогон → письмо получено (Mailtrap/реальная почта), сообщение в Telegram-боте; запись в `notifications` со `status='sent'`.
- Симулировать сбой VK (битый токен) → `status='failed'` для VK, остальные `sent`.
- WF4: закупка с дедлайном через 2 дня и `interested` → напоминание пришло, `reminded=true`.

**Rollback:** `git revert HEAD`; отключить WF3/WF4 в N8N.

---

## Фаза 6 — Дашборд + календарь дедлайнов (US-5)

**Цель:** веб-интерфейс просмотра закупок и сроков, отметки «интересно»/«скрыть».

**Скоуп (in):** список закупок с фильтрами/сортировкой по дедлайну; карточка закупки; пометки interested/hidden (запись в matches.status); календарь/таймлайн дедлайнов по interested; Supabase Realtime-обновление.
**Скоуп (out):** аналитика, экспорт.

**Файлы:**
- Create: `web/app/tenders/page.tsx` (список+фильтры), `web/components/TenderCard.tsx`, `web/components/DeadlineCalendar.tsx`.
- Create: `web/lib/realtime.ts` (подписка на matches/tenders).
- Test: `web/__tests__/tenders.test.tsx`.

**Зависимости:** Фаза 1 (схема), Фаза 4 (matches).

**Definition of Done:**
- Список найденных закупок с фильтром по радару/статусу/дате, сортировка по дедлайну (AC-5.1).
- Карточка с полями AC-2.3 + ссылка ЕИС (AC-5.2).
- Пометки interested/hidden работают и сохраняются (AC-5.3).
- Календарь дедлайнов по interested (AC-5.4).
- Обновление близко к realtime (AC-5.5).

**Верификация:**
- `cd web && npm run build && npm run lint && npx tsc --noEmit && npm test` → exit 0.
- Ручная проверка: новые matches появляются в списке без перезагрузки; пометка interested → закупка в календаре.

**Rollback:** `git revert HEAD`.

---

## Фаза 7 — Hardening + портфолио-полировка (US-6 финал)

**Цель:** довести до прод/демо-уровня и оформить портфолио.

**Скоуп (in):** защита вебхуков (Header Auth/секрет); ревизия секретов (всё в .env/credential, ничего в git); полнота Error Workflow и ретраев; reverse-proxy (Caddy) + HTTPS для VPS; финальный экспорт всех воркфлоу в git; корневой `README.md` со схемой архитектуры (из ARCHITECTURE §2), GIF исполнения WF1, бизнес-метрикой; заполнить `docs/QUALITY_SCORE.md` портфолио-чеклист.
**Скоуп (out):** Фаза 2 проекта (LLM/CRM/223-ФЗ).

**Файлы:**
- Create: `README.md` (корень — портфолио-витрина).
- Create: `n8n/Caddyfile` (reverse-proxy, HTTPS).
- Modify: воркфлоу (защита вебхуков, ретраи где не хватает).
- Modify: `docs/QUALITY_SCORE.md` (отметить галочки).

**Зависимости:** Фазы 2–6.

**Definition of Done:**
- Все AC US-6 выполнены (6.1..6.5).
- Портфолио-чеклист в QUALITY_SCORE отмечен.
- README содержит схему + GIF + метрику; репо готов к публикации.

**Верификация:**
- Неавторизованный запрос к защищённому вебхуку → отклонён (curl без секрета = 401/403).
- `git grep` по репо → нет секретов (только в .env, который в .gitignore).
- Полный прогон WF1→WF2→WF3 на реальных данных → закупки→совпадения→уведомление, всё в БД.
- `cd web && npm run build` → exit 0.

**Rollback:** `git revert HEAD` по конкретному изменению.

---

## Глобальные правила исполнения

- Перед фазой: открыть фазу здесь, сверить `phase-registry.md`, отметить in_progress.
- Только активная фаза. Выход за скоуп → `Deferred to Phase N` в `docs/tech-debt-tracker.md` + `HANDOFF.md`.
- После фазы: verification зелёный → атомарный коммит → ревью SOLID+SRE → обновить PROGRESS/HANDOFF → следующая фаза.
- Конец commit-message: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
