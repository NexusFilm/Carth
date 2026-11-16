create or replace function public.kathar_cleanup_deleted_post_saves()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.kathar_saved_items
    where tenant_id = old.tenant_id
      and kind = 'post'
      and target_id = old.id;

    return old;
end;
$$;

revoke all on function public.kathar_cleanup_deleted_post_saves() from public, anon, authenticated;

drop trigger if exists kathar_posts_cleanup_saved_items on public.kathar_posts;
create trigger kathar_posts_cleanup_saved_items
after delete on public.kathar_posts
for each row execute function public.kathar_cleanup_deleted_post_saves();
