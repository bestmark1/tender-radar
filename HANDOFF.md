# HANDOFF — Тендер-радар

Передача контекста между сессиями/агентами.

## Где мы

Пайплайн `phased-engineering-pipeline`, режим Full. Все gate пройдены. **Фазы 0, 1, 2 завершены.** Из-за КЭП-блокера ЕИС (TD-9) **Фаза 3 (реальный ЕИС) отложена**; идём к **Фазе 4 (фильтрация)** на мок-тендерах.

## Состояние окружения
- Supabase-проект создан (URL `https://xtxyporcywnpkdyatoxe.supabase.co`), миграция 0001 применена, Auth URL настроен. anon-ключ в `web/.env.local`. service_role у пользователя (в N8N позже).
- Dev-сервер: `cd web && npm run dev` → localhost:3000.
- **КЭП ЕИС (R1/TD-9):** пользователь — ИП, КЭП пока не оформляет. Источник Фазы 3 абстрагируем (мок/сторонний JSON-API).

## Что готово

- Репозиторий `tender-radar`, ветка `feature/tender-radar-mvp`.
- `SPEC_PLAN/`: Narrative, MRD, PRD, clarification, ARCHITECTURE, CONSTITUTION, IMPLEMENTATION_PLAN, phase-registry, cross-artifact-analysis.
- Корень: PROJECT_INDEX, AGENTS, PROGRESS, HANDOFF.
- `docs/`: README, EXECUTION_RULES, tech-debt-tracker, QUALITY_SCORE.
- **Фаза 0:** `web/` (Next.js 16 App Router, TS strict, ESLint flat config, vitest), `n8n/docker-compose.yml` (n8n+worker+Postgres+Redis, queue mode), `.env.example` (web + n8n), структура `supabase/migrations`, `n8n/workflows`. Все проверки exit 0.

## Состояние N8N (Фаза 2)
- Стек поднят (`n8n/docker-compose.yml`, queue mode). UI: localhost:5678 (owner-аккаунт пользователь создаёт сам при первом входе).
- Воркфлоу: WF0 `AF15RiHM3PhZEpS3` (error handler, active в файле — включить тумблером в UI), WF1 `RNZXUe3Xdw461tHg` (ingest, errorWorkflow→WF0). Файлы `n8n/workflows/*.json` со стабильными id.
- `n8n/.env`: service_role вписан пользователем (формат `sb_secret_...`). Воркфлоу читают Supabase через `$env`.
- В Supabase `tenders` — 3 мок-клининговых тендера (результат WF1).
- Прогон/импорт: см. `n8n/README.md`. Прогон в одноразовом контейнере: `docker compose run --rm --no-deps -e EXECUTIONS_MODE=regular -e N8N_RUNNERS_ENABLED=false n8n execute --id <id>`.

## Следующий шаг — Фаза 4 (фильтрация, US-3) на мок-данных

WF2 sub-workflow: читать активные `radars` (Supabase) → матчить с `tenders` по региону/ОКПД-префиксу/ключевым словам/цене/закону → upsert `matches` (только новые). Вызов WF2 из WF1 после upsert. Есть реальный радар «Клининг МСК» (создан в Фазе 1) и 3 мок-тендера — готовый материал для проверки.
**Фаза 3 (реальный ЕИС SOAP) отложена** — нужен КЭП (TD-9); источник абстрагирован, подключим позже (КЭП или сторонний JSON-API).

## Важные напоминания

- Бизнес-данные → Supabase, НЕ в БД N8N (ADR-1).
- Только активная фаза. Атомарные коммиты.
- Задача 0 (токен ЕИС) — блокер US-2, действие пользователя.
- MAX (R8) и объём Москва+МО (R9) — под наблюдением.
