-- Catharsia-only safety records. Every row is bound to the existing Kathar
-- tenant and scoped by RLS; no shared Viewfinder or Rema tables are changed.
create unique index if not exists kathar_profiles_tenant_id_id_key
  on public.kathar_profiles (tenant_id, id);

create table if not exists public.kathar_user_blocks (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  blocker_id uuid not null,
  blocked_user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, blocker_id, blocked_user_id),
  constraint kathar_user_blocks_not_self check (blocker_id <> blocked_user_id),
  constraint kathar_user_blocks_blocker_profile_fkey
    foreign key (tenant_id, blocker_id)
    references public.kathar_profiles (tenant_id, id) on delete cascade,
  constraint kathar_user_blocks_blocked_profile_fkey
    foreign key (tenant_id, blocked_user_id)
    references public.kathar_profiles (tenant_id, id) on delete cascade
);

alter table public.kathar_user_blocks enable row level security;

create policy kathar_user_blocks_read_self
  on public.kathar_user_blocks for select to authenticated
  using (tenant_id = public.kathar_tenant_id() and blocker_id = auth.uid());

create policy kathar_user_blocks_create_self
  on public.kathar_user_blocks for insert to authenticated
  with check (
    tenant_id = public.kathar_tenant_id()
    and blocker_id = auth.uid()
    and blocked_user_id <> auth.uid()
  );

create policy kathar_user_blocks_delete_self
  on public.kathar_user_blocks for delete to authenticated
  using (tenant_id = public.kathar_tenant_id() and blocker_id = auth.uid());

grant select, insert, delete on public.kathar_user_blocks to authenticated;

create table if not exists public.kathar_reports (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid,
  post_id uuid,
  comment_id uuid,
  content_excerpt text not null,
  author_name text not null,
  reason text not null,
  status text not null default 'pending'
    check (status in ('pending', 'dismissed', 'removed')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint kathar_reports_one_target check ((post_id is null) <> (comment_id is null))
);

create index if not exists kathar_reports_tenant_status_created_idx
  on public.kathar_reports (tenant_id, status, created_at desc);

alter table public.kathar_reports enable row level security;

create policy kathar_reports_admin_read
  on public.kathar_reports for select to authenticated
  using (tenant_id = public.kathar_tenant_id() and public.kathar_is_admin());

create policy kathar_reports_admin_update
  on public.kathar_reports for update to authenticated
  using (tenant_id = public.kathar_tenant_id() and public.kathar_is_admin())
  with check (tenant_id = public.kathar_tenant_id() and public.kathar_is_admin());

grant select, update on public.kathar_reports to authenticated;

create or replace function public.kathar_create_content_report(
  p_post_id uuid default null,
  p_comment_id uuid default null,
  p_reason text default 'inappropriate'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  target_tenant uuid := public.kathar_tenant_id();
  current_user_id uuid := auth.uid();
  target_author_id uuid;
  target_author_name text;
  target_content text;
  report_id uuid;
begin
  if current_user_id is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  if (p_post_id is null) = (p_comment_id is null) then
    raise exception 'Report one post or one comment';
  end if;

  if p_post_id is not null then
    select p.author_user_id,
           coalesce(nullif(btrim(p.author_name), ''), nullif(btrim(p.author_credentials), ''), 'Therapist'),
           coalesce(nullif(btrim(p.title), ''), nullif(btrim(p.summary), ''), nullif(btrim(p.body), ''), 'Post')
      into target_author_id, target_author_name, target_content
      from public.kathar_posts p
     where p.tenant_id = target_tenant
       and p.id = p_post_id
       and p.is_mock = false
       and p.is_test = false;
  else
    select c.author_id,
           coalesce(nullif(btrim(c.author_name), ''), 'Member'),
           c.body
      into target_author_id, target_author_name, target_content
      from public.kathar_comments c
     where c.tenant_id = target_tenant
       and c.id = p_comment_id;
  end if;

  if not found then
    raise exception 'Content is unavailable';
  end if;

  insert into public.kathar_reports (
    tenant_id, reporter_id, reported_user_id, post_id, comment_id,
    content_excerpt, author_name, reason
  ) values (
    target_tenant, current_user_id, target_author_id, p_post_id, p_comment_id,
    left(target_content, 1500), target_author_name,
    left(coalesce(nullif(btrim(p_reason), ''), 'inappropriate'), 80)
  ) returning id into report_id;

  return report_id;
end;
$function$;

revoke all on function public.kathar_create_content_report(uuid, uuid, text) from public, anon;
grant execute on function public.kathar_create_content_report(uuid, uuid, text) to authenticated;
