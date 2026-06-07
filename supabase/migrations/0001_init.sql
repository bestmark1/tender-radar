-- =====================================================================
-- Тендер-радар — миграция 0001: схема MVP + RLS
-- Бизнес-данные (ADR-1). N8N пишет через service_role (минует RLS).
-- =====================================================================

-- ---------- Расширения ----------
create extension if not exists "pgcrypto"; -- gen_random_uuid

-- ---------- users (профиль; завязан на auth.users) ----------
create table public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  -- настройки каналов уведомлений: {email:bool, vk:{...}, max:{...}, telegram:{chat_id}}
  channels    jsonb not null default '{"email": true}'::jsonb,
  created_at  timestamptz not null default now()
);

-- ---------- radars (правила мониторинга) — US-1 ----------
create table public.radars (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.users (id) on delete cascade,
  name             text not null,
  regions          text[] not null,            -- ['77','50']
  okpd_prefixes    text[] not null,            -- ['81.2']
  keywords_include text[] not null default '{}',
  keywords_exclude text[] not null default '{}',
  price_min        numeric,
  price_max        numeric,
  law              text not null default '44',  -- '44' | '223' | 'both'
  reminder_days    int  not null default 2,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  -- US-1.4: нужен хотя бы один регион и хотя бы один критерий фильтрации
  constraint radars_has_region check (array_length(regions, 1) >= 1),
  constraint radars_has_filter check (
    array_length(okpd_prefixes, 1) >= 1
    or array_length(keywords_include, 1) >= 1
    or price_min is not null
    or price_max is not null
  ),
  constraint radars_law_valid check (law in ('44','223','both'))
);
create index radars_user_idx on public.radars (user_id);
create index radars_active_idx on public.radars (is_active) where is_active;

-- ---------- tenders (нормализованные закупки из ЕИС) — US-2 ----------
-- Глобальные данные: без user_id. Запись только service_role (см. RLS, A3).
create table public.tenders (
  id                  uuid primary key default gen_random_uuid(),
  reg_number          text not null,
  version             int  not null default 1,
  title               text,
  customer            text,
  region              text,
  okpd                text,
  price               numeric,                  -- НМЦК
  published_at        timestamptz,
  submission_deadline timestamptz,
  eis_url             text,
  law                 text,
  raw                 jsonb,
  created_at          timestamptz not null default now(),
  unique (reg_number, version)
);
create index tenders_deadline_idx on public.tenders (submission_deadline);
create index tenders_okpd_idx on public.tenders (okpd);
create index tenders_region_idx on public.tenders (region);

-- ---------- matches (совпадение закупка↔радар) — US-3 ----------
create table public.matches (
  id         uuid primary key default gen_random_uuid(),
  tender_id  uuid not null references public.tenders (id) on delete cascade,
  radar_id   uuid not null references public.radars (id) on delete cascade,
  user_id    uuid not null references public.users (id) on delete cascade,
  status     text not null default 'new',       -- 'new'|'interested'|'hidden'
  notified   boolean not null default false,
  reminded   boolean not null default false,
  created_at timestamptz not null default now(),
  unique (tender_id, radar_id),
  constraint matches_status_valid check (status in ('new','interested','hidden'))
);
create index matches_user_idx on public.matches (user_id);
create index matches_status_idx on public.matches (status);

-- ---------- notifications (лог отправок) — US-4 ----------
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  channel    text not null,                     -- 'email'|'vk'|'max'|'telegram'
  kind       text not null,                     -- 'digest'|'deadline'
  payload    jsonb,
  status     text not null,                     -- 'sent'|'failed'
  error      text,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id);

-- =====================================================================
-- A2: автосоздание строки public.users при регистрации в auth.users
-- =====================================================================
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- RLS
-- =====================================================================
alter table public.users         enable row level security;
alter table public.radars        enable row level security;
alter table public.tenders       enable row level security;
alter table public.matches       enable row level security;
alter table public.notifications enable row level security;

-- users: видит/меняет только себя
create policy users_select_own on public.users
  for select using (id = auth.uid());
create policy users_update_own on public.users
  for update using (id = auth.uid()) with check (id = auth.uid());

-- radars: полный CRUD только над своими
create policy radars_all_own on public.radars
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- tenders (A3): чтение всем аутентифицированным; запись — нет политик => только service_role
create policy tenders_select_auth on public.tenders
  for select to authenticated using (true);

-- matches: чтение своих; обновление статуса своих (interested/hidden)
create policy matches_select_own on public.matches
  for select using (user_id = auth.uid());
create policy matches_update_own on public.matches
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- notifications: чтение своих
create policy notifications_select_own on public.notifications
  for select using (user_id = auth.uid());
