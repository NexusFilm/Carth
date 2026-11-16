# Catharsia

Native SwiftUI iOS social education app backed by the existing Supabase project shared with Viewfinder. Catharsia uses its existing Kathar tenant (`c735a494-a9c1-432a-8d44-14d38f12f0c0`); no second Supabase project or tenant was created.

Explore is open without an account. Members sign in to like, comment, save, report, or block. Only backend-authorized therapists and the owner admin can publish. Posts support up to five mixed photos and videos. Videos are limited to 60 seconds and exported as 720p MP4 below 48 MB. The app does not seed people, posts, or engagement counts. The shared live tenant currently has two real public Catharsia posts; mock and test rows stay excluded.

## Build

Requirements: Xcode 16.3 or newer and XcodeGen.

```sh
xcodegen generate
open Catharsia.xcodeproj
```

`Config/Supabase.xcconfig` contains the public project URL and tenant identifiers. The ignored `Config/Supabase.local.xcconfig` contains the project's publishable client key. XcodeGen writes those values and the native OAuth callback into `Config/Info.plist` for the app bundle. Never place a Supabase secret or service-role key in the iOS app.

The app bundle ID is `com.catharsia.ios`; the OAuth callback is `com.catharsia.ios://login-callback`. Google OAuth is enabled in the existing Supabase project, and its callback is on the Supabase redirect allow-list. The Google identity for `derric.chambers@gmail.com` is already linked to that Supabase account. No Firebase `GoogleService-Info.plist` is used. Apple device installation requires an active developer-team account and provisioning profile.

## Features

- Full-screen vertical Explore feed with chronological pagination and truthful empty, loading, and error states.
- Email/password, Google OAuth, and Apple Sign-In using the shared Supabase Auth identity.
- Member likes, comments, saved posts, reporting, blocking, and report review for admins.
- Photo/video carousel composer, in-app camera, 720p export, 48 MiB client cap, and backend therapist/admin gating.
- Tenant-scoped account-data deletion; the shared sign-in remains available to other Viewfinder apps.
- Light appearance, native SwiftUI controls, privacy disclosures, and crisis support.

## Reuse from Rema

The existing [Rema iOS app](https://github.com/NexusFilm/Rema) uses the same Supabase project. Catharsia follows its shared sign-in and role-gated admin patterns where they fit this product, while keeping Catharsia posts, comments, moderation, and privacy inside the Kathar tenant. Bible lessons, games, ads, and study streaks are not part of Catharsia.

## Backend files

- `Sources/Catharsia/Services`: Supabase client, Auth, feed, publishing, and interactions.
- `supabase/migrations`: Catharsia-only schema and policy changes applied to the existing project.
- `supabase/functions/kathar-delete-account`: deployed tenant-scoped account-data deletion.
- `Config/Catharsia.entitlements`: Apple Sign-In entitlement.

## Current pilot status

The app opens to public Explore and fetches the real Kathar feed. At the last backend audit, two real Catharsia posts were publicly readable and two mock/test rows were filtered out. New sign-ins are added to the Kathar tenant as members. Publishing is granted to the existing administrator and verified professionals. Signed-in clinicians can request access; an administrator must verify the active license against an official registry and record its URL before the app grants posting access. This review is manual; automated registry verification is not implemented. TestFlight uses the same live tenant, so approved therapist test posts are public in Explore, as intended for the beta.

## Media budget

The `kathar-media` bucket accepts JPEG and MP4 files up to 50 MB; the app keeps uploads below 48 MB. Ordered carousel metadata is stored with each post. Public reads keep Explore available before sign-in, and storage writes require an admin or verified therapist. Supabase Free storage and bandwidth are limited, so 50,000 monthly active users does not mean video viewing will remain free. Keep media lean and review usage before growing the audience. Cloudflare R2 may reduce egress costs later, but needs a signed-upload path and has its own free-tier quotas.
