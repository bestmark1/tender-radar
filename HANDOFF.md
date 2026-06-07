# HANDOFF — Тендер-радар

Передача контекста между сессиями/агентами.

## Где мы

Пайплайн `phased-engineering-pipeline`, режим Full. Пройдены: продуктовый gate. Завершена архитектура, ожидает архитектурного USER APPROVAL gate. Дальше — Tech Lead (IMPLEMENTATION_PLAN + phase-registry).

## Что готово

- Репозиторий `tender-radar`, ветка `feature/tender-radar-mvp`.
- `SPEC_PLAN/`: Narrative, MRD, PRD, clarification-report, ARCHITECTURE, CONSTITUTION.
- Корень: PROJECT_INDEX, AGENTS, PROGRESS, HANDOFF.
- `docs/`: README, EXECUTION_RULES, tech-debt-tracker, QUALITY_SCORE.

## Следующий шаг

После архитектурного gate — создать `SPEC_PLAN/IMPLEMENTATION_PLAN.md` (фазы с DoD/verification/rollback) и `phase-registry.md`.

## Важные напоминания

- Бизнес-данные → Supabase, НЕ в БД N8N (ADR-1).
- Только активная фаза. Атомарные коммиты.
- Задача 0 (токен ЕИС) — блокер US-2, действие пользователя.
- MAX (R8) и объём Москва+МО (R9) — под наблюдением.
