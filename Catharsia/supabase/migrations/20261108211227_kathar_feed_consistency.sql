-- Keep Catharsia's public feed, comments, and feed cursor on the same visibility rules.
-- These changes are scoped to Kathar and do not alter the shared tenant project.

create index if not exists kathar_posts_feed_tenant_created_id_idx
  on public.kathar_posts (tenant_id, created_at desc, id desc)
  where is_mock = false and is_test = false;

create or replace function public.kathar_can_view_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.kathar_posts p
    left join public.kathar_professional_access_grants g
      on g.professional_id = p.professional_id
     and g.tenant_id = p.tenant_id
     and lower(g.viewer_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    left join public.kathar_profiles author_profile on author_profile.id = p.author_user_id
    where p.id = p_post_id
      and p.tenant_id = public.kathar_tenant_id()
      and not coalesce(p.is_mock, false)
      and (
        not p.is_test
        or p.author_user_id = auth.uid()
        or public.kathar_is_admin()
        or g.id is not null
      )
      and (
        coalesce(author_profile.deactivated, false) = false
        or p.author_user_id = auth.uid()
        or public.kathar_is_admin()
      )
  );
$function$;

drop policy if exists kathar_comments_read on public.kathar_comments;
create policy kathar_comments_read
  on public.kathar_comments for select to public
  using (
    tenant_id = public.kathar_tenant_id()
    and public.kathar_can_view_post(post_id)
  );

drop policy if exists kathar_comments_create on public.kathar_comments;
create policy kathar_comments_create
  on public.kathar_comments for insert to public
  with check (
    tenant_id = public.kathar_tenant_id()
    and public.kathar_is_member()
    and author_id = auth.uid()
    and public.kathar_can_view_post(post_id)
  );
