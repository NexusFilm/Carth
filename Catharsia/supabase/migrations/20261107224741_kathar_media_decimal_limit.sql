-- Use decimal megabytes for the service-side cap so the app's 48 MB target
-- remains below a plain-language 50 MB limit.
update storage.buckets
   set file_size_limit = 50000000
 where id = 'kathar-media';

do $migration$
begin
  if not exists (select 1 from storage.buckets where id = 'kathar-media') then
    raise exception 'Catharsia media bucket kathar-media is missing';
  end if;
end;
$migration$;
