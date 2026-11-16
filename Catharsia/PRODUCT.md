# Catharsia Product

## Purpose

Catharsia is a hopeful way to discover real, verified therapists through their educational content, therapist-led communities, and practice events. Explore opens directly to a full-screen vertical feed. Reading public posts and community descriptions is open; signing in is reserved for actions that save or submit account-linked data or join a private community.

## Roles

- Visitors can browse therapist posts and safety information.
- Members can like, comment on, and save public posts, and can report or block accounts. Members can also participate in conversations inside communities they have joined.
- Verified therapists can publish educational posts with the in-app camera or photo library and host therapist-led communities.
- The owner administrator can publish, manage therapist access, and review reports.

General members cannot publish. Publishing permission must be checked by the backend, not inferred from a client-side email or hidden button.

## Content

- Show only real, published records from the existing Kathar tenant in the shared Supabase project.
- Exclude rows marked as mock or test. Never invent people, content, or engagement counts.
- Show likes, comments, saves, and shares as real aggregate counts. Keep individual saves and reaction identities private; comments stay on their post and saved posts stay in the member's Saved area.
- Public therapist profiles have two sections: published Posts and the Bento profile. Show only the therapist's real published posts, with no sample tiles.
- Posts are general education, not diagnosis, treatment, or emergency care. Posts may be caption-only or include up to five ordered photos and videos. Videos are limited to 60 seconds, exported at 720p, and capped at 48 MB before upload.
- Authors can delete their own posts and comments. Members can like, comment, save, and share; account-linked actions require sign-in.
- A post may include one secure external link for an event signup, group opportunity, booking page, or resource.
- Verified therapists have a public Bento page with up to six labeled links. Event links can include a date, place, or short note so visitors know what they are opening.
- Public community details include the group name, focus, description, member limit, and shared expectations. Do not expose private member records, therapist email lists, moderator credentials, or community discussions in the public directory.
- Joined members can comment in their community. The therapist host can publish guidance and curated HTTPS resources, view the active roster, remove a member, and update the group description, guidelines, and capacity. Public community counts are synchronized from active memberships.
- Community discovery, membership, and discussion use the existing tenant-scoped Supabase tables and Row Level Security. Exclude mock groups; do not seed sample communities or discussions.

## Experience

Use a bright, expressive visual identity with the abstract paired-lobe brain mark, familiar full-screen social-feed gestures, and a compact action rail. First-time visitors see a brief welcome screen about therapist stories, groups, and events; one action opens Explore, where browsing remains public. Keep the therapist and credentials visible, make the next action obvious, and preserve clear navigation and reading controls. Communities are a peer section next to Explore, Saved, and Profile, with a short value statement and public group directory. On iPhone, hosts create and manage a group without a separate admin app. On desktop, Host Studio gives therapists a clearer overview of their groups, membership and conversation counts, editable group details, active roster, resource publishing, and community QR/share cards. A public community page explains its purpose and invites visitors to join; signed-in members see the group's private conversation. Authorized publishers get a compact inline composer above the tab bar with a progressively disclosed external-link field. Their Profile tab provides access to the Bento link editor. The camera button opens directly to a branded full-screen camera, with video as the default mode, a 60-second recording cap, an optional on-screen teleprompter, photo mode, and camera switching. Captured video is compressed to 720p MP4 under the 48 MB upload cap. Visible videos autoplay muted and loop; pause them when their post leaves view. Motion gives brief action feedback and respects Reduce Motion.

## Feed ranking

Rank for catharsis, usefulness, and safe conversation rather than time-on-app. Use explicit topic and content preferences plus meaningful comment engagement to learn what people want to see. Likes and saves can be relevance signals, but do not optimize for streaks, outrage, repeated notifications, or endless viewing. Limit repeated posts from one author, allow chronological browsing, and provide clear controls to tune recommendations. Do not use sensitive health inferences to personalize or target people.

## Privacy and safety

Do not ask visitors to sign in just to read. Keep comments and account activity attached to the signed-in account. Provide report, block, report review, privacy information, account-data deletion, and U.S. crisis support. Catharsia data deletion removes only this tenant's user data; it leaves the shared Supabase identity available to the user's other Nexus apps.

## Out of scope for this MVP

Direct messages, public member posts, clinical records, and treatment workflows. Reuse features from other Nexus apps only when they fit therapist-authored public education and the visitor-first interaction model.
