-- Catharsia media is stored as an ordered list so a post can render a mixed
-- photo/video carousel while older single-image rows continue to work.
alter table public.kathar_posts
  add column if not exists media_items jsonb not null default '[]'::jsonb;

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.kathar_posts'::regclass
       and conname = 'kathar_posts_media_items_limit'
  ) then
    alter table public.kathar_posts
      add constraint kathar_posts_media_items_limit
      check (
        case
          when jsonb_typeof(media_items) = 'array' then jsonb_array_length(media_items) <= 5
          else false
        end
      );
  end if;
end;
$migration$;

-- Free-plan upload maximum. Only optimized JPEG photos and H.264/AAC MP4 clips
-- are accepted; the app compresses before upload and leaves headroom below 50MB.
update storage.buckets
   set file_size_limit = 52428800,
       allowed_mime_types = array['image/jpeg', 'video/mp4']::text[]
 where id = 'kathar-media';

do $migration$
begin
  if not exists (select 1 from storage.buckets where id = 'kathar-media') then
    raise exception 'Catharsia media bucket kathar-media is missing';
  end if;
end;
$migration$;
