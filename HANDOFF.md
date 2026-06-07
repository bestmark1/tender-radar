# HANDOFF — Тендер-радар

Передача контекста между сессиями/агентами.

## Где мы

Пайплайн `phased-engineering-pipeline`, режим Full. Все gate (продукт/архитектура/план/analyze) пройдены. **Фаза 0 завершена.** Идём к Фазе 1.

## Что готово

- Репозиторий `tender-radar`, ветка `feature/tender-radar-mvp`.
- `SPEC_PLAN/`: Narrative, MRD, PRD, clarification, ARCHITECTURE, CONSTITUTION, IMPLEMENTATION_PLAN, phase-registry, cross-artifact-analysis.
- Корень: PROJECT_INDEX, AGENTS, PROGRESS, HANDOFF.
- `docs/`: README, EXECUTION_RULES, tech-debt-tracker, QUALITY_SCORE.
- **Фаза 0:** `web/` (Next.js 16 App Router, TS strict, ESLint flat config, vitest), `n8n/docker-compose.yml` (n8n+worker+Postgres+Redis, queue mode), `.env.example` (web + n8n), структура `supabase/migrations`, `n8n/workflows`. Все проверки exit 0.

## Следующий шаг — Фаза 1 (US-1)

`supabase/migrations/0001_init.sql` (таблицы + RLS), Supabase Auth (magic link), CRUD радаров во фронте, генерация типов БД, тест валидации US-1.4.
**Учесть из cross-artifact-analysis:** A2 (триггер на создание строки `users` при signup), A3 (RLS для `tenders`: read authenticated, write service_role), A1 (Фаза 2 зависит от Фазы 1). Подключить тесты → заодно закрыть TD-7 (vitest 3.x).

## Важные напоминания

- Бизнес-данные → Supabase, НЕ в БД N8N (ADR-1).
- Только активная фаза. Атомарные коммиты.
- Задача 0 (токен ЕИС) — блокер US-2, действие пользователя.
- MAX (R8) и объём Москва+МО (R9) — под наблюдением.
