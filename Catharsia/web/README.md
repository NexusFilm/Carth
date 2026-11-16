# Catharsia desktop community workspace

Responsive web client for the existing Catharsia Supabase tenant. The public Explore and community directory are readable without an account. Joining a private group, posting, and therapist host controls require a Supabase session.

## Local development

1. Keep `web/.env.local` private and provide the existing Supabase project URL, **publishable** key, tenant ID, and (optionally) the final public website origin. Never use a service-role key in this client.
2. Add the local origin (`http://localhost:5173/**`) to Supabase Authentication → URL Configuration → Redirect URLs. Google sign-in also returns to this origin.
3. Run `npm ci` then `npm run dev` from this folder.

The project uses only Supabase client access and row-level security. The public share URL is based on `VITE_PUBLIC_BASE_URL`; set it to the actual website before printing or distributing QR cards. A local preview's QR code points to that local origin.

## Host workspace

Verified Catharsia therapists and administrators can create groups, manage the group description/guidelines/member limit, review the active roster, remove members, publish therapist guidance or curated HTTPS resources, and download a print-ready SVG community card with a unique QR code. Public community pages expose group information only; discussion posts and roster remain member/host-only.

The web client is not deployed. Before launch, deploy the Vite `dist` output to the selected public host and add the production origin to Supabase Authentication redirect URLs.
