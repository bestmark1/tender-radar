-- Миграция 0002: LLM-скоринг релевантности.
-- Балл 0–100, который выставляет LLM (DeepSeek) каждому совпадению.
alter table public.matches add column if not exists score int;

-- индекс для сортировки по релевантности в дашборде
create index if not exists matches_score_idx on public.matches (score desc nulls last);
