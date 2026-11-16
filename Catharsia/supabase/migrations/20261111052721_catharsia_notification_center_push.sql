-- Catharsia social notification history and APNs dispatch state.
alter table public.kathar_notifications
  drop constraint if exists kathar_notifications_kind_check;

alter table public.kathar_notifications
  add constraint kathar_notifications_kind_check
  check (kind = any (array[
    'new_post'::text,
    'reply'::text,
    'live_event'::text,
    'community'::text,
    'verification'::text,
    'like'::text,
    'comment'::text
  ]));

alter table public.kathar_notifications
  add column if not exists push_sent_at timestamptz;

create index if not exists kathar_notifications_tenant_recipient_idx
  on public.kathar_notifications (tenant_id, recipient_user_id, read, created_at desc);

-- Keep Catharsia push configuration isolated by bundle ID in the shared Nexus project.
insert into public.push_app_configs (bundle_id, display_name, platform, enabled)
values ('com.catharsia.ios', 'Catharsia', 'ios', true)
on conflict (bundle_id) do update
set display_name = excluded.display_name,
    platform = excluded.platform,
    enabled = true,
    updated_at = now();

insert into public.push_app_settings (
  bundle_id,
  notifications_enabled,
  production_enabled,
  sandbox_enabled,
  broadcast_enabled,
  notes
)
values (
  'com.catharsia.ios',
  true,
  true,
  true,
  true,
  'Catharsia targeted social activity notifications.'
)
on conflict (bundle_id) do update
set notifications_enabled = true,
    production_enabled = true,
    sandbox_enabled = true,
    broadcast_enabled = true,
    notes = excluded.notes,
    updated_at = now();

-- Create the in-app notification in the same transaction as the social action.
-- These functions run as the signed-in caller; the existing tenant/actor RLS
-- policy on kathar_notifications remains in force.
create or replace function public.kathar_notify_post_like()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  recipient_id uuid;
begin
  select p.author_user_id
    into recipient_id
    from public.kathar_posts as p
   where p.tenant_id = new.tenant_id
     and p.id = new.post_id;

  if recipient_id is null or recipient_id = new.user_id then
    return new;
  end if;

  insert into public.kathar_notifications (
    tenant_id,
    legacy_base44_id,
    recipient_user_id,
    actor_user_id,
    kind,
    title,
    detail,
    entity_id
  ) values (
    new.tenant_id,
    'catharsia:like:' || new.tenant_id::text || ':' || new.post_id::text || ':' || new.user_id::text || ':' || new.created_at::text,
    recipient_id,
    new.user_id,
    'like',
    'New like',
    'Someone liked your post.',
    new.post_id
  ) on conflict (legacy_base44_id) do nothing;

  return new;
end;
$$;

create or replace function public.kathar_notify_post_comment()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  recipient_id uuid;
begin
  if new.author_id is null then
    return new;
  end if;

  select p.author_user_id
    into recipient_id
    from public.kathar_posts as p
   where p.tenant_id = new.tenant_id
     and p.id = new.post_id;

  if recipient_id is null or recipient_id = new.author_id then
    return new;
  end if;

  insert into public.kathar_notifications (
    tenant_id,
    legacy_base44_id,
    recipient_user_id,
    actor_user_id,
    kind,
    title,
    detail,
    entity_id
  ) values (
    new.tenant_id,
    'catharsia:comment:' || new.id::text,
    recipient_id,
    new.author_id,
    'comment',
    'New comment',
    'Someone commented on your post.',
    new.post_id
  ) on conflict (legacy_base44_id) do nothing;

  return new;
end;
$$;

drop trigger if exists kathar_post_likes_notify_owner on public.kathar_post_likes;
create trigger kathar_post_likes_notify_owner
after insert on public.kathar_post_likes
for each row execute function public.kathar_notify_post_like();

drop trigger if exists kathar_comments_notify_owner on public.kathar_comments;
create trigger kathar_comments_notify_owner
after insert on public.kathar_comments
for each row execute function public.kathar_notify_post_comment();
