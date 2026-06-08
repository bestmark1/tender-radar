# HANDOFF — Тендер-радар

Передача контекста между сессиями/агентами.

## Где мы

Пайплайн `phased-engineering-pipeline`, режим Full. Все gate пройдены. **Фазы 0 и 1 завершены** (US-1 проверен e2e на реальной Supabase). Идём к Фазе 2.

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

## Следующий шаг — Фаза 2 (N8N: инфра + Error WF + ingest-скелет)

`n8n/workflows/WF0_error.json` (Error Workflow), `WF1_ingest.json` (Schedule → Code-нода-заглушка с 2–3 фейковыми клининговыми извещениями → upsert в Supabase `tenders`). Credential Supabase service_role в N8N (НЕ в git). Экспорт воркфлоу в JSON. Проверка: ручной прогон WF1 → строки в `tenders`, идемпотентность, Error WF ловит ошибку, queue mode.
**Токен/КЭП ЕИС не нужны** (реальный SOAP — Фаза 3). Зависит от Фазы 1 (таблица `tenders` есть).

## Важные напоминания

- Бизнес-данные → Supabase, НЕ в БД N8N (ADR-1).
- Только активная фаза. Атомарные коммиты.
- Задача 0 (токен ЕИС) — блокер US-2, действие пользователя.
- MAX (R8) и объём Москва+МО (R9) — под наблюдением.
