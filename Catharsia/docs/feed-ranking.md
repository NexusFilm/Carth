# Catharsia feed ranking

## Product goal

Help people find thoughtful, useful therapist perspectives and make room for supportive conversation. The feed should optimize for relevance and perceived helpfulness, not session length or compulsive return.

## Current implementation

Explore is chronological (`created_at`, newest first). The app does not currently have a personalized ranking model or the per-viewer feedback data needed to train one. Likes and comments create activity notifications; they are not currently ranking inputs.

## Ranking principles for the next iteration

- Keep a chronological feed option available and make the current sort easy to understand.
- Use explicit preferences first: followed topics, saved posts, and “show me less like this.”
- Treat comments as a sign of meaningful conversation, not a popularity contest. Do not reward raw comment volume or controversial replies.
- Use saves and direct helpfulness feedback as stronger positive signals than likes or shares.
- Balance freshness, topic relevance, and creator diversity so one therapist or topic cannot dominate a session.
- Avoid watch-time maximization, streak pressure, infinite novelty loops, outrage signals, and sensitive mental-health profiling.
- Explain why a post appears and let people reset or adjust their feed preferences.
- Measure success with user-reported usefulness, helpful conversation, and content diversity; monitor negative feedback and report rates as guardrails.

## Safe rollout

Before personalization, add explicit per-user preference events and a “show less” control, document retention, and test ranking with synthetic data. Start with a deterministic, auditable score using freshness, explicit topic affinity, helpfulness feedback, and diversity constraints. Keep ranking server-side and tenant-scoped. Do not ship a behavioral model until the needed consent, controls, and success measures exist.
