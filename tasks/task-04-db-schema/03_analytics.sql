-- =====================================================================
-- Задание 4 — аналитические запросы
-- =====================================================================
-- Запуск:  psql -v ON_ERROR_STOP=1 -f 03_analytics.sql
-- Требует применённых 01_schema.sql и 02_seed.sql.
-- =====================================================================

\set ON_ERROR_STOP on
set search_path = marketplace, public;

-- =====================================================================
-- Запрос 1. Топ-3 компании по сумме выигранных тендеров за последний месяц
-- =====================================================================
-- Помимо самой суммы возвращаются: число контрактов, средний процент
-- снижения от НМЦК (показывает, ценой какой маржи взяты победы) и доля
-- компании в общем объёме законтрактованного за период.
--
-- Тонкости:
--   * Расторгнутые контракты исключены: подписанный и затем расторгнутый
--     контракт — не выигрыш, и включать его в рейтинг нельзя.
--   * Оконная функция sum() over () считается ДО применения LIMIT,
--     поэтому доля рынка берётся от всего периода, а не от трёх строк.
--   * rank(), а не row_number(): при равных суммах обе компании должны
--     получить одно место, иначе рейтинг зависит от порядка чтения строк.
--   * nullif(l.nmck, 0) страхует деление на ноль, хотя CHECK на lots и
--     не должен пропускать нулевую НМЦК — в аналитике дешевле
--     перестраховаться, чем ловить деление на ноль на проде.
-- =====================================================================
with won_contracts as (
  -- Границу периода намеренно НЕ выносим в отдельный CTE.
  -- Через `where signed_at >= (select from_ts from period)` предикат
  -- становится для планировщика InitPlan'ом с неизвестным значением:
  -- селективность оценивается по умолчанию, индекс по signed_at не
  -- используется и contractors читается последовательно. С предикатом
  -- на месте планировщик знает границу и берёт bitmap index scan.
  -- Замер на 20 745 контрактах: 16.5 мс против 6.1 мс (см. SOLUTION.md).
  --
  -- Скользящие 30 дней. Для календарного месяца:
  --   signed_at >= date_trunc('month', now()) - interval '1 month'
  --   and signed_at < date_trunc('month', now())
  select c.company_id,
         c.contract_amount,
         l.nmck
    from contractors c
    join lots l on l.id = c.lot_id
   where c.signed_at >= now() - interval '30 days'
     and c.status <> 'terminated'
),
by_company as (
  select company_id,
         count(*)                                                  as contracts_count,
         sum(contract_amount)                                      as total_amount,
         round(avg(1 - contract_amount / nullif(nmck, 0)) * 100, 2) as avg_discount_pct
    from won_contracts
   group by company_id
)
select rank() over (order by b.total_amount desc)                       as rank,
       co.short_name,
       co.inn,
       co.region_code,
       b.contracts_count,
       b.total_amount,
       round(100 * b.total_amount / sum(b.total_amount) over (), 2)     as market_share_pct,
       b.avg_discount_pct
  from by_company b
  join companies co on co.id = b.company_id
 order by b.total_amount desc
 limit 3;

-- =====================================================================
-- Запрос 2. Эффективность участия поставщиков в разрезе категорий ОКПД2
-- =====================================================================
-- По каждому классу ОКПД2 — тройка сильнейших поставщиков за полгода:
-- сколько ставок подано, сколько выиграно, win-rate, средняя глубина
-- снижения цены и позиция относительно конкурентов в том же классе.
--
-- Это тот срез, ради которого площадка и нужна поставщику: «в какой
-- нише я реально конкурентоспособен, а где просто трачу время на заявки».
--
-- Тонкости:
--   * count(*) filter (where ...) вместо sum(case when ... then 1 end) —
--     читается прямо и не считает NULL как ноль по недосмотру.
--   * HAVING отсекает компании с единичным участием: win-rate 100% при
--     одной поданной заявке — статистический шум, который иначе займёт
--     весь топ.
--   * percent_rank() даёт позицию в распределении, устойчивую к разному
--     числу участников в классах: сравнивать «3-е место из 5» и
--     «3-е из 400» по абсолютному рангу бессмысленно.
--   * Ставки со статусом 'submitted' (торги ещё идут) в знаменатель
--     win-rate не попадают — исход по ним неизвестен.
-- =====================================================================
with participation as (
  select b.supplier_id,
         left(l.okpd2, 2)                                            as okpd_class,
         count(*)                                                    as bids_total,
         count(*) filter (where b.status = 'won')                    as bids_won,
         sum(b.amount) filter (where b.status = 'won')               as won_amount,
         avg((l.nmck - b.amount) / nullif(l.nmck, 0))
           filter (where b.status = 'won')                           as avg_discount
    from bids b
    join lots    l on l.id = b.lot_id
    join tenders t on t.id = l.tender_id
   where t.published_at >= now() - interval '6 months'
     and b.status in ('won', 'lost')          -- только завершённые торги
   group by b.supplier_id, left(l.okpd2, 2)
  having count(*) >= 5                        -- отсекаем случайных участников
),
ranked as (
  select p.*,
         round(100.0 * bids_won / bids_total, 2)                     as win_rate_pct,
         rank() over (partition by okpd_class
                      order by bids_won desc, won_amount desc nulls last) as rank_in_class,
         round((100 * percent_rank() over (
                      partition by okpd_class
                      order by bids_won::numeric / bids_total))::numeric, 1) as win_rate_percentile,
         count(*) over (partition by okpd_class)                     as competitors_in_class
    from participation p
)
select r.okpd_class,
       r.rank_in_class,
       co.short_name,
       co.region_code,
       r.bids_total,
       r.bids_won,
       r.win_rate_pct,
       r.win_rate_percentile,
       r.competitors_in_class,
       coalesce(r.won_amount, 0)                                     as won_amount,
       round((r.avg_discount * 100)::numeric, 2)                     as avg_discount_pct
  from ranked r
  join companies co on co.id = r.supplier_id
 where r.rank_in_class <= 3
 order by r.okpd_class, r.rank_in_class;

-- =====================================================================
-- Запрос 3 (дополнительный). Помесячная динамика законтрактованного объёма
-- =====================================================================
-- Показывает, как площадка растёт: объём и число контрактов по месяцам,
-- прирост к предыдущему месяцу и скользящее среднее за 3 месяца.
-- LAG/AVG с рамкой окна нужны здесь именно потому, что сравнивать месяц
-- с месяцем самосоединением таблицы — дороже и хуже читается.
-- =====================================================================
with monthly as (
  select date_trunc('month', signed_at)::date as month,
         count(*)                             as contracts_count,
         sum(contract_amount)                 as total_amount,
         count(distinct company_id)           as active_suppliers
    from contractors
   where signed_at >= now() - interval '12 months'
   group by 1
)
select month,
       contracts_count,
       total_amount,
       active_suppliers,
       lag(total_amount) over (order by month)                       as prev_month_amount,
       round(100 * (total_amount - lag(total_amount) over (order by month))
             / nullif(lag(total_amount) over (order by month), 0), 1) as mom_growth_pct,
       round(avg(total_amount) over (order by month
             rows between 2 preceding and current row), 2)           as rolling_3m_avg
  from monthly
 order by month;
