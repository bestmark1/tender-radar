# EXECUTION_RULES — Тендер-радар

Правила исполнения. Производны от `SPEC_PLAN/CONSTITUTION.md`.

## Цикл фазы

1. Открыть активную фазу в `IMPLEMENTATION_PLAN.md`, сверить скоуп в `phase-registry.md`.
2. Реализовать **только** её. Выход за скоуп → `Deferred to Phase N` в tech-debt-tracker.
3. Прогнать verification-команды фазы (должны вернуть exit 0).
4. Self-review: verify → fix → re-verify.
5. Атомарный коммит (один change = один коммит).
6. Ревью SOLID + SRE. Замечания → fix → recommit → re-review.
7. Оба APPROVE → обновить `PROGRESS.md` / `HANDOFF.md` → следующая фаза.

## Гейты (STRICT_MODE=true — блокирующие)

- Продуктовый gate (после PRD) — ✅ пройден.
- Архитектурный gate (после ARCHITECTURE) — текущий.
- План gate (после IMPLEMENTATION_PLAN).
- Analyze gate (после cross-artifact-analysis).
- Per-phase review gate (SOLID+SRE).
- QA gate (трассировка критериев приёмки PRD).

## Verification matrix

| Уровень | Что | Когда |
|---|---|---|
| Basic | exit codes, lint, typecheck, unit | каждая кодовая фаза |
| Medium | интеграционные/smoke, прогон воркфлоу с реальным входом | QA |
| High | логи/метрики прод-демо | после деплоя (вне скилла) |

## Definition of Done (общее)

Скоуп фазы закрыт · все проверки зелёные · PROGRESS/HANDOFF обновлены · отложенное записано · SOLID+SRE одобрили.
