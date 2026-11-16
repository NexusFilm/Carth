-- Review is restricted to Catharsia administrators. License numbers remain on
-- the RLS-protected application and are deliberately not copied to public
-- therapist profiles when posting access is granted.
create or replace function public.kathar_review_verification_application(
  p_application_id uuid,
  p_decision text,
  p_verification_source text default null,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_tenant uuid := public.kathar_tenant_id();
  application public.kathar_verification_applications%rowtype;
  professional_id uuid;
begin
  if auth.uid() is null or not public.kathar_is_admin() then
    raise exception 'Catharsia administrator access required' using errcode = '42501';
  end if;

  if p_decision not in ('verified', 'rejected') then
    raise exception 'Unsupported therapist application decision';
  end if;

  select * into application
    from public.kathar_verification_applications
   where tenant_id = current_tenant
     and id = p_application_id
   for update;

  if not found then
    raise exception 'Therapist application not found';
  end if;
  if application.status in ('verified', 'rejected') then
    raise exception 'Therapist application has already been reviewed';
  end if;

  if p_decision = 'verified' then
    if application.applicant_user_id is null then
      raise exception 'Application is not linked to a signed-in user';
    end if;
    if nullif(btrim(application.credentials), '') is null then
      raise exception 'A professional credential is required';
    end if;
    if coalesce(p_verification_source, '') !~* '^https://[^[:space:]]+' then
      raise exception 'An HTTPS official licensing registry URL is required';
    end if;

    select id into professional_id
      from public.kathar_professionals
     where tenant_id = current_tenant
       and user_id = application.applicant_user_id
     order by created_at asc
     limit 1
     for update;

    if professional_id is null then
      insert into public.kathar_professionals (
        tenant_id, user_id, full_name, credentials, license_number,
        license_states, specialties, verified, verified_on,
        verification_tier, verification_status, is_mock, is_platform
      ) values (
        current_tenant, application.applicant_user_id, application.full_name,
        btrim(application.credentials), null,
        array[upper(btrim(application.license_state))], application.specialties,
        true, current_date, 'verified_clinician', 'verified', false, false
      );
    else
      update public.kathar_professionals
         set full_name = application.full_name,
             credentials = btrim(application.credentials),
             license_number = null,
             license_states = array[upper(btrim(application.license_state))],
             specialties = application.specialties,
             verified = true,
             verified_on = current_date,
             verification_tier = 'verified_clinician',
             verification_status = 'verified',
             is_mock = false,
             is_platform = false
       where id = professional_id
         and tenant_id = current_tenant;
    end if;

    update public.kathar_verification_applications
       set status = 'verified',
           verification_status = 'verified',
           verification_method = 'manual_official_registry',
           verification_source = left(btrim(p_verification_source), 2000),
           verification_checked_at = now(),
           verification_notes = nullif(left(btrim(coalesce(p_notes, '')), 1000), '')
     where tenant_id = current_tenant
       and id = p_application_id;
  else
    update public.kathar_professionals
       set verified = false,
           verification_tier = 'rejected',
           verification_status = 'rejected'
     where tenant_id = current_tenant
       and user_id = application.applicant_user_id;

    update public.kathar_verification_applications
       set status = 'rejected',
           verification_status = 'rejected',
           verification_method = 'manual_review',
           verification_checked_at = now(),
           verification_notes = nullif(left(btrim(coalesce(p_notes, '')), 1000), '')
     where tenant_id = current_tenant
       and id = p_application_id;
  end if;
end;
$function$;

revoke all on function public.kathar_review_verification_application(uuid, text, text, text) from public, anon;
grant execute on function public.kathar_review_verification_application(uuid, text, text, text) to authenticated;
