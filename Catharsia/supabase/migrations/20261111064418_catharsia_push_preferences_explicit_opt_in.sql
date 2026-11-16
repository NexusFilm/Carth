alter table public.catharsia_push_preferences
    alter column manual_push_enabled set default false,
    alter column auto_push_enabled set default false;
