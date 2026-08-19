-- =====================================================================
-- Задание 4 — Схема БД «Тендерная площадка»  (PostgreSQL 14+)
-- =====================================================================
-- Развитие модели данных Тендер-Радара (см. supabase/migrations/0001_init.sql)
-- до полноценной площадки: к «извещениям» добавляются лоты, ставки участников
-- и исполнение контрактов.
--
-- Запуск:  psql -v ON_ERROR_STOP=1 -f 01_schema.sql
-- Идемпотентность обеспечивается пересозданием схемы marketplace целиком.
-- =====================================================================

\set ON_ERROR_STOP on

-- Расширения ставим в public: они общие для всей БД и не должны исчезать
-- вместе с пересозданием прикладной схемы.
create extension if not exists pgcrypto with schema public;  -- gen_random_uuid()
create extension if not exists pg_trgm  with schema public;  -- GIN trigram по названию лота

drop schema if exists marketplace cascade;
create schema marketplace;
set search_path = marketplace, public;

-- ---------------------------------------------------------------------
-- Общая функция для автообновления updated_at.
-- Одна на всю схему: дублировать её в каждой таблице незачем.
-- ---------------------------------------------------------------------
create function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- =====================================================================
-- 1. companies — единый справочник юрлиц
-- =====================================================================
-- Заказчик и поставщик — это одна и та же сущность «организация»,
-- отличается только роль в конкретной закупке. Одна компания может быть
-- заказчиком в одном тендере и участником в другом, поэтому разделять
-- на customers/suppliers нельзя: получим дублирование реквизитов и
-- рассинхрон при обновлении данных из ЕГРЮЛ.
-- Роль выражена флагами, а не отдельной таблицей ролей: ролей ровно две
-- и новых не предвидится.
-- =====================================================================
create table companies (
  id            uuid primary key default gen_random_uuid(),
  inn           text not null,
  kpp           text,
  ogrn          text,
  short_name    text not null,
  full_name     text,
  region_code   text not null,                    -- код субъекта РФ, '77'
  is_customer   boolean not null default false,   -- может публиковать закупки
  is_supplier   boolean not null default false,   -- может подавать ставки
  is_blacklisted boolean not null default false,  -- РНП (реестр недобросов.)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- ИНН: 10 знаков у юрлица, 12 у ИП
  constraint companies_inn_format   check (inn ~ '^[0-9]{10}$' or inn ~ '^[0-9]{12}$'),
  constraint companies_kpp_format   check (kpp is null  or kpp  ~ '^[0-9]{9}$'),
  constraint companies_ogrn_format  check (ogrn is null or ogrn ~ '^[0-9]{13,15}$'),
  constraint companies_region_format check (region_code ~ '^[0-9]{2,3}$'),
  -- организация без единой роли — мусорная запись
  constraint companies_has_role     check (is_customer or is_supplier)
);

-- ИНН+КПП уникальны в паре: у головной организации и филиала ИНН общий,
-- КПП разный. Для ИП КПП отсутствует — отсюда два частичных индекса
-- вместо одного составного (NULL в UNIQUE не сравниваются между собой,
-- и без частичного индекса дубли ИП прошли бы незамеченными).
create unique index companies_inn_kpp_uniq on companies (inn, kpp) where kpp is not null;
create unique index companies_inn_uniq     on companies (inn)      where kpp is null;

create index companies_region_idx   on companies (region_code);
-- под подбор доступных поставщиков по региону (компании в РНП исключены)
create index companies_supplier_region_idx on companies (region_code)
  where is_supplier and not is_blacklisted;

create trigger companies_set_updated_at before update on companies
  for each row execute function set_updated_at();

-- =====================================================================
-- 2. tenders — закупка (извещение)
-- =====================================================================
-- Статусы взяты те же, что требует задание 6 (Черновик/Активен/Выигран/
-- Проигран): это взгляд участника площадки, а не оператора ЕИС, и он же
-- нужен сервису трекинга. Держать два разных набора статусов на одну
-- сущность — прямой путь к рассинхрону.
-- =====================================================================
create table tenders (
  id                  uuid primary key default gen_random_uuid(),
  reg_number          text not null,                   -- реестровый номер ЕИС
  version             int  not null default 1,         -- редакция извещения
  customer_id         uuid not null references companies (id) on delete restrict,
  title               text not null,
  law                 text not null default '44',      -- 44-ФЗ | 223-ФЗ
  procedure_type      text not null default 'auction', -- форма закупки
  region_code         text not null,
  status              text not null default 'draft',
  nmck_total          numeric(15,2),                   -- сумма НМЦК всех лотов
  published_at        timestamptz,
  submission_deadline timestamptz,                     -- окончание приёма заявок
  eis_url             text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- одна редакция извещения — одна строка (идемпотентный upsert из ЕИС)
  constraint tenders_regnum_version_uniq unique (reg_number, version),
  constraint tenders_law_valid    check (law in ('44','223')),
  constraint tenders_status_valid check (status in ('draft','active','won','lost')),
  constraint tenders_procedure_valid check (
    procedure_type in ('auction','contest','quotation','single_supplier')
  ),
  constraint tenders_nmck_positive check (nmck_total is null or nmck_total > 0),
  -- опубликованная закупка обязана иметь дату публикации и дедлайн
  constraint tenders_published_fields check (
    status = 'draft'
    or (published_at is not null and submission_deadline is not null)
  ),
  -- приём заявок не может закрываться раньше публикации
  constraint tenders_deadline_after_publish check (
    published_at is null or submission_deadline is null
    or submission_deadline > published_at
  )
);

create index tenders_customer_idx on tenders (customer_id);
create index tenders_region_idx   on tenders (region_code);
create index tenders_status_idx   on tenders (status);
-- Частичный индекс под самый горячий запрос площадки — «открытые закупки,
-- у которых скоро дедлайн». В индекс попадает только активная часть таблицы
-- (единицы процентов от общего объёма), а не весь исторический архив.
create index tenders_active_deadline_idx on tenders (submission_deadline)
  where status = 'active';
-- Составной индекс под витрину «свежие закупки по региону»: порядок колонок
-- задан по правилу равенство-до-диапазона (region_code = ..., published_at > ...).
create index tenders_region_published_idx on tenders (region_code, published_at desc);

create trigger tenders_set_updated_at before update on tenders
  for each row execute function set_updated_at();

-- =====================================================================
-- 3. lots — лоты внутри закупки
-- =====================================================================
-- Отдельная таблица, а не поля в tenders: закупка может содержать
-- несколько лотов, торги и победитель определяются по каждому лоту
-- независимо. Именно лот, а не тендер, — предмет ставки и контракта.
-- =====================================================================
create table lots (
  id             uuid primary key default gen_random_uuid(),
  tender_id      uuid not null references tenders (id) on delete cascade,
  lot_number     int  not null,
  title          text not null,
  okpd2          text not null,                   -- '81.29.19.000'
  nmck           numeric(15,2) not null,          -- начальная (максимальная) цена
  currency       char(3) not null default 'RUB',
  quantity       numeric(14,3),
  unit           text,
  delivery_place text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint lots_number_uniq  unique (tender_id, lot_number),
  constraint lots_nmck_positive check (nmck > 0),
  -- ОКПД2: 2 цифры класса и до трёх уточняющих групп по 1–3 цифры
  -- ('81.2', '81.29.19', '43.999', '81.29.19.000')
  constraint lots_okpd2_format  check (okpd2 ~ '^[0-9]{2}(\.[0-9]{1,3}){0,3}$'),
  constraint lots_quantity_positive check (quantity is null or quantity > 0)
);

-- ON DELETE CASCADE не создаёт индекс автоматически, а удаление тендера
-- без него приводит к seq scan по lots на каждую строку.
create index lots_tender_idx on lots (tender_id);
-- text_pattern_ops — чтобы отбор по префиксу ОКПД2 (LIKE '81.2%'), на котором
-- построена фильтрация радаров, шёл по индексу независимо от локали БД.
create index lots_okpd2_prefix_idx on lots (okpd2 text_pattern_ops);
create index lots_nmck_idx  on lots (nmck);
create index lots_title_trgm_idx on lots using gin (title gin_trgm_ops);

create trigger lots_set_updated_at before update on lots
  for each row execute function set_updated_at();

-- =====================================================================
-- 4. bids — ставки участников
-- =====================================================================
create table bids (
  id           uuid primary key default gen_random_uuid(),
  lot_id       uuid not null references lots (id) on delete cascade,
  supplier_id  uuid not null references companies (id) on delete restrict,
  amount       numeric(15,2) not null,        -- предложенная цена
  status       text not null default 'submitted',
  submitted_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- одна действующая ставка компании на лот
  constraint bids_lot_supplier_uniq unique (lot_id, supplier_id),
  constraint bids_amount_positive   check (amount > 0),
  constraint bids_status_valid check (
    status in ('submitted','withdrawn','rejected','won','lost')
  )
);

create index bids_lot_idx      on bids (lot_id);
create index bids_supplier_idx on bids (supplier_id);
-- Покрывающий индекс под «лучшая ставка по лоту»: INCLUDE(amount) позволяет
-- отдать цену из индекса, не заглядывая в heap (index-only scan).
create index bids_lot_amount_idx on bids (lot_id, amount) include (supplier_id);
create index bids_submitted_idx on bids (submitted_at desc);

-- Победитель на лоте может быть только один. Это инвариант торгов, поэтому
-- он закрыт частичным уникальным индексом на уровне БД, а не проверкой
-- в коде приложения: гонка двух параллельных транзакций иначе создаст двух
-- победителей, и рассыплется вся аналитика по выигранным суммам.
create unique index bids_single_winner_per_lot on bids (lot_id) where status = 'won';

-- Технические UNIQUE-ключи: сами по себе избыточны (id уже PK), но именно они
-- позволяют сослаться на bids составным внешним ключом из contractors и тем
-- самым сделать согласованность контракта и ставки задачей БД (см. ниже).
alter table bids add constraint bids_id_lot_uniq      unique (id, lot_id);
alter table bids add constraint bids_id_supplier_uniq unique (id, supplier_id);

create trigger bids_set_updated_at before update on bids
  for each row execute function set_updated_at();

-- =====================================================================
-- 5. contractors — исполнители (контракт по выигранному лоту)
-- =====================================================================
-- «Исполнитель» — не отдельное юрлицо, а роль компании на конкретном лоте:
-- та же организация из companies, выигравшая торги и подписавшая контракт.
-- Поэтому таблица хранит не реквизиты (они уже есть в companies), а факт
-- и параметры исполнения: контракт, суммы, сроки, итог.
-- =====================================================================
create table contractors (
  id                 uuid primary key default gen_random_uuid(),
  lot_id             uuid not null references lots (id) on delete restrict,
  company_id         uuid not null references companies (id) on delete restrict,
  bid_id             uuid not null references bids (id) on delete restrict,
  -- Составные FK вместо проверок в коде: контракт физически не может ссылаться
  -- на ставку с другого лота или поданную другой компанией. Обычные одиночные
  -- FK этого не ловят — каждый из трёх ключей по отдельности был бы валиден.
  constraint contractors_bid_matches_lot
    foreign key (bid_id, lot_id)     references bids (id, lot_id),
  constraint contractors_bid_matches_company
    foreign key (bid_id, company_id) references bids (id, supplier_id),
  contract_number    text not null,
  contract_amount    numeric(15,2) not null,     -- цена контракта = сумма победившей ставки
  signed_at          timestamptz not null,
  execution_deadline date,
  completed_at       timestamptz,
  status             text not null default 'signed',
  penalty_amount     numeric(15,2) not null default 0,  -- начисленные штрафы/пени

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  -- один исполненный контракт на лот
  constraint contractors_lot_uniq      unique (lot_id),
  -- ставка не может быть основанием сразу для двух контрактов
  constraint contractors_bid_uniq      unique (bid_id),
  constraint contractors_number_uniq   unique (contract_number),
  constraint contractors_amount_positive check (contract_amount > 0),
  constraint contractors_penalty_nonneg  check (penalty_amount >= 0),
  constraint contractors_status_valid check (
    status in ('signed','in_progress','completed','terminated')
  ),
  -- завершённый контракт обязан иметь дату завершения, незавершённый — не может
  constraint contractors_completed_consistent check (
    (status = 'completed' and completed_at is not null)
    or (status <> 'completed' and completed_at is null)
  ),
  constraint contractors_completed_after_sign check (
    completed_at is null or completed_at >= signed_at
  )
);

create index contractors_company_idx  on contractors (company_id);
create index contractors_bid_idx      on contractors (bid_id);
-- Основной индекс аналитики: «кто сколько выиграл за период».
-- signed_at первым — по нему идёт отбор диапазона; company_id и сумма
-- в INCLUDE, чтобы агрегация топ-поставщиков закрывалась index-only scan'ом.
create index contractors_signed_at_idx on contractors (signed_at desc)
  include (company_id, contract_amount);
create index contractors_status_idx    on contractors (status);
-- контроль исполнения: только действующие контракты с приближающимся сроком
create index contractors_active_deadline_idx on contractors (execution_deadline)
  where status in ('signed','in_progress');

create trigger contractors_set_updated_at before update on contractors
  for each row execute function set_updated_at();

-- =====================================================================
-- Комментарии к объектам — схема должна читаться из самой БД (\d+),
-- а не только из этого файла.
-- =====================================================================
comment on table companies   is 'Справочник организаций: заказчики и поставщики (роль задаётся флагами)';
comment on table tenders     is 'Закупка (извещение). Статусы совпадают с сервисом трекинга (задание 6)';
comment on table lots        is 'Лот закупки — предмет ставки и контракта';
comment on table bids        is 'Ценовые предложения участников по лоту';
comment on table contractors is 'Исполнитель: компания, выигравшая лот, и параметры контракта';

comment on column tenders.version        is 'Редакция извещения ЕИС; (reg_number, version) уникальны';
comment on column contractors.company_id is 'Дублирует bids.supplier_id ради аналитики без лишнего join; согласованность гарантирует составной FK contractors_bid_matches_company';
