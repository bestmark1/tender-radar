-- =====================================================================
-- Задание 6 — миграция 0002: история изменений статуса тендера
-- =====================================================================
-- Продолжает схему marketplace из задания 4 (01_schema.sql — «миграция 0001»).
-- Вынесена в отдельный файл намеренно: схема площадки и аудит статусов
-- версионируются независимо, аудит можно накатить на уже работающую базу.
--
-- Запуск:  psql -v ON_ERROR_STOP=1 -f 0002_tender_status_history.sql
-- =====================================================================

\set ON_ERROR_STOP on
set search_path = marketplace, public;

create table if not exists tender_status_history (
  id          uuid primary key default gen_random_uuid(),
  tender_id   uuid not null references tenders (id) on delete cascade,

  -- NULL означает создание тендера: предыдущего статуса не существовало.
  -- Именно поэтому колонка nullable, а не заполнена пустой строкой:
  -- «статуса не было» и «статус пустой» — разные утверждения.
  from_status text,
  to_status   text not null,

  -- Кто и почему. changed_by — идентификатор действующего лица, приходит
  -- из слоя аутентификации; хранится как text, чтобы запись аудита
  -- пережила удаление пользователя (FK с ON DELETE SET NULL стёр бы
  -- ровно ту информацию, ради которой аудит и ведётся).
  changed_by  text not null,
  reason      text,

  changed_at  timestamptz not null default now(),

  constraint tsh_to_status_valid   check (to_status   in ('draft','active','won','lost')),
  constraint tsh_from_status_valid check (from_status is null
                                          or from_status in ('draft','active','won','lost')),
  -- переход «в тот же статус» — не изменение, писать его в историю незачем
  constraint tsh_status_changed    check (from_status is distinct from to_status),
  constraint tsh_changed_by_filled check (length(btrim(changed_by)) > 0)
);

-- Основной доступ — «вся история одного тендера в обратном хронологическом
-- порядке». Составной индекс закрывает и отбор, и сортировку: отдельный
-- индекс по tender_id потребовал бы досортировки результата.
create index if not exists tsh_tender_changed_at_idx
  on tender_status_history (tender_id, changed_at desc);

-- Под отчёт «кто что менял за период» (разбор инцидентов).
create index if not exists tsh_changed_by_idx
  on tender_status_history (changed_by, changed_at desc);

comment on table  tender_status_history is
  'Аудит переходов статуса тендера: кто, когда, с какого на какой и почему';
comment on column tender_status_history.from_status is
  'NULL — запись о создании тендера, предыдущего статуса не было';
