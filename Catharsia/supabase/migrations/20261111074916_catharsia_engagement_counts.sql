-- Keep public engagement totals on each Catharsia post without exposing
-- individual like or save rows to other users.
alter table public.kathar_posts
  add column if not exists comment_count integer not null default 0;

create or replace function public.kathar_sync_post_save_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_tenant_id uuid := coalesce(new.tenant_id, old.tenant_id);
  target_post_id uuid := coalesce(new.target_id, old.target_id);
  target_kind text := coalesce(new.kind, old.kind);
begin
  if target_kind = 'post' then
    update public.kathar_posts as post
       set saves = (
         select count(*)::integer
           from public.kathar_saved_items as saved
          where saved.tenant_id = target_tenant_id
            and saved.kind = 'post'
            and saved.target_id = target_post_id
       )
     where post.tenant_id = target_tenant_id
       and post.id = target_post_id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists kathar_saved_items_post_count_insert on public.kathar_saved_items;
create trigger kathar_saved_items_post_count_insert
after insert on public.kathar_saved_items
for each row execute function public.kathar_sync_post_save_count();

drop trigger if exists kathar_saved_items_post_count_delete on public.kathar_saved_items;
create trigger kathar_saved_items_post_count_delete
after delete on public.kathar_saved_items
for each row execute function public.kathar_sync_post_save_count();

create or replace function public.kathar_sync_post_comment_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_tenant_id uuid := coalesce(new.tenant_id, old.tenant_id);
  target_post_id uuid := coalesce(new.post_id, old.post_id);
begin
  update public.kathar_posts as post
     set comment_count = (
       select count(*)::integer
         from public.kathar_comments as comment
        where comment.tenant_id = target_tenant_id
          and comment.post_id = target_post_id
     )
   where post.tenant_id = target_tenant_id
     and post.id = target_post_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists kathar_comments_post_count_insert on public.kathar_comments;
create trigger kathar_comments_post_count_insert
after insert on public.kathar_comments
for each row execute function public.kathar_sync_post_comment_count();

drop trigger if exists kathar_comments_post_count_delete on public.kathar_comments;
create trigger kathar_comments_post_count_delete
after delete on public.kathar_comments
for each row execute function public.kathar_sync_post_comment_count();

-- Reconcile the existing aggregate columns once so older posts start with
-- accurate counts as soon as the client reads them.
update public.kathar_posts as post
   set likes = (
         select count(*)::integer
           from public.kathar_post_likes as liked
          where liked.tenant_id = post.tenant_id
            and liked.post_id = post.id
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
          where comment.tenant_id = post.tenant_id
            and comment.post_id = post.id
       )
 where post.tenant_id = (select config.value::uuid from public.app_config as config where config.key = 'kathar.tenant_id')
   and (
     post.likes is distinct from (select count(*)::integer from public.kathar_post_likes as liked where liked.tenant_id = post.tenant_id and liked.post_id = post.id)
     or post.saves is distinct from (select count(*)::integer from public.kathar_saved_items as saved where saved.tenant_id = post.tenant_id and saved.kind = 'post' and saved.target_id = post.id)
     or post.comment_count is distinct from (select count(*)::integer from public.kathar_comments as comment where comment.tenant_id = post.tenant_id and comment.post_id = post.id)
   );
