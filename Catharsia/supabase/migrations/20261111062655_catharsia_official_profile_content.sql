alter table public.kathar_professionals
  add column if not exists core_values text;

update public.kathar_professionals
set
  bio = case
    when bio is null or btrim(bio) = '' or bio = 'The official Catharsia platform profile.'
      then 'Catharsia is a welcoming space to hear from verified therapists, share perspectives, and find compassionate support. Explore freely; sign in only when you choose to take part.'
    else bio
  end,
  core_values = coalesce(nullif(btrim(core_values), ''), 'Care over clicks · Clinically credible guidance · Privacy and choice · Compassionate conversation · Room for every story.'),
  custom_links = case
    when exists (
      select 1
      from jsonb_array_elements(coalesce(kathar_professionals.custom_links, '[]'::jsonb)) as item
      where item->>'url' = 'https://988lifeline.org/get-help/'
    ) then coalesce(kathar_professionals.custom_links, '[]'::jsonb)
    else coalesce(kathar_professionals.custom_links, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'id', '988-suicide-crisis-lifeline',
      'title', '988 Suicide & Crisis Lifeline',
      'detail', 'Call, text, or chat for free, confidential support.',
      'url', 'https://988lifeline.org/get-help/',
      'kind', 'resource',
      'position', jsonb_array_length(coalesce(kathar_professionals.custom_links, '[]'::jsonb))
    ))
  end
where is_platform = true
  and verified = true
  and verification_status = 'verified'
  and verification_tier = 'verified_professional';
