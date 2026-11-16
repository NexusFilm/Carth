# Catharsia MVP readiness plan

## Product decisions

- Explore is public before sign-in. Sign-in is required for likes, comments, saves, and account settings.
- Only the official Catharsia account and therapists approved by the Catharsia admin can publish.
- Approved beta therapists' posts are public in Explore, including posts made during TestFlight.
- Public posts are chronological for the MVP. The goal is useful, supportive conversation, not maximizing time in the app or raw engagement.
- Photos and short videos share the same composer. Up to five media items are supported; video is capped at 60 seconds and 48 MB before upload.

## Audit findings and work completed

### Feed reliability

- Explore requests exclude mock and test posts. The two seeded mock rows were removed; the user's two real official posts remain public.
- Pull-to-refresh cancellation is no longer presented as a network error. App launch uses the normal loading state instead of triggering the pull-refresh animation.
- Feed refresh, post counters, post timestamps, and carousel media are implemented in the app. The iOS project builds successfully; the carousel and cold-launch behavior still need a physical-device pass before TestFlight.

### Accounts and publishing access

- Google sign-in is connected to the existing Supabase Auth project. The admin account is the existing `derric.chambers@gmail.com` identity; do not create a duplicate.
- The backend already supports therapist applications, admin review, and publishing only after approval. Approval is a human check against an official license registry URL; automated license verification is not configured.
- New beta therapist posts use the normal public post path. The publisher does not set `is_test`, so public Explore does not hide beta posts.
- No therapist test account or credentials were fabricated. Full second-publisher proof still requires a real therapist to sign in, apply with their actual credential details, and be approved by the admin.

### Member profiles and role protection — implemented

- Added **Settings → Personal profile** for signed-in members: display name, optional username, and optional profile image.
- Comments now resolve the current public display name, username, and avatar from the Catharsia profile.
- Added a dedicated public-read avatar bucket capped at 4 MB. Uploads and deletes are limited to each authenticated member's tenant/user folder.
- Narrowed `kathar_profiles` client writes so users cannot change role, tenant, email, or deactivation fields, and cannot insert, delete, or truncate profile rows.
- Updated account deletion to remove Catharsia avatar files. The JWT-protected Supabase function is deployed as version 6.
- Updated the in-app privacy text to disclose public display names, usernames, and photos.
- Added Xcode version/build settings and split APNs entitlements by configuration: Debug uses sandbox; Release uses production.

## Remaining steps, in order

1. **Device pass for profiles and feed:** sign in as the existing admin, edit the name/username/photo, add a comment, confirm the avatar and username appear, then relaunch and confirm both official posts and carousel media remain. Check a signed-out session can still view Explore and cannot publish.
2. **Therapist beta pass:** have one real therapist apply; verify their license in its official registry; approve from the admin account; publish a post; confirm it appears publicly in Explore and on that therapist's post/profile view. Then test a regular member can interact but cannot publish.
3. **Notification pass:** verify activity inbox creation, delete-one and clear-all actions, deep links, per-category preferences, and APNs banner delivery on the iPhone. Debug uses sandbox APNs; TestFlight uses production APNs.
4. **Safety and accessibility pass:** verify comment/post report and delete flows, block/unblock behavior, account deletion, VoiceOver labels, Dynamic Type, contrast, keyboard dismissal, and iPad rotation.
5. **Policy and listing pass:** the updated privacy page is deployed on nexusmobiletech.com and returns HTTP 200. Its served JavaScript includes the November 11 update, profile disclosure, and 60-second video limit. The owner can finish the remaining App Store listing details later.
6. **TestFlight setup:** the 1.0 (1) build was uploaded successfully and is processing in App Store Connect. Once processing completes, the owner can finish TestFlight beta details, create a tester group, and invite the chosen therapists. No app review or public release has been submitted.

## Current release state

- Local iOS archive: **succeeds** as version 1.0 (build 1); the App Store Connect export re-signed and uploaded successfully.
- Live Catharsia tenant: **two real official posts, zero seeded mock posts**.
- Approved therapist publisher: **none confirmed yet**; the admin path is ready, but the second-publisher test needs a real therapist.
- TestFlight: **uploaded; processing**. The new official Catharsia App Store Connect record is `6833532078` for `com.catharsia.ios`. The older unpublished record `6797089910` used `com.nexusapps.catharsia` and was moved to Removed Apps to free the Catharsia name, as requested.
- Public privacy page: **deployed to nexusmobiletech.com and live**.
