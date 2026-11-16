-- Catharsia member profile editing and dedicated public avatars.
-- Keep role, tenant, email, deactivation, and identity fields outside client write access.

alter table public.kathar_profiles
  add column if not exists username text;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.kathar_profiles'::regclass
      and conname = 'kathar_profiles_username_format_check'
  ) then
    alter table public.kathar_profiles
      add constraint kathar_profiles_username_format_check
      check (username is null or username ~ '^[a-z0-9_]{3,24}$');
  end if;
end;
$migration$;

create unique index if not exists kathar_profiles_tenant_username_key
  on public.kathar_profiles (tenant_id, username)
  where username is not null;

-- The profile row itself is created by kathar_ensure_current_user() as a
-- SECURITY DEFINER function. Authenticated clients only need read access and
-- narrowly scoped edits to public profile fields. RLS still limits edits to
-- the signed-in user's row (or to an authorized Catharsia administrator).
revoke all privileges on table public.kathar_profiles from authenticated;

-- Remove any existing per-column grants too; table-level REVOKE does not clear
-- privileges that may have been granted directly on individual columns.
do $migration$
declare
  profile_column record;
begin
  for profile_column in
    select attname
    from pg_attribute
    where attrelid = 'public.kathar_profiles'::regclass
      and attnum > 0
      and not attisdropped
  loop
    execute format('revoke select (%I) on table public.kathar_profiles from authenticated', profile_column.attname);
    execute format('revoke insert (%I) on table public.kathar_profiles from authenticated', profile_column.attname);
    execute format('revoke update (%I) on table public.kathar_profiles from authenticated', profile_column.attname);
    execute format('revoke references (%I) on table public.kathar_profiles from authenticated', profile_column.attname);
  end loop;
end;
$migration$;

grant select on table public.kathar_profiles to authenticated;
grant update (full_name, display_name, photo_url, bio, username, updated_at)
  on table public.kathar_profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'kathar-profile-avatars',
  'kathar-profile-avatars',
  true,
  4194304,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do nothing;

do $migration$
begin
  if not exists (
    select 1 from storage.buckets
    where id = 'kathar-profile-avatars'
      and public
      and file_size_limit = 4194304
      and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']::text[]
  ) then
    raise exception 'Catharsia profile avatar bucket is missing or has unexpected limits';
  end if;
end;
$migration$;

drop policy if exists kathar_profile_avatars_public_read on storage.objects;
create policy kathar_profile_avatars_public_read
  on storage.objects for select to public
  using (bucket_id = 'kathar-profile-avatars');

drop policy if exists kathar_profile_avatars_upload_own on storage.objects;
create policy kathar_profile_avatars_upload_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'kathar-profile-avatars'
    and (storage.foldername(name))[1] = public.kathar_tenant_id()::text
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.kathar_is_member()
  );

drop policy if exists kathar_profile_avatars_delete_own on storage.objects;
create policy kathar_profile_avatars_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'kathar-profile-avatars'
    and (storage.foldername(name))[1] = public.kathar_tenant_id()::text
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.kathar_is_member()
  );
