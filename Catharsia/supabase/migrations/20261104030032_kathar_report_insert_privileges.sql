-- Content reports must be created through kathar_create_content_report so the
-- function validates the target and captures the current signed-in reporter.
-- Do not allow direct INSERTs through the public Data API.
revoke insert on table public.kathar_reports from public, anon, authenticated;
