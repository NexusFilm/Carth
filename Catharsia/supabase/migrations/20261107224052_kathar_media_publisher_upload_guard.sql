-- Only administrators and verified therapists may create or replace Catharsia media objects.
create or replace function public.kathar_can_upload_media()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select coalesce(
    public.kathar_is_admin()
    or exists (
      select 1
        from public.kathar_professionals as professional
       where professional.tenant_id = public.kathar_tenant_id()
         and professional.user_id = auth.uid()
         and professional.verified is true
         and professional.verification_status = 'verified'
         and professional.verification_tier in ('verified_clinician', 'verified_professional')
    ),
    false
  );
$function$;

revoke all on function public.kathar_can_upload_media() from public, anon;
grant execute on function public.kathar_can_upload_media() to authenticated;

drop policy if exists kathar_media_upload_own on storage.objects;
create policy kathar_media_upload_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'kathar-media'
    and (storage.foldername(name))[1] = public.kathar_tenant_id()::text
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.kathar_can_upload_media()
  );

drop policy if exists kathar_media_update_own on storage.objects;
create policy kathar_media_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'kathar-media'
    and (storage.foldername(name))[1] = public.kathar_tenant_id()::text
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.kathar_can_upload_media()
  )
  with check (
    bucket_id = 'kathar-media'
    and (storage.foldername(name))[1] = public.kathar_tenant_id()::text
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.kathar_can_upload_media()
  );
