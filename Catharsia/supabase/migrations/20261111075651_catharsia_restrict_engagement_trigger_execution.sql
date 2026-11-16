-- Trigger-only helpers update aggregate counters after private engagement writes.
-- Clients must never call them directly through Supabase RPC.
revoke all on function public.kathar_sync_post_save_count() from public;
revoke all on function public.kathar_sync_post_save_count() from anon, authenticated;
revoke all on function public.kathar_sync_post_comment_count() from public;
revoke all on function public.kathar_sync_post_comment_count() from anon, authenticated;
