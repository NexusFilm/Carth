# Catharsia web

Responsive Catharsia client for the existing Supabase tenant. The shared shell follows the app’s four sections: **Explore**, **Saved**, **Communities**, and **Profile**. Therapist group management lives inside Communities; verified admins see the Admin overview inside Profile.

## Local development

1. Copy `.env.example` to `.env.local` and add the existing Supabase project URL, publishable key, Kathar tenant ID, and public base URL. Keep `.env.local` private. Never use a Supabase secret or service-role key in the browser.
2. Add `http://localhost:5173/**` to Supabase Authentication → URL Configuration → Redirect URLs for web sign-in.
3. Run `npm ci` and `npm run dev` from this folder.

The app uses Supabase Auth, Postgres row-level security, and Storage directly. Public Explore and the community directory remain readable without signing in. Sign-in is needed to save or appreciate posts, join groups, edit a profile, or use host tools.

## Profile and administration

Profiles edit their display name, username, bio, and photo in `kathar_profiles`. Photos use the tenant-scoped `kathar-profile-avatars` bucket. The Admin overview is rendered only after `kathar_is_admin()` confirms the current session, and its totals are tenant-scoped exact counts from Supabase.

## Therapist workspace

Verified therapists and administrators can manage groups from the Communities section, edit group details, review active members, publish guidance or secure resource links, and create a share card with a unique QR code. Public community URLs remain shareable at `/community/:id`.

## Production

The web client deploys to Vercel as the `catharsia` project. The production domain is `https://catharsia.com`; set `VITE_PUBLIC_BASE_URL` to that address before generating printed QR cards. Keep the domain in Supabase Auth’s redirect allow-list.
