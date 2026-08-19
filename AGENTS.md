# AGENTS.md — Тендер-радар

Карта проекта для AI-агентов и разработчиков. Читать первым.

## Что это

Веб-сервис мониторинга госзакупок 44-ФЗ для поставщиков-клинеров. N8N (self-hosted) забирает извещения из ЕИС, фильтрует по правилам пользователя, шлёт подборку с дедлайнами (email/VK/MAX/Telegram). Фронт — Next.js на Vercel, данные — Supabase.

## Цель проекта

Первый сильный портфолио-кейс на N8N (бэкграунд разработчика — Python) + реально востребованный B2B-продукт в РФ. → Качество исполнения и «галочки» low-code важнее ширины фич.

## Структура репозитория (целевая)

```
PROJECT_INDEX.md          навигация
AGENTS.md                 этот файл
PROGRESS.md / HANDOFF.md  состояние исполнения
SPEC_PLAN/                продукт + архитектура + план
docs/                     знания, правила, tech-debt, quality
web/                      Next.js приложение (Vercel)
n8n/
  docker-compose.yml      n8n + Postgres(служебная) + Redis
  workflows/*.json        экспортированные воркфлоу (версионируются)
supabase/
  migrations/*.sql        схема БД бизнес-данных
tasks/                    решения тестовых заданий (вне фазового цикла,
                          PROGRESS/HANDOFF/phase-registry не затрагивают)
.env.example              шаблон секретов (реальные — вне git)
```

## Правила (обязательно)

- Источник истины смысла — markdown в `SPEC_PLAN/`/`docs/`. Источник истины статуса — `PROGRESS.md`.
- Исполнять **только активную фазу** (см. IMPLEMENTATION_PLAN.md). Не тянуть будущие фазы.
- Атомарные коммиты, один change = один коммит. Конец commit-message:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Секреты — только `.env`/credential store, никогда в git.
- N8N-воркфлоу экспортировать в `n8n/workflows/*.json` после изменений.
- Verification обязателен (см. CONSTITUTION §4). «Done» без зелёных проверок не принимается.

## Команды

| Действие | Команда |
|---|---|
| Build фронта | `npm run build` (в `web/`) |
| Lint | `npm run lint` |
| Typecheck | `tsc --noEmit` |
| Тесты | `npm test` |
| Поднять N8N | `docker compose -f n8n/docker-compose.yml up -d` |
| Откат | `git revert HEAD` |

## Внешние зависимости

- **ЕИС SOAP:** `https://int44.zakupki.gov.ru/eis-integration/services/getDocsIP` — токен `individualPerson_token` в заголовке. Задача 0 (Госуслуги) — блокер US-2.
- **Supabase** (managed), **Vercel** (фронт), **VK / MAX / Telegram Bot API**, **SMTP** (Яндекс).
- Документация: N8N https://docs.n8n.io , Next.js https://nextjs.org/docs , Supabase https://supabase.com/docs

## Чего НЕ делать

- Не использовать Telegram как единственный канал.
- Не складывать бизнес-данные в БД N8N (только Supabase).
- Не реализовывать Фазу 2 (LLM, CRM, 223-ФЗ) в MVP.
- Не перепродавать N8N как сервис (лицензия fair-code).
