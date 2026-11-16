-- Serialize the one-time reconciliation with engagement writes.
lock table public.kathar_posts, public.kathar_post_likes,
           public.kathar_saved_items, public.kathar_comments
in share row exclusive mode;

create or replace function public.kathar_sync_post_like_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.kathar_posts
       set likes = greatest(0, coalesce(likes, 0) + 1)
     where tenant_id = new.tenant_id and id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.kathar_posts
       set likes = greatest(0, coalesce(likes, 0) - 1)
     where tenant_id = old.tenant_id and id = old.post_id;
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.kathar_sync_post_save_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.kind = 'post' then
      update public.kathar_posts
         set saves = greatest(0, coalesce(saves, 0) + 1)
       where tenant_id = new.tenant_id and id = new.target_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.kind = 'post' then
      update public.kathar_posts
         set saves = greatest(0, coalesce(saves, 0) - 1)
       where tenant_id = old.tenant_id and id = old.target_id;
    end if;
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.kathar_sync_post_comment_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.kathar_posts
       set comment_count = greatest(0, coalesce(comment_count, 0) + 1)
     where tenant_id = new.tenant_id and id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.kathar_posts
       set comment_count = greatest(0, coalesce(comment_count, 0) - 1)
     where tenant_id = old.tenant_id and id = old.post_id;
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.kathar_sync_post_like_count() from public, anon, authenticated;
revoke all on function public.kathar_sync_post_save_count() from public, anon, authenticated;
revoke all on function public.kathar_sync_post_comment_count() from public, anon, authenticated;

-- Reconcile all existing posts in the Catharsia tenant after the atomic
-- trigger logic is in place. The tenant comes from app configuration.
update public.kathar_posts as post
   set likes = (
         select count(*)::integer
           from public.kathar_post_likes as liked
          where liked.tenant_id = post.tenant_id and liked.post_id = post.id
       ),
       saves = (
         select count(*)::integer
           from public.kathar_saved_items as saved
          where saved.tenant_id = post.tenant_id
            and saved.kind = 'post'
            and saved.target_id = post.id
       ),
       comment_count = (
         select count(*)::integer
           from public.kathar_comments as comment
          where comment.tenant_id = post.tenant_id and comment.post_id = post.id
       )
 where post.tenant_id = (
   select config.value::uuid
     from public.app_config as config
    where config.key = 'kathar.tenant_id'
 );
