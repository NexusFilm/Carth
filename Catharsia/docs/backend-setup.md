# Supabase backend

## Existing project and tenant

Catharsia uses the existing Supabase project shared by the Nexus/Viewfinder apps: `olypztthdzctunsoopwi`. Its Kathar tenant is `c735a494-a9c1-432a-8d44-14d38f12f0c0`. This work did not create another project or tenant and did not modify Rema's tenant data.

The feed is backed by `kathar_posts`; the app filters out mock and test rows. The two seeded mock posts were removed from the Catharsia tenant during the latest audit. The two real official posts remain public in Explore. Therapist and administrator publishing is checked against tenant roles on the backend.

## App configuration

- Project URL and tenant IDs are in `Config/Supabase.xcconfig`.
- The ignored `Config/Supabase.local.xcconfig` holds only the publishable client key.
- Never embed a service-role key or other Supabase secret in the app.
- Bundle ID: `com.catharsia.ios`.
- Native OAuth callback: `com.catharsia.ios://login-callback`.

Google OAuth is enabled in the existing Supabase Auth project, and `com.catharsia.ios://login-callback` is in the redirect allow-list. The native callback and URL scheme are generated into the iOS app bundle from `project.yml`. The Google provider secret stays in Supabase and is never included in the app. The app does not use Firebase or a `GoogleService-Info.plist`. Apple Sign-In is optional for the first pilot; its entitlement is included in the target.

## Tenant protections

Migrations in `supabase/migrations` add tenant-scoped blocking and reporting, limit report creation to the authenticated RPC, and prevent signups from unrelated apps from silently joining Catharsia. The app calls `kathar_ensure_current_user()` to add a person who signs into Catharsia.

New sign-ins receive the `member` tenant role. Publishing remains limited to the tenant administrator and professional records already marked verified in `kathar_professionals`. Signed-in clinicians can submit an application in the iOS app. A tenant administrator must check the active license against an official public registry and record the HTTPS source URL before approval; the migration grants no automated registry verification. The license number stays in the RLS-protected application row and is not copied to the public professional profile.

Signed-in members can edit their public display name, optional username, and optional profile photo in **Settings → Personal profile**. Profile editing is limited to those public fields; authenticated clients cannot insert, delete, truncate, or change the role, tenant, email, or deactivation fields on `kathar_profiles`. Avatar images use the dedicated public-read `kathar-profile-avatars` bucket, limited to 4 MB. Upload and delete policies restrict writes to the member's own tenant/user path. Account deletion also removes that user's Catharsia avatar objects.

TestFlight currently uses the same live Supabase project and Kathar tenant as the two official posts. After the administrator verifies a therapist application, that therapist can publish real, public posts visible in Explore. Do not use the `is_test` flag for these beta posts; that flag intentionally hides posts from the public feed.

The deployed `kathar-delete-account` Edge Function is JWT-protected. It removes Catharsia profile, posts, comments, engagement, reports submitted by that user, verification documents, tenant-scoped media, and profile avatars. Supabase Auth identity is shared with other apps, so deletion intentionally leaves that identity available to Rema/Viewfinder. The function uses server-only credentials; none are in the iOS bundle.

## Catharsia push notifications

The official announcement composer is available in the iOS app under **Settings → Admin tools → Official announcements**. It writes an in-app notification for Catharsia accounts and can link to Explore, Saved posts, or Profile. APNs alerts follow each recipient’s Catharsia announcement preference; the administrator is included and can enable their own alerts under **Settings → Push alerts**. Likes and comments use a separate preference. The activity inbox stays focused on notifications while push controls live in Settings.

Catharsia shares the Supabase project but has its own `catharsia-push` entry point, bundle ID (`com.catharsia.ios`), push settings, device-token partition, and `catharsia_push_preferences` table. The shared `send-push` dispatcher requires Catharsia-specific environment keys for this bundle and does not fall back to a generic Nexus/Rhema APNs key. Other app bundle IDs retain their existing key path. The Catharsia preferences default to off so people choose whether they want social interaction alerts or Catharsia announcements; in-app activity remains available in the notification center.

Store APNs credentials only as Supabase Edge Function secrets:

- `APNS_TEAM_ID`
- `CATHARSIA_APNS_SANDBOX_KEY_ID` and `CATHARSIA_APNS_SANDBOX_PRIVATE_KEY` for development builds
- `CATHARSIA_APNS_PRODUCTION_KEY_ID` and `CATHARSIA_APNS_PRODUCTION_PRIVATE_KEY` for TestFlight and App Store builds

Apple’s development APNs environment is called **Sandbox**. Xcode development builds register sandbox device tokens; TestFlight and distribution builds register production tokens. Each request is routed to the environment recorded with its Catharsia device token. The production key is a dedicated team-scoped APNs key named `CatharsiaPushProduction` (Key ID `7XGYVMPS63`). Apple’s key scope picker did not respond, so it has All Topics access for Team `DG4DARLJ54`. The Catharsia dispatcher only selects it for `com.catharsia.ios`; keep the key in Supabase secrets and never copy it into the iOS app or another app’s configuration.

## Photo and video storage

`kathar_posts.media_items` stores an ordered list of up to five media objects. `kathar-media` remains public-read so Explore works before sign-in, and accepts JPEG and MP4 only with a 50 MB object limit. The app exports videos to 720p MP4, at most 60 seconds and 48 MB. Database storage policies permit uploads and updates only for the tenant admin and verified clinicians. The composer streams local files into Supabase Storage and removes uploaded objects if saving the post fails.

Supabase's 50,000 monthly active user authentication allowance is separate from storage and bandwidth quotas. Video playback can exceed the free media quota well before 50,000 people. Monitor project usage as posts and viewing begin. Cloudflare R2 is a possible lower-egress media store later, with additional signed-upload setup and its own free-tier quotas.

## Owner publishing

`derric.chambers@gmail.com` already has a Supabase Auth account, Kathar profile, and tenant-admin membership. Sign in with that account through Catharsia; do not create a duplicate. Backend admin publishing is ready for that identity.
