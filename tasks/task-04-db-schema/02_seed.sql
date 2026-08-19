-- =====================================================================
-- Задание 4 — генерация тестовых данных
-- =====================================================================
-- Данные синтетические, но с правдоподобным распределением: без него
-- планировщик строит планы по равномерной модели, и замеры на такой базе
-- ничего не говорят о поведении на проде.
--
-- Заложено намеренно:
--   * перекос по регионам — Москва и МО дают ~40% закупок (как в ЕИС);
--   * длинный хвост поставщиков — большинство подаёт 1–2 ставки,
--     единицы участвуют в сотнях торгов;
--   * распределение по времени за 18 месяцев — чтобы фильтр
--     «за последний месяц» реально отсекал большую часть таблицы;
--   * лоты без ставок (несостоявшиеся закупки) — иначе аналитика
--     не увидит случая с нулевым знаменателем.
--
-- Запуск:  psql -v ON_ERROR_STOP=1 -f 02_seed.sql
-- Время:   ~20–40 с, объём ~500 тыс. строк.
-- =====================================================================

\set ON_ERROR_STOP on
set search_path = marketplace, public;

-- Фиксируем зерно ГСЧ — оно отвечает за разброс сумм и дат.
select setseed(0.4242);

-- Выбор «случайной» строки из справочника делается не через random(),
-- а через хеш от ключа строки-источника. Причина принципиальная:
-- некоррелированный random() внутри LATERAL планировщик вправе вычислить
-- один раз на весь запрос, и тогда, например, все 50 000 закупок получат
-- один и тот же статус. Хеш от идентификатора строки коррелирован по
-- построению, считается ровно один раз на строку и не зависит от того,
-- какой план выбрал планировщик.
create function pg_temp.pick(seed text, n int) returns int
language sql immutable as $$
  select 1 + (hashtext(seed) & 2147483647) % n
$$;

-- То же, но со смещением к началу диапазона (степень > 1): нужно для
-- длинного хвоста активности поставщиков.
create function pg_temp.pick_skewed(seed text, n int, power_ float8) returns int
language sql immutable as $$
  select 1 + floor(power((hashtext(seed) & 2147483647)::float8 / 2147483647.0, power_) * n)::int
$$;

truncate contractors, bids, lots, tenders, companies restart identity cascade;

-- ---------------------------------------------------------------------
-- Справочники значений
-- ---------------------------------------------------------------------
create temp table ref_regions (region_code text, weight int);
insert into ref_regions values
  ('77', 25), ('50', 15), ('78', 8), ('66', 5), ('16', 5), ('23', 5),
  ('54', 4), ('52', 4), ('61', 4), ('74', 4), ('24', 3), ('36', 3),
  ('63', 3), ('34', 2), ('72', 2), ('59', 2), ('02', 2), ('47', 2);

-- «Развёртка» весов в плоский список: выбор случайного элемента из него
-- сразу даёт нужное распределение, без вычисления кумулятивных сумм.
-- Первичный ключ по idx обязателен — выборка идёт точечным поиском
-- по случайному номеру, а не сортировкой пула на каждой строке.
create temp table region_pool (idx int generated always as identity primary key, region_code text);
insert into region_pool (region_code)
select region_code from ref_regions, generate_series(1, weight);

create temp table ref_okpd (idx int generated always as identity primary key, okpd2 text, title text);
insert into ref_okpd (okpd2, title) values
  ('81.29.11', 'Услуги по дезинфекции и дератизации помещений'),
  ('81.21.10', 'Услуги по общей уборке зданий'),
  ('81.22.11', 'Услуги по мытью окон и фасадов'),
  ('81.29.19', 'Услуги по уборке прилегающей территории'),
  ('62.01.11', 'Разработка программного обеспечения'),
  ('62.02.30', 'Техническая поддержка информационных систем'),
  ('43.999',   'Работы строительные специализированные прочие'),
  ('33.12.29', 'Ремонт и техническое обслуживание оборудования'),
  ('86.90.19', 'Услуги в области медицины прочие'),
  ('49.41.19', 'Перевозка грузов автомобильным транспортом');

-- ---------------------------------------------------------------------
-- 1. companies — 5 000 организаций
-- ---------------------------------------------------------------------
insert into companies (inn, kpp, ogrn, short_name, full_name, region_code,
                       is_customer, is_supplier, is_blacklisted)
select
  lpad((1000000000 + g)::text, 10, '0')                             as inn,
  lpad((100000000 + g)::text, 9, '0')                               as kpp,
  lpad((1000000000000 + g)::text, 13, '0')                          as ogrn,
  case when g % 7 = 0 then 'ГБУ «Организация №'  || g || '»'
       when g % 3 = 0 then 'ООО «Поставщик-'     || g || '»'
       else                'АО «Компания-'       || g || '»' end    as short_name,
  'Полное наименование организации №' || g                          as full_name,
  rp.region_code,
  g % 7 = 0                        as is_customer,   -- ~14% заказчиков
  g % 7 <> 0                       as is_supplier,   -- остальные поставщики
  g % 211 = 0                      as is_blacklisted -- ~0.5% в РНП
from generate_series(1, 5000) g
join region_pool rp
  on rp.idx = pg_temp.pick('region:' || g, (select count(*)::int from region_pool));

-- Пулы участников с плотной нумерацией: выбор «случайной компании»
-- дальше делается точечным поиском по номеру. Вариант
-- `order by random() limit 1` внутри lateral обошёлся бы в полную
-- сортировку справочника на каждую из сотен тысяч строк.
create temp table cust_pool (n int generated always as identity primary key, id uuid, region_code text);
insert into cust_pool (id, region_code)
select id, region_code from companies where is_customer order by inn;

create temp table supp_pool (n int generated always as identity primary key, id uuid);
insert into supp_pool (id)
select id from companies where is_supplier and not is_blacklisted order by inn;

-- ---------------------------------------------------------------------
-- 2. tenders — 50 000 закупок за 18 месяцев
-- ---------------------------------------------------------------------
-- Распределение статусов приближено к реальному: большая часть закупок
-- уже завершена, доля выигранных невелика.
insert into tenders (reg_number, version, customer_id, title, law, procedure_type,
                     region_code, status, published_at, submission_deadline, eis_url)
select
  '0' || lpad(g::text, 17, '0')                                     as reg_number,
  1                                                                 as version,
  cust.id                                                           as customer_id,
  'Закупка №' || g || ' — ' || ok.title                             as title,
  case when g % 9 = 0 then '223' else '44' end                      as law,
  (array['auction','auction','auction','contest','quotation'])[1 + (g % 5)],
  cust.region_code,
  st.status,
  pub.published_at,
  pub.published_at + (7 + (g % 21)) * interval '1 day'              as submission_deadline,
  'https://zakupki.gov.ru/epz/order/notice/view?regNumber=0' || lpad(g::text, 17, '0')
from generate_series(1, 50000) g
join cust_pool cust
  on cust.n  = pg_temp.pick('customer:' || g, (select count(*)::int from cust_pool))
join ref_okpd ok
  on ok.idx  = pg_temp.pick('okpd:' || g, (select count(*)::int from ref_okpd))
cross join lateral (
  select (now() - pg_temp.pick('day:' || g, 540) * interval '1 day')::timestamptz as published_at
) pub
cross join lateral (
  -- доли: 4% черновиков, 14% активных, 24% выигранных, 58% проигранных
  select case
    when pg_temp.pick('status:' || g, 100) <=  4 then 'draft'
    when pg_temp.pick('status:' || g, 100) <= 18 then 'active'
    when pg_temp.pick('status:' || g, 100) <= 42 then 'won'
    else                                              'lost'
  end as status
) st;

-- Черновик не имеет дат публикации — иначе нарушится
-- constraint tenders_published_fields (проверяем, что он и правда работает).
update tenders set published_at = null, submission_deadline = null where status = 'draft';

-- ---------------------------------------------------------------------
-- 3. lots — 1–3 лота на закупку (~100 тыс.)
-- ---------------------------------------------------------------------
insert into lots (tender_id, lot_number, title, okpd2, nmck, quantity, unit, delivery_place)
select
  t.id,
  n                                                                 as lot_number,
  'Лот ' || n || ' — ' || ok.title                                  as title,
  ok.okpd2,
  -- цены лог-нормальные: много мелких закупок, единицы крупных
  round((50000 * exp(random() * 4.5))::numeric, 2)                  as nmck,
  round((1 + random() * 500)::numeric, 3)                           as quantity,
  (array['шт','усл.ед','кв.м','ч','мес'])[pg_temp.pick('unit:' || t.id::text || ':' || n, 5)],
  'г. Москва, объект №' || n
from tenders t
cross join lateral generate_series(1, pg_temp.pick('lotcount:' || t.id::text, 3)) n
join ref_okpd ok
  on ok.idx = pg_temp.pick('lotokpd:' || t.id::text || ':' || n, (select count(*)::int from ref_okpd));

-- НМЦК закупки — сумма её лотов (агрегат хранится, чтобы витрина списка
-- закупок не считала сумму по lots на каждой строке).
update tenders t
   set nmck_total = agg.total
  from (select tender_id, sum(nmck) total from lots group by tender_id) agg
 where agg.tender_id = t.id;

-- ---------------------------------------------------------------------
-- 4. bids — ставки участников (~400 тыс.)
-- ---------------------------------------------------------------------
-- Черновики ставок не имеют: закупка ещё не опубликована.
-- Часть лотов остаётся без ставок — несостоявшаяся закупка.
insert into bids (lot_id, supplier_id, amount, status, submitted_at)
select
  l.id,
  s.id,
  -- участники снижают цену от НМЦК на 0–35%
  round((l.nmck * (1 - random() * 0.35))::numeric, 2)               as amount,
  'submitted',
  t.published_at + (random() * 5) * interval '1 day'
from lots l
join tenders t on t.id = l.tender_id
cross join lateral (
  -- 0–9 участников на лот; чем крупнее закупка, тем больше конкуренция
  select generate_series(1, case
    when pg_temp.pick('nobid:' || l.id::text, 100) <= 8 then 0   -- несостоявшиеся
    when l.nmck > 1000000 then 2 + pg_temp.pick('bidcnt:' || l.id::text, 7)
    else                       pg_temp.pick('bidcnt:' || l.id::text, 4)
  end) as k
) cnt
join supp_pool s
  -- Длинный хвост: степень 2.5 смещает выбор к началу пула, поэтому
  -- часть компаний участвует в сотнях торгов, а большинство — в единицах.
  on s.n = pg_temp.pick_skewed('supplier:' || l.id::text || ':' || cnt.k,
                               (select count(*)::int from supp_pool), 2.5)
where t.status <> 'draft'
on conflict (lot_id, supplier_id) do nothing;   -- одна ставка компании на лот

-- ---------------------------------------------------------------------
-- 5. Определение победителей
-- ---------------------------------------------------------------------
-- Побеждает минимальная цена (аукцион на понижение). Победители
-- проставляются только у закупок со статусом 'won'.
with ranked as (
  select b.id,
         row_number() over (partition by b.lot_id order by b.amount, b.id) as rn
    from bids b
    join lots l    on l.id = b.lot_id
    join tenders t on t.id = l.tender_id
   where t.status = 'won'
)
update bids b
   set status = case when r.rn = 1 then 'won' else 'lost' end
  from ranked r
 where r.id = b.id;

-- Остальные опубликованные закупки — проигранные: ставки закрываются как 'lost'
update bids b
   set status = 'lost'
  from lots l
  join tenders t on t.id = l.tender_id
 where l.id = b.lot_id and t.status = 'lost' and b.status = 'submitted';

-- ---------------------------------------------------------------------
-- 6. contractors — контракты по победившим ставкам
-- ---------------------------------------------------------------------
insert into contractors (lot_id, company_id, bid_id, contract_number, contract_amount,
                         signed_at, execution_deadline, completed_at, status, penalty_amount)
select
  b.lot_id,
  b.supplier_id,
  b.id,
  'К-' || to_char(t.published_at, 'YYYYMM') || '-' || lpad((row_number() over (order by b.id))::text, 7, '0'),
  b.amount,
  sign.signed_at,
  (sign.signed_at + (30 + pg_temp.pick('exec:' || b.id::text, 150)) * interval '1 day')::date,
  case when fin.status = 'completed'
       then sign.signed_at + (25 + pg_temp.pick('done:' || b.id::text, 140)) * interval '1 day'
  end,
  fin.status,
  -- штрафы начисляются меньшинству контрактов
  case when pg_temp.pick('penalty:' || b.id::text, 100) <= 12
       then round((b.amount * pg_temp.pick('pen:' || b.id::text, 500) / 10000.0)::numeric, 2)
       else 0 end
from bids b
join lots l    on l.id = b.lot_id
join tenders t on t.id = l.tender_id
cross join lateral (
  select t.submission_deadline + (3 + pg_temp.pick('sign:' || b.id::text, 14)) * interval '1 day' as signed_at
) sign
cross join lateral (
  select case
    when pg_temp.pick('fin:' || b.id::text, 100) <= 55 then 'completed'
    when pg_temp.pick('fin:' || b.id::text, 100) <= 80 then 'in_progress'
    when pg_temp.pick('fin:' || b.id::text, 100) <= 95 then 'signed'
    else                                                    'terminated'
  end as status
) fin
where b.status = 'won';

-- ---------------------------------------------------------------------
-- Статистика для планировщика: без ANALYZE первые же EXPLAIN покажут
-- оценки по умолчанию и планы будут выбраны неверно.
-- ---------------------------------------------------------------------
analyze companies;
analyze tenders;
analyze lots;
analyze bids;
analyze contractors;

-- ---------------------------------------------------------------------
-- Сводка
-- ---------------------------------------------------------------------
drop table ref_regions, region_pool, ref_okpd, cust_pool, supp_pool;

select 'companies'   as table_name, count(*) from companies
union all select 'tenders',     count(*) from tenders
union all select 'lots',        count(*) from lots
union all select 'bids',        count(*) from bids
union all select 'contractors', count(*) from contractors;
