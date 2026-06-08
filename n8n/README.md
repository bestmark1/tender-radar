# N8N — движок автоматизации Тендер-радара

Self-hosted, **queue mode** (n8n main + worker + Postgres + Redis). Бизнес-данные пишутся в **Supabase** (ADR-1); локальная Postgres здесь — только execution-история n8n.

## Запуск

```bash
cp .env.example .env          # заполнить секреты (см. ниже)
docker compose up -d
# UI: http://localhost:5678  (при первом запуске — создать owner-аккаунт)
```

### Секреты в `.env` (в git НЕ коммитятся)
- `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY` — генерируются (`openssl rand -hex`).
- `SUPABASE_URL` — URL проекта Supabase.
- `SUPABASE_SERVICE_ROLE` — service_role ключ (Supabase → Settings → API). Нужен для записи в `tenders` (минует RLS). **Секрет.**
- `EIS_TOKEN` — токен ЕИС (Фаза 3, требует КЭП — см. tech-debt TD-9).

Воркфлоу читают Supabase через `{{ $env.SUPABASE_URL }}` / `{{ $env.SUPABASE_SERVICE_ROLE }}`
(`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`), поэтому секрет живёт только в `.env`.

## Воркфлоу (версионируются как JSON)

| Файл | Назначение |
|---|---|
| `workflows/WF0_error.json` | Глобальный Error Workflow (лог сбоев; алерт — Фаза 5/7) |
| `workflows/WF1_ingest.json` | Schedule/Manual → мок-извещения (клининг) → upsert в Supabase `tenders` |

В Фазе 3 заглушка в WF1 заменяется реальным SOAP-вызовом ЕИС.

### Импорт / экспорт через CLI

```bash
# импорт всех воркфлоу из папки (папка примонтирована как /workflows)
docker compose exec n8n n8n import:workflow --separate --input=/workflows

# список воркфлоу с id
docker compose exec n8n n8n list:workflow

# прогон воркфлоу по id (например WF1)
docker compose exec n8n n8n execute --id <workflow_id>

# экспорт обратно в JSON (после правок в UI)
docker compose exec n8n n8n export:workflow --all --separate --output=/workflows
```
