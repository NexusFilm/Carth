-- Keep share totals as a real aggregate on the post record, like likes,
-- saves, and comments. The increment runs atomically in the database.
alter table public.kathar_posts
  add column if not exists share_count integer not null default 0
  check (share_count >= 0);

-- Keep the SECURITY DEFINER implementation out of PostgREST's exposed
-- schemas. The public RPC below is SECURITY INVOKER and can only call this
-- narrowly scoped counter operation.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create or replace function private.kathar_increment_post_share_count(p_post_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  updated_share_count integer;
begin
  if p_post_id is null then
    raise exception 'Post is not available.' using errcode = 'P0002';
  end if;

  update public.kathar_posts as post
     set share_count = post.share_count + 1
   where post.id = p_post_id
     and post.tenant_id = public.kathar_tenant_id()
     and not coalesce(post.is_mock, false)
     and not coalesce(post.is_test, false)
     and public.kathar_can_view_post(post.id)
  returning post.share_count into updated_share_count;

  if not found then
    raise exception 'Post is not available.' using errcode = 'P0002';
  end if;

  return updated_share_count;
end;
$function$;

revoke all on function private.kathar_increment_post_share_count(uuid) from public;
grant execute on function private.kathar_increment_post_share_count(uuid) to anon, authenticated;

create or replace function public.kathar_record_post_share(p_post_id uuid)
returns integer
language sql
security invoker
set search_path = ''
as $function$
  select private.kathar_increment_post_share_count(p_post_id);
$function$;

revoke all on function public.kathar_record_post_share(uuid) from public;
grant execute on function public.kathar_record_post_share(uuid) to anon, authenticated;
