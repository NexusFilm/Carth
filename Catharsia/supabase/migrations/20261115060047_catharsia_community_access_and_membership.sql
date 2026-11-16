-- Keep the community directory public while keeping internal therapist email
-- lists and member details unavailable to public clients.
create schema if not exists kathar_private;
revoke all on schema kathar_private from public, anon, authenticated;

drop policy if exists kathar_communities_create on public.kathar_communities;
create policy kathar_communities_create
on public.kathar_communities
for insert to authenticated
with check (
    tenant_id = kathar_tenant_id()
    and is_mock = false
    and owner_user_id = (select auth.uid())
    and (
        kathar_is_admin()
        or (professional_id is not null and kathar_can_publish_as_professional(professional_id))
    )
);

drop policy if exists kathar_communities_read on public.kathar_communities;
create policy kathar_communities_read
on public.kathar_communities
for select to anon, authenticated
using (tenant_id = kathar_tenant_id() and is_mock = false);

drop policy if exists kathar_communities_update on public.kathar_communities;
create policy kathar_communities_update
on public.kathar_communities
for update to authenticated
using (tenant_id = kathar_tenant_id() and (owner_user_id = (select auth.uid()) or kathar_is_admin()))
with check (tenant_id = kathar_tenant_id() and is_mock = false and (owner_user_id = (select auth.uid()) or kathar_is_admin()));

drop policy if exists kathar_communities_delete on public.kathar_communities;
create policy kathar_communities_delete
on public.kathar_communities
for delete to authenticated
using (tenant_id = kathar_tenant_id() and (owner_user_id = (select auth.uid()) or kathar_is_admin()));

-- Imported community rows contain private email arrays and moderator credentials.
revoke all on public.kathar_communities from public, anon, authenticated;
grant select (tenant_id, id, name, topic, description, cover_url, members, member_limit,
              professional_id, owner_user_id, guidelines, created_at, updated_at)
on public.kathar_communities to anon, authenticated;
grant insert (tenant_id, name, topic, description, cover_url, member_limit,
              professional_id, owner_user_id, guidelines, is_mock)
on public.kathar_communities to authenticated;
grant update (name, topic, description, cover_url, member_limit, guidelines, updated_at)
on public.kathar_communities to authenticated;
grant delete on public.kathar_communities to authenticated;

drop policy if exists kathar_community_members_read on public.kathar_community_members;
create policy kathar_community_members_read
on public.kathar_community_members
for select to authenticated
using (
    tenant_id = kathar_tenant_id()
    and (
        user_id = (select auth.uid())
        or community_owner_id = (select auth.uid())
        or kathar_is_admin()
    )
);

drop policy if exists kathar_community_members_write on public.kathar_community_members;
create policy kathar_community_members_join
on public.kathar_community_members
for insert to authenticated
with check (
    tenant_id = kathar_tenant_id()
    and user_id = (select auth.uid())
    and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and role = 'member'
    and status = 'active'
    and exists (
        select 1 from public.kathar_communities c
        where c.id = community_id
          and c.tenant_id = (select kathar_tenant_id())
          and c.owner_user_id is not distinct from community_owner_id
          and c.is_mock = false
    )
);

create policy kathar_community_members_rejoin
on public.kathar_community_members
for update to authenticated
using (tenant_id = kathar_tenant_id() and user_id = (select auth.uid()))
with check (
    tenant_id = kathar_tenant_id()
    and user_id = (select auth.uid())
    and role = 'member'
    and status = 'active'
    and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

create policy kathar_community_members_moderate
on public.kathar_community_members
for update to authenticated
using (
    tenant_id = kathar_tenant_id()
    and (community_owner_id = (select auth.uid()) or kathar_is_admin())
)
with check (
    tenant_id = kathar_tenant_id()
    and (community_owner_id = (select auth.uid()) or kathar_is_admin())
    and status in ('active', 'removed')
);

create policy kathar_community_members_leave
on public.kathar_community_members
for delete to authenticated
using (
    tenant_id = kathar_tenant_id()
    and (user_id = (select auth.uid()) or community_owner_id = (select auth.uid()) or kathar_is_admin())
);

revoke all on public.kathar_community_members from public, anon, authenticated;
grant select (tenant_id, id, community_id, community_owner_id, user_id, display_name,
              role, status, description, created_at, updated_at)
on public.kathar_community_members to authenticated;
grant insert (tenant_id, community_id, community_owner_id, user_id, email, display_name, role, status)
on public.kathar_community_members to authenticated;
grant update (status, updated_at) on public.kathar_community_members to authenticated;
grant delete on public.kathar_community_members to authenticated;

create or replace function kathar_private.guard_community_member_capacity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
    v_limit integer;
    v_members integer;
begin
    if new.status = 'active' and tg_op = 'INSERT' then
        select c.member_limit, c.members
          into v_limit, v_members
          from public.kathar_communities c
         where c.id = new.community_id and c.tenant_id = new.tenant_id and c.is_mock = false
         for update;
        if not found then
            raise exception 'Community is unavailable';
        end if;
        if v_members >= v_limit then
            raise exception 'This community is full';
        end if;
    elsif new.status = 'active' and old.status <> 'active' then
        select c.member_limit, c.members
          into v_limit, v_members
          from public.kathar_communities c
         where c.id = new.community_id and c.tenant_id = new.tenant_id and c.is_mock = false
         for update;
        if not found then
            raise exception 'Community is unavailable';
        end if;
        if v_members >= v_limit then
            raise exception 'This community is full';
        end if;
    end if;
    return new;
end;
$$;
revoke all on function kathar_private.guard_community_member_capacity() from public, anon, authenticated;

create or replace function kathar_private.sync_community_member_count()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
    if tg_op = 'INSERT' and new.status = 'active' then
        update public.kathar_communities
           set members = members + 1, updated_at = now()
         where id = new.community_id and tenant_id = new.tenant_id;
    elsif tg_op = 'DELETE' and old.status = 'active' then
        update public.kathar_communities
           set members = greatest(0, members - 1), updated_at = now()
         where id = old.community_id and tenant_id = old.tenant_id;
    elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
        update public.kathar_communities
           set members = greatest(0, members + case when new.status = 'active' then 1 else -1 end),
               updated_at = now()
         where id = new.community_id and tenant_id = new.tenant_id;
    end if;
    return null;
end;
$$;
revoke all on function kathar_private.sync_community_member_count() from public, anon, authenticated;

drop trigger if exists kathar_community_member_capacity on public.kathar_community_members;
create trigger kathar_community_member_capacity
before insert or update of status on public.kathar_community_members
for each row execute function kathar_private.guard_community_member_capacity();

drop trigger if exists kathar_community_member_count on public.kathar_community_members;
create trigger kathar_community_member_count
after insert or update of status or delete on public.kathar_community_members
for each row execute function kathar_private.sync_community_member_count();

drop policy if exists kathar_community_posts_read on public.kathar_community_posts;
create policy kathar_community_posts_read
on public.kathar_community_posts
for select to authenticated
using (
    tenant_id = kathar_tenant_id()
    and exists (
        select 1 from public.kathar_communities c
        where c.id = community_id
          and c.tenant_id = (select kathar_tenant_id())
          and c.is_mock = false
          and (
              c.owner_user_id = (select auth.uid())
              or kathar_is_admin()
              or exists (
                  select 1 from public.kathar_community_members m
                  where m.community_id = c.id
                    and m.tenant_id = c.tenant_id
                    and m.user_id = (select auth.uid())
                    and m.status = 'active'
              )
          )
    )
);

drop policy if exists kathar_community_posts_write on public.kathar_community_posts;
create policy kathar_community_posts_create
on public.kathar_community_posts
for insert to authenticated
with check (
    tenant_id = kathar_tenant_id()
    and author_user_id = (select auth.uid())
    and exists (
        select 1 from public.kathar_communities c
        where c.id = community_id
          and c.tenant_id = (select kathar_tenant_id())
          and c.is_mock = false
          and (
              c.owner_user_id = (select auth.uid())
              or kathar_is_admin()
              or (
                  kind in ('comment', 'reply')
                  and exists (
                      select 1 from public.kathar_community_members m
                      where m.community_id = c.id and m.tenant_id = c.tenant_id
                        and m.user_id = (select auth.uid()) and m.status = 'active'
                  )
              )
          )
    )
    and (
        kind in ('comment', 'reply')
        or (kind = 'group_post' and (kathar_is_admin() or exists (
            select 1 from public.kathar_communities c
            where c.id = community_id and c.tenant_id = (select kathar_tenant_id()) and c.owner_user_id = (select auth.uid())
        )))
    )
    and (
        kind in ('comment', 'reply')
        or kathar_is_admin()
        or exists (
            select 1 from public.kathar_communities c
            where c.id = community_id
              and c.tenant_id = (select kathar_tenant_id())
              and c.owner_user_id = (select auth.uid())
              and c.professional_id is not null
              and kathar_can_publish_as_professional(c.professional_id)
        )
    )
);

create policy kathar_community_posts_update
on public.kathar_community_posts
for update to authenticated
using (
    tenant_id = kathar_tenant_id()
    and (author_user_id = (select auth.uid()) or kathar_is_admin() or exists (
        select 1 from public.kathar_communities c
        where c.id = community_id and c.tenant_id = (select kathar_tenant_id()) and c.owner_user_id = (select auth.uid())
    ))
)
with check (tenant_id = kathar_tenant_id() and author_user_id = (select auth.uid()));

create policy kathar_community_posts_delete
on public.kathar_community_posts
for delete to authenticated
using (
    tenant_id = kathar_tenant_id()
    and (author_user_id = (select auth.uid()) or kathar_is_admin() or exists (
        select 1 from public.kathar_communities c
        where c.id = community_id and c.tenant_id = (select kathar_tenant_id()) and c.owner_user_id = (select auth.uid())
    ))
);

revoke all on public.kathar_community_posts from public, anon, authenticated;
grant select (tenant_id, id, legacy_base44_id, community_id, parent_id, kind, title, format,
              media_url, link_url, author_user_id, author_name, is_professional,
              author_credentials, body, pinned, upvotes, replies, created_at, updated_at)
on public.kathar_community_posts to authenticated;
grant insert (tenant_id, community_id, parent_id, kind, title, format, media_url, link_url,
              author_user_id, author_name, body)
on public.kathar_community_posts to authenticated;
grant update (title, format, media_url, link_url, body, updated_at)
on public.kathar_community_posts to authenticated;
grant delete on public.kathar_community_posts to authenticated;
