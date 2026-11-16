# Catharsia Design System

## Direction

Immersive vertical Explore feed with familiar social interactions and an abstract paired-lobe brain identity. The mark keeps an open center and suggests a hopeful path through therapist voices, group opportunities, and practice events. A single therapist post owns the viewport; the therapist's name and credentials stay legible and close to the content.

## Appearance

Light appearance only. Use warm white and soft lavender for surfaces, dark ink text, saturated violet for primary actions, coral for likes, and occasional aqua or amber accents. Maintain accessible contrast and never rely on color alone to convey a role or state.

## Layout and navigation

- Keep first-run onboarding to one quiet visual axis: mark, short hopeful message, a concise explanation, a browse-without-sign-in assurance, and one “Start exploring” action.
- Keep the brain Explore identity at the top, the current post in the center, and Like, Comment, Save, and Share actions beside it. Put owner-only Delete beside Report in the post menu.
- Keep Explore, Communities, Saved, and Profile available through compact bottom navigation.
- Put a concise value statement at the start of Explore, Communities, and host tools. Treat it as section orientation, not a separate marketing landing page.
- Keep the public community directory open to browse. On a group page, show its purpose and expectations before sign-in; ask for sign-in only when joining or posting.
- On mobile, keep group discovery, conversations, and therapist controls inside the Communities flow. On desktop, give therapist hosts an overview of their groups, active membership, discussion count, editable details, shared resources, roster controls, and a reusable QR/share card.
- Keep community conversations private to active members and the therapist host. Public pages show only the community's public description and shared expectations.
- Use the abstract Catharsia mark in the app icon, Explore tab, and brand moments. Keep the silhouette recognizable at small sizes without adding anatomical folds.
- Show an optional, tappable external-link action on posts. Make a verified therapist's public profile reachable from their author row, with a Posts section beside a Bento Profile section containing up to six labeled event, booking, group, social, or resource links.
- Show live like, comment, save, and share totals beside post actions. Keep these counts aggregate and never reveal who privately saved a post.
- Render source photos at their original colors without tint or overlay gradients. Show a real image loading state with retry rather than substituting branded artwork when a photo fails to load.
- Let verified therapists edit Bento links from Profile. Keep the composer focused on the caption, with link and library actions in a compact panel that opens directly above the Plus control.
- Keep Profile focused on identity and useful actions. Group admin, help/privacy, and account actions into compact sections; place account deletion under Account as a destructive action without primary-action weight.
- Show the camera composer only to accounts authorized by Supabase.
- Keep the publisher composer inline above the tab bar, group Camera and Plus before the caption field, and place Send inside the field at its trailing edge. Keep the empty-field prompt stable and short. Camera opens capture directly, defaulting to video with a 60-second cap, an optional on-screen teleprompter, photo mode, and camera switching; Plus opens the action panel for links and media. Limit a post to five media items total, show confirmed Discard draft only while a draft exists, and let its author edit or delete a published post from the post menu.
- Provide honest loading, empty, signed-out, error, and success states. Zero live posts must remain an empty feed, never a fabricated demo.
- Use native SwiftUI navigation, Dynamic Type, VoiceOver labels, 44-point minimum action targets, and Reduce Motion support.
- Keep keyboard dismissal close to the composer as a compact “Hide keyboard” control. Let vertical feed scrolling dismiss it interactively.

## Interaction and motion

Prefer direct manipulation: swipe between real posts and carousel media, tap to engage, and return to Explore without losing context. Give likes, saves, comments, publishing, and manual refresh brief feedback. UI motion stays under 400 ms and never loops; in-feed video may autoplay muted only while visible, then pauses offscreen.
