-- The public feed and professional profile query these non-sensitive fields.
-- Keep the table's restricted column-level grants for license and application data.
grant select (verification_status, verification_tier, core_values)
  on table public.kathar_professionals
  to anon, authenticated;
