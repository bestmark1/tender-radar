-- =====================================================================
-- Задание 4 — снятие планов выполнения аналитических запросов
-- =====================================================================
-- Воспроизводит замеры, приведённые в SOLUTION.md.
--
-- Запуск:  psql -d tender_platform -f 04_explain.sql
--
-- Важно: первый прогон читает данные с диска и всегда медленнее.
-- Сравнивать варианты нужно на прогретом кеше — запускать дважды
-- и брать второй результат.
-- =====================================================================

set search_path = marketplace, public;
\timing off
\pset pager off

\echo '=== Запрос 1, вариант ДО: граница периода вынесена в CTE ==='
-- Антипаттерн: значение приходит в предикат через InitPlan, планировщик
-- не знает его на этапе планирования и оценивает селективность по
-- умолчанию → seq scan по contractors.
explain (analyze, buffers, costs off, timing off)
with period as (select now() - interval '30 days' as from_ts),
won_contracts as (
  select c.company_id, c.contract_amount, l.nmck
    from contractors c
    join lots l on l.id = c.lot_id
   where c.signed_at >= (select from_ts from period)
     and c.status <> 'terminated'
),
by_company as (
  select company_id, count(*) as contracts_count, sum(contract_amount) as total_amount
    from won_contracts group by company_id
)
select rank() over (order by b.total_amount desc), co.short_name, b.total_amount
  from by_company b join companies co on co.id = b.company_id
 order by b.total_amount desc limit 3;

\echo ''
\echo '=== Запрос 1, вариант ПОСЛЕ: предикат на месте ==='
explain (analyze, buffers, costs off, timing off)
with won_contracts as (
  select c.company_id, c.contract_amount, l.nmck
    from contractors c
    join lots l on l.id = c.lot_id
   where c.signed_at >= now() - interval '30 days'
     and c.status <> 'terminated'
),
by_company as (
  select company_id, count(*) as contracts_count, sum(contract_amount) as total_amount
    from won_contracts group by company_id
)
select rank() over (order by b.total_amount desc), co.short_name, b.total_amount
  from by_company b join companies co on co.id = b.company_id
 order by b.total_amount desc limit 3;

\echo ''
\echo '=== Запрос 2: эффективность участия по категориям ОКПД2 ==='
explain (analyze, buffers, costs off, timing off)
with participation as (
  select b.supplier_id,
         left(l.okpd2, 2) as okpd_class,
         count(*) as bids_total,
         count(*) filter (where b.status = 'won') as bids_won,
         sum(b.amount) filter (where b.status = 'won') as won_amount
    from bids b
    join lots    l on l.id = b.lot_id
    join tenders t on t.id = l.tender_id
   where t.published_at >= now() - interval '6 months'
     and b.status in ('won', 'lost')
   group by 1, 2
  having count(*) >= 5
),
ranked as (
  select p.*,
         rank() over (partition by okpd_class
                      order by bids_won desc, won_amount desc nulls last) as rank_in_class
    from participation p
)
select r.okpd_class, r.rank_in_class, co.short_name
  from ranked r join companies co on co.id = r.supplier_id
 where r.rank_in_class <= 3
 order by 1, 2;
