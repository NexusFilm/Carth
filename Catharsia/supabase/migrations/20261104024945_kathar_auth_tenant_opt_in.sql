-- Auth users are shared by multiple apps in this Supabase project. Only users
-- explicitly signing up from Catharsia are auto-added to the Kathar tenant.
create or replace function public.kathar_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  target_tenant uuid := public.kathar_tenant_id();
begin
  if target_tenant is null
     or coalesce(new.raw_user_meta_data ->> 'kathar_tenant_id', '') <> target_tenant::text then
    return new;
  end if;

  insert into public.tenant_members (tenant_id, user_id, role)
  values (target_tenant, new.id, 'member')
  on conflict (tenant_id, user_id) do nothing;

  insert into public.kathar_profiles (tenant_id, id, email, full_name, display_name)
  values (
    target_tenant,
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$function$;
