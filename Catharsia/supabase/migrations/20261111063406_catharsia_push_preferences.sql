-- Keep Catharsia notification choices separate from other Nexus apps.
create table if not exists public.catharsia_push_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  manual_push_enabled boolean not null default true,
  auto_push_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.catharsia_push_preferences enable row level security;

grant select, insert, update on public.catharsia_push_preferences to authenticated;

drop policy if exists "Users can view own Catharsia push preferences" on public.catharsia_push_preferences;
create policy "Users can view own Catharsia push preferences"
  on public.catharsia_push_preferences
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own Catharsia push preferences" on public.catharsia_push_preferences;
create policy "Users can insert own Catharsia push preferences"
  on public.catharsia_push_preferences
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own Catharsia push preferences" on public.catharsia_push_preferences;
create policy "Users can update own Catharsia push preferences"
  on public.catharsia_push_preferences
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
