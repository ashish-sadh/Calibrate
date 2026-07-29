# Design: Friends Hub Redesign — social polish + coach workspace

> References: Issue #1156
> Builds on `friends-trainer-sharing.md` (the social layer's living design).
> Operator ask 2026-07-29: "friend tab is a little lame. Take inspiration from
> Threads, Insta to make it look neat, and it needs to be coach oriented too
> where coaches can see stats etc. and build and coach their clients."

## Problem

`SharingView` (667 lines) works but reads like a settings page, not a social
surface: seven stacked ALL-CAPS sections (YOUR COACHES / YOUR CLIENTS /
FRIENDS / FRIEND ACTIVITY / ADD FRIENDS / FRIEND REQUESTS / SHARED WITH YOU)
with uniform caption-weight rows. Nothing establishes identity (your own
profile is a "Signed in" caption), activity is a text list, and a coach who
opens the tab sees the same flat list a friend does — there is no coaching
surface at all beyond tapping a client into `ClientSessionDetailView` (a raw
set list).

What Threads/Instagram get right that we can borrow without becoming a social
network: a clear identity header, avatars everywhere, one primary feed,
requests tucked behind a badge, and search that feels like search rather than
a form section.

## Proposal

Restructure the Friends hub into three focused surfaces, and give coaches a
real client workspace. No new backend primitives — everything below reads
existing tables (`friendships`, `profiles`, `live_workouts`, `client_briefings`,
`shared_templates`); the only additive change is an optional `avatar_color`
(or emoji) profile field if we want richer avatars later.

**Out of scope:** public profiles, follower counts, comments/likes, any
discovery beyond exact-username search, media uploads. This is a private
1:1 layer with better clothes on, not a feed product.

## UX Flow

### 1. Hub (default tab view)
- **Identity header** — large avatar (initial on gradient, as today but 56pt),
  @username + display name, small edit affordance. Anchors the screen the way
  Threads' profile row does.
- **Requests pill** — bell/badge in the header row ("2 requests") opening the
  requests list. Requests leave the main scroll (today they're a full section
  at the bottom where they're missed).
- **Activity feed** — the main scroll body: friend finished-workout cards
  (avatar, name, workout, relative time, exercise timeline), newest first.
  Cards, not caption rows. Tap → session detail. Empty state sells the
  feature ("When friends finish workouts, they show up here").
- **People strip** — horizontally scrolling avatar circles (coaches first,
  badge on coach avatars) above the feed; tap → person detail. Replaces the
  three stacked list sections for the common case; a "See all" pushes the
  full grouped list.
- **Search** — a persistent search field at top (as Threads' search tab does)
  that searches the directory; result rows keep the Add friend / Add coach
  actions.

### 2. Person detail (friend or coach)
- Header: avatar, name, relationship badge (FRIEND / COACH / CLIENT), chat
  button, remove.
- Friend: their recent shared workouts.
- Your coach: what you're sharing with them (briefing level, from
  `CoachSharingCard`) + templates they've assigned you.

### 3. Coach workspace (only when you HAVE clients)
The coach-oriented ask. A "Clients" card section at the top of the hub for
users with `.client` connections:
- **Client cards** — one per client: avatar, name, last workout ("2d ago —
  P5 Day 1"), a 7-day activity sparkline (sessions/week), and the briefing
  headline metrics the client chose to share (weight trend, adherence) from
  `client_briefings`.
- **Client detail** — full stats page: workout history list (existing
  `ClientSessionDetailView` data), briefing metrics/notes, and two actions:
  **Assign template** (existing `shareTemplate` flow, template picker) and
  **Chat**. "Build and coach" = assign + review + talk, all one screen.
- Nothing new crosses the wire: the coach sees exactly what the client's
  briefing level + shared workouts already grant. The redesign is
  presentation, not new access.

## Technical Approach

- `SharedUI/SharingView.swift` splits into `FriendsHubView` (header, search,
  people strip, feed), `PersonDetailView`, `CoachClientsSection` +
  `ClientDetailView`, `FriendRequestsView`. All SharedUI (both platforms);
  Skip Fuse constraints apply (no private @State, one TextField per scope,
  no stacked presentation modifiers — push, don't sheet).
- Feed = existing `friendActivity()` (`live_workouts` fetch) rendered as
  cards; sparkline = counts bucketed by day from the same rows — computed
  client-side in DriftCore (`Sharing/`), Tier-0 testable.
- Reuses `FriendSharePicker` row/avatar/badge idiom introduced 2026-07-29 so
  the share sheets and the hub read as one family.
- No migration required. Optional later: `profiles.avatar_color` (additive
  column, default null) for user-picked avatar colors.
- Phasing (each a shippable slice):
  1. Hub restructure — identity header, requests pill, people strip, feed
     cards (pure re-layout of existing data; biggest perceived win).
  2. Coach workspace — client cards + client detail + assign-from-detail.
  3. Person detail polish + avatar color.

## Risks / notes

- LAUNCH HARDENING is the active focus; this is operator-directed design
  work. Implementation slices should ride behind stability work unless the
  operator pulls them forward.
- The hub currently mixes bootstrap/signup states (`PICK A USERNAME`) with
  the signed-in hub in one view; the split must keep the signup path intact.
- Coach sparklines must be goal-aware-neutral (activity, not deficit/surplus)
  — green/red semantics don't apply to "did they train".
