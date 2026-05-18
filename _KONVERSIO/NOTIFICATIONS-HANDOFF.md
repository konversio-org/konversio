# Notifications — Handoff

Design doc + state-of-play for the dashboard tab notification system.
Companion to `_KONVERSIO/HANDOFF.md`; this is the deep-dive specifically
on the favicon-badge / audio-alert / unread-count signal chain and where
Konversio diverges from upstream.

---

## Mental model

What an agent should experience:

1. **Agent tab in background, customer sends a message** → red dot on the
   browser tab favicon (peripheral signal that draws the eye)
2. **Agent clicks back to the tab** → dot clears (they've seen it)
3. **Agent tab in foreground, viewing the conversation** → no dot (no
   point alerting someone who's looking)
4. **Agent tab in foreground, viewing a *different* conversation** → red
   dot still fires (they need to know another conv has activity)
5. **Audio "ding"** → orthogonal, opt-in via profile settings

That's the Slack / Intercom / Front pattern. It's what the user expects.
It's what we want Konversio to do.

---

## What upstream Chatwoot actually does

The flow lives in
`app/javascript/dashboard/helper/AudioAlerts/DashboardAudioNotificationHelper.js`
and `app/javascript/dashboard/helper/AudioAlerts/faviconHelper.js`.

When ActionCable broadcasts `message.created`:

1. `DashboardAudioNotificationHelper.onNewMessage(message)` runs
2. Early-return guards: permission check, `isMessageFromPendingConversation`
   (suppresses bot-handled convos), `isMessageFromCurrentUser` (suppresses
   self-sends)
3. **`shouldNotifyOnMessage(message)` audio-type filter** — if
   `audioAlertType.includes('none')`, returns false and the function bails
4. If still alive: message-type guard (must be incoming or private)
5. Visibility guard: if the window is visible AND the user is on the
   relevant conversation OR `playAlertOnlyWhenHidden` is true, bail
6. Finally: `this.playAudioAlert()` and `showBadgeOnFavicon()` run side
   by side

`showBadgeOnFavicon()` swaps `<link class="favicon">` href to
`/favicon-badge-{size}.png`. `initFaviconSwitcher()` registers a
`visibilitychange` listener that reverts the href when the tab becomes
visible again.

### The default-driven gap

| Setting | Default | Effect |
|---|---|---|
| `audioAlertType` | `['none']` | `shouldNotifyOnMessage` returns false → **no favicon, no audio, ever** |
| `alwaysPlayAudioAlert` | `false` | `playAlertOnlyWhenHidden` → only when hidden (this would be fine if step 3 didn't kill the badge first) |

A fresh user with empty `ui_settings: {}` gets the `['none']` default
and **never sees a favicon badge** until they go into Settings → Profile
→ Audio notifications and pick an alert type. The favicon path is gated
*behind* the audio opt-in.

### Verified upstream (May 2026)

A spider-agent compared upstream `develop` to our v4.13.0 fork point and
confirmed: the logic is byte-identical, the `'none'` default hasn't
moved, and there is no parallel favicon-only code path. `showBadgeOnFavicon`
is called from exactly three sites upstream (`onNewMessage`,
`executeRecurringNotification`, plus Konversio's new `onAssigneeChanged`),
all of them downstream of the audio gate.

### Industry comparison

| Product | Default favicon-when-hidden | Default title-prefix `(N)` | Audio |
|---|---|---|---|
| Slack | yes | yes | opt-in |
| Intercom Inbox | yes | yes | opt-in |
| Front | yes | yes | opt-in |
| **Chatwoot** | **no** | **no** | opt-in (and gates the favicon too) |

Chatwoot is the outlier. Treating its current behavior as "the upstream
default we should mirror" is a mistake — upstream just hasn't fixed this.

---

## Konversio's design

**Decouple the favicon path from the audio path.** Audio remains opt-in
behind `audioAlertType`. Favicon is governed only by tab visibility +
the safety guards that already exist (permission, pending, self-send,
message-type).

Concretely, in `onNewMessage`:

```js
// ... permission / pending / self-sent / message-type guards ...

// Visual peripheral signal — fires for any valid incoming/private
// message when the tab isn't currently visible.
if (!WindowVisibilityHelper.isWindowVisible()) {
  showBadgeOnFavicon();
}

// Audio remains gated on audioAlertType + shouldPlayAlert (existing)
if (!this.shouldNotifyOnMessage(message)) return;
// ... existing audio path unchanged ...
```

And the same split for `onAssigneeChanged` (the bot-handoff hook
described in the next section).

### Resulting behavior

| Scenario | Favicon | Audio |
|---|---|---|
| Customer msg, tab hidden | badge fires | only if user enabled audio for this type |
| Customer msg, tab visible, viewing same conv | no badge (you're there) | no audio (existing guard) |
| Customer msg, tab visible, viewing different conv | badge fires | only if `alwaysPlayAudioAlert` is true |
| Agent returns to tab | badge clears (existing `initFaviconSwitcher`) | n/a |
| Bot replying during pending phase | no badge (existing `isMessageFromPendingConversation` guard) | no audio |
| Assignment lands (bot→human) | badge fires if tab hidden | optional via existing alert types |

Same `isMessageFromPendingConversation` guard kept in place — agents
don't get spammed for every customer↔bot turn during the pending phase.
Once status flips to `open` (bot has handed off), badges resume.

---

## Bot→human handoff specifically

The `onAssigneeChanged` hook (commit `2d7efa65b`) was added because:

1. Autopilot sets the conversation to `status: pending` while handling it
2. The customer's "I want to talk to a human" message arrives, but
   `isMessageFromPendingConversation` suppresses any alert for it
3. Default Policy then auto-assigns the conversation to an agent
4. Without a hook on `assignee.changed`, the assigned agent gets no
   peripheral signal — they have to spot the new entry in their Mine
   inbox themselves

The hook fires on the ActionCable `assignee.changed` event when the new
assignee is the current user. Verified end-to-end on 2026-05-18:

- WebSocket frame captured with `assignee.changed`, `assignee_id: 1`
- 2 ms later, all three `<link class="favicon">` href attributes mutated
  to the badge variants
- After `visibilitychange` → `visible`, `initFaviconSwitcher` reverted
  them

### Open: `assignee.changed` fires twice for one handoff

In the verification run, two `assignee.changed` events arrived 325 ms
apart for the same conversation, both with `assignee_id: 1`. Suspected
race between Autopilot's own assignment path and Chatwoot's standard
auto-assignment policy. Idempotent on the favicon (same href set
twice = no visual effect) but could double-play audio. Not chased this
session.

---

## Current state of play

| Commit | What it does | Status |
|---|---|---|
| `2d7efa65b` | `onAssigneeChanged` hook (favicon + audio for assignments) | landed, verified |
| `8966ec514` | Gate `onAssigneeChanged` on `shouldPlayAlert` (mirror upstream `onNewMessage`) | landed, verified |
| `d6cf8b347` | Decouple favicon from `audioAlertType` per the design above | landed, verified |

Verified end-to-end with John on empty `ui_settings: {}` (audioAlertType
defaulting to `'none'`):
- Forced `document.visibilityState = 'hidden'`, then `INSERT INTO messages`
  on an open conversation
- Captured `message.created` event arriving with `message_type: 0`
  (incoming)
- 3 ms later all three `<link class="favicon">` href attributes mutated
  to `/favicon-badge-{size}.png`
- Audio remained silent because John's profile still has audio alerts at
  `'none'` — exactly the intended separation

---

## Defaults & migration notes

### Server-side default

`db/schema.rb` defines `users.ui_settings jsonb default: {}`. New users
start with empty `ui_settings`. `scriptHelpers.js:30` falls back to
`audioAlertType: audioAlertType || 'none'`. There is no current
migration that backfills `'mine'` or `'all'` for new accounts.

### If we want to ship the decoupling

The minimal code path:

1. Edit `DashboardAudioNotificationHelper.js` to move
   `showBadgeOnFavicon()` ahead of `shouldNotifyOnMessage`, gated on
   `WindowVisibilityHelper.isWindowVisible()` only
2. Mirror the same split inside `onAssigneeChanged`
3. No DB migration needed
4. No profile-settings UI changes needed
5. Existing `initFaviconSwitcher` keeps clearing on visibilitychange

That's it. One file, two methods, ~10 lines.

### What we are NOT doing (yet)

- **No `(N) Conversations` title-prefix.** Industry standard and would
  pair well with the favicon, but separate scope. Worth considering as a
  follow-up since the data (unread count) is already in Vuex.
- **No change to the audio path.** Audio stays opt-in via existing
  profile settings.
- **No change to `isMessageFromPendingConversation`.** Still want to
  suppress alerts during bot phase.

---

## Open questions / future work

1. **Should `(N) Conversations` title prefix ship together with the
   favicon decoupling?** Same surface, same idea. Decide before
   committing the decoupling so it can land as one cohesive change.

2. **Should we backfill `ui_settings.notification_settings = 'mine'`
   for existing users?** With the decoupling, this is no longer
   required for the favicon to work — but it would also turn audio on
   for everyone, which is more invasive. Probably skip.

3. **Double-fire of `assignee.changed`** — separate investigation. Find
   the two dispatch paths (likely Autopilot's own assigner + Chatwoot's
   standard auto-assignment policy) and pick one.

4. **Browser favicon repaint stickiness** — observed during testing
   that Chrome sometimes doesn't visually repaint the tab icon
   immediately after a `.href` mutation, even though the DOM updated.
   Cosmetic; doesn't affect the `<link>` state. If users complain,
   look at cache-busting query params or full link-node replacement —
   but only as a last resort (we wasted hours doing this during the
   Lit-dedupe session; see `_KONVERSIO/POSTMORTEM-LIT-DEDUPE.md`).

5. **Mobile / push notifications** — totally separate concern; the
   browser-tab favicon is a desktop signal. Mobile push lives in the
   `Notification` model and FCM/APNS pipeline, not in this helper.

---

## How to pick this up in a future session

1. Read this file end-to-end.
2. Read `_KONVERSIO/POSTMORTEM-LIT-DEDUPE.md` for the rules around
   touching Vite / Lit / build infrastructure (we burned hours; don't
   repeat).
3. Implement the Option-B decoupling described above. ~10 lines, one
   file. No build-infra changes needed.
4. Test with: bot handoff via widget + customer follow-up message,
   with the dashboard tab in another window. Verify the favicon
   badges, then clears when you focus back.
5. Decide on the `(N)` title prefix separately.
