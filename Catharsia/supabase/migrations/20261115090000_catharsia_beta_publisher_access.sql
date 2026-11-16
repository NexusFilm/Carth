-- Shared, reusable beta access for invited contributors.
-- This grants publishing permission to an account without claiming that the
-- account holder is a verified therapist.

create schema if not exists kathar_private;
revoke all on schema kathar_private from public, anon, authenticated;

create table if not exists kathar_private.beta_publisher_codes (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null,
    code_hash text not null unique,
    is_active boolean not null default true,
    created_by uuid not null references auth.users(id) on delete restrict,
    created_at timestamptz not null default now(),
    revoked_at timestamptz
);

create unique index if not exists beta_publisher_codes_one_active_per_tenant
    on kathar_private.beta_publisher_codes (tenant_id)
    where is_active = true;

create table if not exists kathar_private.beta_publisher_grants (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    code_id uuid not null references kathar_private.beta_publisher_codes(id) on delete restrict,
    granted_at timestamptz not null default now(),
    revoked_at timestamptz,
    unique (tenant_id, user_id)
);

create index if not exists beta_publisher_grants_active_user
    on kathar_private.beta_publisher_grants (tenant_id, user_id)
    where revoked_at is null;

create table if not exists kathar_private.beta_publisher_code_attempts (
    id bigint generated always as identity primary key,
    tenant_id uuid not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    succeeded boolean not null,
    attempted_at timestamptz not null default now()
);

create index if not exists beta_publisher_code_attempts_user_time
    on kathar_private.beta_publisher_code_attempts (tenant_id, user_id, attempted_at desc)
    where succeeded = false;

alter table kathar_private.beta_publisher_codes enable row level security;
alter table kathar_private.beta_publisher_grants enable row level security;
alter table kathar_private.beta_publisher_code_attempts enable row level security;
revoke all on kathar_private.beta_publisher_codes from public, anon, authenticated;
revoke all on kathar_private.beta_publisher_grants from public, anon, authenticated;
revoke all on kathar_private.beta_publisher_code_attempts from public, anon, authenticated;

create or replace function public.kathar_has_beta_publisher_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    select auth.uid() is not null
       and public.kathar_current_user_active()
       and exists (
            select 1
              from auth.users u
             where u.id = auth.uid()
               and u.email_confirmed_at is not null
       )
       and exists (
            select 1
              from kathar_private.beta_publisher_grants g
             where g.tenant_id = public.kathar_tenant_id()
               and g.user_id = auth.uid()
               and g.revoked_at is null
       );
$function$;

revoke all on function public.kathar_has_beta_publisher_access() from public, anon;
grant execute on function public.kathar_has_beta_publisher_access() to authenticated;

create or replace function public.kathar_beta_publisher_code_is_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    current_tenant uuid := public.kathar_tenant_id();
begin
    if auth.uid() is null or not public.kathar_is_admin() then
        raise exception 'Catharsia administrator access required' using errcode = '42501';
    end if;
    return exists (
        select 1
          from kathar_private.beta_publisher_codes c
         where c.tenant_id = current_tenant
           and c.is_active = true
    );
end;
$function$;

revoke all on function public.kathar_beta_publisher_code_is_active() from public, anon;
grant execute on function public.kathar_beta_publisher_code_is_active() to authenticated;

create or replace function public.kathar_rotate_beta_publisher_code()
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
    current_tenant uuid := public.kathar_tenant_id();
    random_hex text;
    normalized_code text;
    display_code text;
begin
    if auth.uid() is null or not public.kathar_is_admin() then
        raise exception 'Catharsia administrator access required' using errcode = '42501';
    end if;
    if not exists (
        select 1 from auth.users u
         where u.id = auth.uid() and u.email_confirmed_at is not null
    ) then
        raise exception 'Confirm your email before creating a publisher code' using errcode = '42501';
    end if;
    if current_tenant is null then
        raise exception 'Catharsia tenant is not configured';
    end if;

    perform public.kathar_ensure_current_user();
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(current_tenant::text, 0));

    update kathar_private.beta_publisher_codes
       set is_active = false,
           revoked_at = now()
     where tenant_id = current_tenant
       and is_active = true;

    random_hex := upper(encode(extensions.gen_random_bytes(12), 'hex'));
    display_code := 'CAT-' || substr(random_hex, 1, 4) || '-' || substr(random_hex, 5, 4)
        || '-' || substr(random_hex, 9, 4) || '-' || substr(random_hex, 13, 4)
        || '-' || substr(random_hex, 17, 4) || '-' || substr(random_hex, 21, 4);
    normalized_code := upper(regexp_replace(display_code, '[^A-Za-z0-9]', '', 'g'));

    insert into kathar_private.beta_publisher_codes (tenant_id, code_hash, created_by)
    values (
        current_tenant,
        encode(extensions.digest(convert_to(normalized_code, 'UTF8'), 'sha256'), 'hex'),
        auth.uid()
    );

    return display_code;
end;
$function$;

revoke all on function public.kathar_rotate_beta_publisher_code() from public, anon;
grant execute on function public.kathar_rotate_beta_publisher_code() to authenticated;

create or replace function public.kathar_redeem_beta_publisher_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
    current_tenant uuid := public.kathar_tenant_id();
    normalized_code text;
    code_hash_value text;
    matched_code_id uuid;
    recent_failures integer;
begin
    if auth.uid() is null then
        raise exception 'Sign in to redeem a publisher code' using errcode = '42501';
    end if;
    if current_tenant is null then
        raise exception 'Catharsia tenant is not configured';
    end if;
    if not exists (
        select 1 from auth.users u
         where u.id = auth.uid() and u.email_confirmed_at is not null
    ) then
        raise exception 'Confirm your email before redeeming a publisher code' using errcode = '42501';
    end if;

    perform public.kathar_ensure_current_user();
    if not public.kathar_current_user_active() then
        raise exception 'This account is not active' using errcode = '42501';
    end if;

    select count(*)::integer into recent_failures
      from kathar_private.beta_publisher_code_attempts a
     where a.tenant_id = current_tenant
       and a.user_id = auth.uid()
       and a.succeeded = false
       and a.attempted_at > now() - interval '15 minutes';

    if recent_failures >= 8 then
        return false;
    end if;

    normalized_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
    if length(normalized_code) = 27 and left(normalized_code, 3) = 'CAT' then
        code_hash_value := encode(extensions.digest(convert_to(normalized_code, 'UTF8'), 'sha256'), 'hex');
        select c.id into matched_code_id
          from kathar_private.beta_publisher_codes c
         where c.tenant_id = current_tenant
           and c.code_hash = code_hash_value
           and c.is_active = true
         limit 1;
    end if;

    if matched_code_id is null then
        insert into kathar_private.beta_publisher_code_attempts (tenant_id, user_id, succeeded)
        values (current_tenant, auth.uid(), false);
        return false;
    end if;

    insert into kathar_private.beta_publisher_grants (tenant_id, user_id, code_id)
    values (current_tenant, auth.uid(), matched_code_id)
    on conflict (tenant_id, user_id) do update
        set code_id = excluded.code_id,
            granted_at = now(),
            revoked_at = null;

    insert into kathar_private.beta_publisher_code_attempts (tenant_id, user_id, succeeded)
    values (current_tenant, auth.uid(), true);

    return true;
end;
$function$;

revoke all on function public.kathar_redeem_beta_publisher_code(text) from public, anon;
grant execute on function public.kathar_redeem_beta_publisher_code(text) to authenticated;

-- A beta publisher may publish only without asserting a clinician profile.
create or replace function public.kathar_can_publish_as_professional(p_professional_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    select coalesce(
        case
            when p_professional_id is null then
                public.kathar_is_admin() or public.kathar_has_beta_publisher_access()
            when public.kathar_is_admin() then exists (
                select 1
                  from public.kathar_professionals p
                 where p.id = p_professional_id
                   and p.tenant_id = public.kathar_tenant_id()
                   and p.user_id = auth.uid()
                   and p.is_platform = true
            )
            else exists (
                select 1
                  from public.kathar_professionals p
                 where p.id = p_professional_id
                   and p.tenant_id = public.kathar_tenant_id()
                   and p.user_id = auth.uid()
                   and p.is_platform = false
                   and p.verified = true
                   and p.verification_status = 'verified'
                   and p.verification_tier in ('verified_clinician', 'verified_professional')
            )
        end,
        false
    );
$function$;

revoke all on function public.kathar_can_publish_as_professional(uuid) from public, anon;
grant execute on function public.kathar_can_publish_as_professional(uuid) to authenticated;

create or replace function public.kathar_can_upload_media()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    select coalesce(
        public.kathar_is_admin()
        or public.kathar_has_beta_publisher_access()
        or exists (
            select 1
              from public.kathar_professionals p
             where p.tenant_id = public.kathar_tenant_id()
               and p.user_id = auth.uid()
               and p.verified = true
               and p.verification_status = 'verified'
               and p.verification_tier in ('verified_clinician', 'verified_professional')
        ),
        false
    );
$function$;

revoke all on function public.kathar_can_upload_media() from public, anon;
grant execute on function public.kathar_can_upload_media() to authenticated;

drop policy if exists kathar_communities_create on public.kathar_communities;
create policy kathar_communities_create
on public.kathar_communities
for insert to authenticated
with check (
    tenant_id = public.kathar_tenant_id()
    and is_mock = false
    and owner_user_id = (select auth.uid())
    and (
        public.kathar_is_admin()
        or public.kathar_can_publish_as_professional(professional_id)
    )
);

drop policy if exists kathar_community_posts_create on public.kathar_community_posts;
create policy kathar_community_posts_create
on public.kathar_community_posts
for insert to authenticated
with check (
    tenant_id = public.kathar_tenant_id()
    and author_user_id = (select auth.uid())
    and exists (
        select 1
          from public.kathar_communities c
         where c.id = kathar_community_posts.community_id
           and c.tenant_id = public.kathar_tenant_id()
           and c.is_mock = false
           and (
                c.owner_user_id = (select auth.uid())
                or public.kathar_is_admin()
                or (
                    kind in ('comment', 'reply')
                    and exists (
                        select 1
                          from public.kathar_community_members m
                         where m.community_id = c.id
                           and m.tenant_id = c.tenant_id
                           and m.user_id = (select auth.uid())
                           and m.status = 'active'
                    )
                )
           )
    )
    and (
        kind in ('comment', 'reply')
        or (
            kind = 'group_post'
            and (
                public.kathar_is_admin()
                or exists (
                    select 1 from public.kathar_communities c
                     where c.id = kathar_community_posts.community_id
                       and c.tenant_id = public.kathar_tenant_id()
                       and c.owner_user_id = (select auth.uid())
                )
            )
        )
    )
    and (
        kind in ('comment', 'reply')
        or public.kathar_is_admin()
        or exists (
            select 1 from public.kathar_communities c
             where c.id = kathar_community_posts.community_id
               and c.tenant_id = public.kathar_tenant_id()
               and c.owner_user_id = (select auth.uid())
               and public.kathar_can_publish_as_professional(c.professional_id)
        )
    )
);
