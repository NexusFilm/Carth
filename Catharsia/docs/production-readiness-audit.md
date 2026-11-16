# Catharsia production readiness audit

Updated: 2026-11-14

## Current device build and signing status

- The iPhone 15 Pro Max is connected. Catharsia was installed and launched from a device build containing the current Swift source, including the idempotent save fix.
- That first install came from a stale generated Xcode project configured for `DG4DARLJ54`; the source `project.yml` specifies `NP2PB46J97`.
- Regenerated `Catharsia.xcodeproj` from `project.yml` to remove that mismatch. The corrected device build now fails because Xcode has no signed-in account for team `NP2PB46J97` and no matching iOS Development provisioning profile.
- The app on the phone is therefore the prior install. A correctly team-signed build still needs the Apple Developer account added to Xcode, then a fresh build and install.
- Internal Mac storage now reports 5.9 GB available. Cleanup removed replaceable npm and Comet caches plus generated Catharsia build output. The active uv tool runtime was left intact.

## Current product readiness

Catharsia is not ready for public launch yet. The highest priority gates are: correct team signing and TestFlight delivery; a real-device one-finger feed/media pass; a second therapist publishing/onboarding pass; production APNs delivery; and completion of privacy, safety, and App Store review checks. The verified app still has only two live posts, so a broader content and account-flow check also remains.

## Feed changes in this pass

- Explore is a continuous vertical scroll view with native deceleration. The old full-screen vertical paging behavior is removed.
- Each post keeps its own engagement rail; no rail is pinned across posts.
- Carousel media uses a native horizontal scroll view with page snapping inside the media frame. The outer vertical feed keeps its own vertical scroll gesture.
- Post cards use 4:5 for photos and 9:16 for videos.
- The Explore header now occupies its own layout space so the first author row does not begin underneath it.
- The lilac atmosphere is lighter.
- The current simulator build compiles and launches with the two live Catharsia posts.

## Live backend snapshot

The Supabase project is active and healthy. Its Catharsia tenant currently has two public posts, zero mock posts, zero test posts, and one verified official profile.

The `kathar-media` bucket is public-read, accepts JPEG/PNG/WebP/MP4, and caps files at 50 MiB. The app upload limit is 48,000,000 bytes, leaving headroom below the bucket limit. The profile avatar bucket caps files at 4 MiB. The identity-document bucket is private.

Google sign-in has already been confirmed by the owner on the physical iPhone. The iPhone 15 Pro Max is currently connected to this Mac. The feed gesture pass has not yet been completed on the device.

## Backend findings to close before public release

- Supabase’s project-wide security advisor reports six push administration tables with RLS enabled but no policies. The live database also grants the client roles table privileges. RLS currently denies rows because there are no policies, but this should be converted to explicit service-only grants and rechecked against the other apps sharing this project before release.
- The advisor reports executable `SECURITY DEFINER` RPCs. Catharsia uses some role and visibility helpers from RLS policies, so those cannot be revoked indiscriminately. Review each exposed helper and restrict only functions that are not needed by public feed policy evaluation.
- Supabase reports leaked-password protection is not enabled for one Auth configuration.
- The performance advisor reports many unindexed foreign keys across the shared project. Do not add indexes across other tenants blindly; profile Catharsia’s actual feed and moderation queries first.

## Distribution gates

1. **Real-device gesture pass:** one-finger vertical fling between at least three posts; horizontal media swipes; tap actions; verify the gestures never need a second finger and controls only activate within their own hit areas.
2. **Media pass:** publish and view at least one real 9:16 video plus a photo carousel, test upload limits, playback after relaunch, and poor-network loading.
3. **Account and publisher pass:** browse signed out; sign in and use likes/comments/saves; use one real therapist account to submit an access request, approve it, publish, edit, and delete. This second publisher flow has not yet been proven.
4. **Notifications:** receive an APNs production alert from a TestFlight build, then validate the in-app inbox, badge, and destinations.
5. **Apple signing:** `project.yml` uses team `NP2PB46J97`, which matches the installed Apple Development identities and Catharsia App Store Connect record. The generated Xcode project is now synchronized, but Xcode currently has no account for that team and no matching iOS Development profile. A signed Release archive still needs to confirm the Distribution certificate/profile and current Developer Program agreement.
6. **App Review:** provide review credentials/instructions, keep the in-app privacy policy and public privacy URL aligned, and recheck account deletion, UGC report/block, support contact, and App Store privacy declarations.
7. **Marketing:** the root of `nexusmobiletech.com` is still the Nexus portfolio, not a Catharsia launch page. Per-therapist QR/share links and the Universal Link association file are not implemented. The App Store call-to-action should be connected to the approved listing before public launch.

## Source of truth

The local Catharsia checkout at `/Volumes/LaCie/Carth/Carth/Catharsia` has no Git remote configured, and the connected GitHub account did not return a Catharsia iOS repository by name or bundle identifier. The Nexus marketing-site repository exists separately as `NexusFilm/nexus-mobile-tech-universe`. Confirm the intended app repository/source of truth before pushing the iOS changes.

## Current build state

The current code has a successful unsigned iOS Simulator build. A device build was installed and launched using the stale generated project, then the project was regenerated from `project.yml`; the corrected team-signed device build is currently blocked by missing Xcode account/profile access. No signed App Store archive or new TestFlight build has been uploaded, and no public release has been submitted. The previously uploaded TestFlight version is an older build and does not include the feed changes above.
