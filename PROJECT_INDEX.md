# Тендер-радар — Project Index

Навигационный хаб проекта. Веб-сервис мониторинга госзакупок 44-ФЗ для поставщиков; движок автоматизации — N8N (self-hosted).

## Быстрый старт для агента/разработчика

1. Прочитать `AGENTS.md` — карта проекта и правила.
2. Прочитать `SPEC_PLAN/CONSTITUTION.md` — незыблемые правила.
3. Найти активную фазу в `SPEC_PLAN/IMPLEMENTATION_PLAN.md`.
4. Сверить скоуп в `SPEC_PLAN/phase-registry.md`.
5. Исполнять только активную фазу. Обновлять `PROGRESS.md` / `HANDOFF.md`.

## Карта артефактов

### Продукт (что и зачем)
- [Narrative](SPEC_PLAN/Narrative.md) — история, why now, мир пользователя, риски, не-цели.
- [MRD](SPEC_PLAN/MRD.md) — ICP, JTBD, конкуренты, позиционирование.
- [PRD](SPEC_PLAN/PRD.md) — user stories US-1..US-6, критерии приёмки.
- [Clarification Report](SPEC_PLAN/clarification-report.md) — открытые вопросы и дефолты.

### Архитектура (как)
- [ARCHITECTURE](SPEC_PLAN/ARCHITECTURE.md) — компоненты, потоки, схема БД, воркфлоу, ADR.
- [CONSTITUTION](SPEC_PLAN/CONSTITUTION.md) — правила и стандарты.

### Исполнение
- [IMPLEMENTATION_PLAN](SPEC_PLAN/IMPLEMENTATION_PLAN.md) — фазы (создаётся Tech Lead).
- [phase-registry](SPEC_PLAN/phase-registry.md) — реестр фаз/статусов.
- [cross-artifact-analysis](SPEC_PLAN/cross-artifact-analysis.md) — проверка согласованности (Analyzer).
- [PROGRESS](PROGRESS.md) · [HANDOFF](HANDOFF.md)

### Документация
- [docs/README](docs/README.md) · [docs/EXECUTION_RULES](docs/EXECUTION_RULES.md)
- [docs/tech-debt-tracker](docs/tech-debt-tracker.md) · [docs/QUALITY_SCORE](docs/QUALITY_SCORE.md)

## Ключевые факты

| Параметр | Значение |
|---|---|
| Скоуп MVP | 44-ФЗ, клининг (ОКПД2 81.2), Москва+МО, 1 пользователь |
| Стек | Next.js (Vercel) + Supabase + N8N (Docker, queue mode + Redis) |
| Каналы | email, VK, MAX, Telegram (демо) |
| Источник | SOAP ЕИС `getDocsByOrgRegionRequest`, токен физлица/ИП |
| Блокер | Задача 0: токен потребителя машиночитаемых данных (Госуслуги) |
| Фаза 2 | LLM-скоринг, CRM (Битрикс24/amoCRM), 223-ФЗ, мультиарендность |
