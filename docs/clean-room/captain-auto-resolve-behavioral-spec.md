# CAPTAIN AUTO-RESOLVE — BEHAVIORAL SPEC (clean-room safe)

> **Provenance / wall note.** The analyst (dirty room) read the **public upstream**
> `chatwoot/chatwoot` source to understand the mechanism, then re-expressed only the
> observable behavior here. This document deliberately carries **zero protected
> expression**: no class/module/method/table/column/file/job/feature-flag names, no
> source structure ("which thing calls which"), and no copied string literals
> (internal note text, reason labels, message keys, etc. are described by effect
> only). It is safe to hand to a clean-room engineer who must never see the source.
> The prohibition on resurrecting *this repo's* deleted enterprise history was not
> touched — only the public upstream tree was read.

## 0. Big picture — there are TWO independent auto-resolution systems plus one in-flight action

A clean-room engineer must not collapse these into one feature; they target
different conversation states, use different timers, and post different messages.

- **System A — account-wide idle resolution.** A general "tidy up stale threads"
  sweep that closes **open** conversations after a configurable idle period. Not
  AI-specific; applies to ordinary human/agent conversations.
- **System B — AI-assistant pending-conversation resolution.** A sweep specific to
  inboxes handled by the AI assistant. It acts on conversations still in the
  **bot-handling (pending)** state, on a **fixed short timer**, and decides between
  *resolving* and *handing off to a human*.
- **Action C — in-conversation agentic resolve.** While the assistant is actively
  replying, it can choose to close the conversation immediately by invoking a
  "resolve" capability with a stated reason.

The sections below answer the eight behavioral questions across all three.

---

## 1. Triggers

- **System A (idle):** purely time-based. An open conversation that has had no
  activity for longer than the account's configured idle window becomes eligible.
- **System B (AI pending):** time-based eligibility (a fixed short idle window in
  the bot-handling state), followed — in its smarter mode — by an **AI judgment**
  of whether the customer's issue is actually finished. Eligibility opens the door;
  the AI decides resolve-vs-handoff.
- **Action C (agentic):** the assistant decides mid-conversation that the issue is
  addressed and closes it on the spot, with no timer involved.

A hand-off to a human is a **distinct outcome**, not a resolution (see §3/§7). In
System B's smart mode, "not finished" produces a hand-off, not a close.

## 2. Timing

- **System A idle window:** configurable, **administrator-facing in minutes / hours
  / days** but stored and evaluated internally in **minutes**. Bounded: a floor of
  **10 minutes** and a ceiling on the order of **~1000 days**. There is no implicit
  default magnitude — the feature does nothing until a value is set (a zero/blank
  value disables it). The countdown is **inactivity since last activity** on the
  conversation; any new activity resets it.
- **System B idle window:** a **fixed ~1 hour** of inactivity in the bot-handling
  state. This is **not configurable** — it is a hard internal constant. Measured as
  time since last activity on the conversation.
- **Action C:** immediate; no timer.

## 3. State eligibility & transitions

- **System A** only ever touches conversations in the **open** state. It closes
  open → resolved. It does not promote other states first.
- **System B** only touches conversations in the **bot-handling (pending)** state —
  i.e. conversations the AI is currently fronting. Its two possible transitions:
  - bot-handling → **resolved** (issue judged complete, or in time-based mode
    unconditionally after the timer), **or**
  - bot-handling → **handed off to a human** (issue judged unfinished). The
    hand-off transition is explicitly **not** a resolution and preserves the
    "waiting on someone" timestamp so downstream waiting logic stays correct.
- **Action C** closes whatever the active conversation is, refusing if it is already
  resolved.

## 4. Modes / decision branch (System B)

System B runs in one of **three modes**, selected per account:

1. **Disabled** — the AI never auto-resolves or auto-hands-off; the sweep is skipped
   for that account. An explicit disable preference forces this.
2. **Time-based (legacy)** — after the fixed idle window, the conversation is simply
   resolved (closing message posted, then closed). No AI judgment.
3. **Evaluated (smart)** — after the fixed idle window, the full conversation
   transcript is sent to an LLM that returns a structured verdict: **"is the
   customer's need complete?"** plus a short free-text reason. Then:
   - **complete →** resolve (see §5).
   - **not complete →** hand off to a human (see §5/§7).

Mode selection precedence (described by effect): an explicit stored mode wins; else
an explicit "disable" preference means disabled; else, if the account has the
agentic-task capability enabled, the mode is **evaluated**, otherwise **time-based**.

Because the LLM evaluation takes real wall-clock time, after it returns the system
**re-checks** that the conversation is *still* in the bot-handling state and *still*
past the idle cutoff before acting; if the customer re-engaged in the meantime, it
is left alone (see §7).

The completeness evaluation runs on the **installation/system-level LLM credential**
(not the customer's), and is **deliberately excluded from any customer usage
metering** — it's treated as internal housekeeping, not a billable AI action.

## 5. Messages posted

- **System A on close:** optionally posts a single **account-level** closing message
  (admin-configured copy); if that copy is blank, the conversation closes silently.
  Posting respects the channel's **messaging window** — if the channel can't be
  messaged at that moment, the closing message is **not sent** and instead an
  internal activity note records that it was suppressed for that reason. It may also
  optionally **apply a label** to the closed conversation.
- **System B on resolve:** posts a customer-facing **resolution message** taken from
  the **assistant's own configuration**, falling back to a built-in default if the
  assistant has none set. It additionally records an **internal private note**
  (agent-only) summarizing why it resolved.
- **System B on hand-off:** posts the assistant's configured **hand-off message**
  (skipped entirely if that copy is unset — no fallback), records an **internal
  private note** summarizing why it handed off, and, where applicable, also posts an
  **out-of-office style message** — except for conversations that originated from an
  outbound campaign, which never receive the out-of-office message.
- Reason text in the AI's verdict is surfaced only in the **internal private notes**,
  never to the customer.

## 6. Toggles / knobs (described by effect, not name)

**System A:**
- Idle duration + unit (minutes/hours/days; floor 10 min) — also the on/off switch
  (blank/zero = off).
- Closing-message-on-resolve copy (account-level; blank = silent).
- Apply-a-label-on-resolve (optional).
- **"Skip conversations currently waiting on the customer"** — when on, the sweep
  excludes conversations flagged as awaiting the customer (a non-null "waiting since"
  marker); when off, all idle open conversations are eligible.

**System B:**
- Three-way mode selector: disabled / time-based / evaluated (§4), including an
  explicit hard-disable preference.
- Per-assistant resolution-message copy (with default fallback).
- Per-assistant hand-off-message copy (no fallback; blank = no message).
- Gated by an account-level agentic-task capability that also flips the default mode
  from time-based to evaluated.

**Action C:** governed by the same account-level disable preference — if auto-resolve
is disabled for the account, the in-conversation resolve action refuses to run.

## 7. Exclusions / edge cases

- **System B skips email-type inboxes entirely.**
- **System B skips accounts** whose AI auto-resolve is disabled (both at scheduling
  time and again defensively at execution time).
- **Customer re-engagement during the (slow) AI evaluation:** if the conversation
  leaves the bot-handling state or its activity timer resets while the LLM is
  thinking, the verdict is discarded and no action is taken. A disappeared/deleted
  conversation is likewise skipped safely.
- **System A excludes conversations with no associated contact** (e.g. orphaned by a
  pending contact cleanup) to avoid acting on half-deleted records, and optionally
  excludes "waiting on customer" conversations per the §6 toggle.
- **Batching:** both sweeps cap how many conversations they touch per run (a bulk
  action limit), so a large backlog drains over multiple cycles rather than all at
  once.
- **Already-resolved guard (Action C):** the in-conversation resolve refuses if the
  conversation is already resolved.

## 8. Scheduling cadence (observable latency)

- A periodic scheduler fans out the work: for **System A** it enqueues a per-account
  sweep for every account that has idle-resolution configured; for **System B** it
  enqueues a per-inbox sweep for every AI-handled (non-email) inbox on a
  non-disabled account. The two are dispatched together on the same cadence.
- Observable consequence: a conversation is resolved (or handed off) **at or shortly
  after** its idle threshold expires — never exactly on the tick. Plan for latency of
  **"idle threshold + up to one scheduler interval."** For System B that means a
  conversation typically closes/hands-off roughly an hour-plus after the customer
  goes quiet; for System A it closes roughly the configured window plus one cycle.

---

## Corrections vs. the earlier docs-only draft

Reading the real source changed several claims that the public documentation alone
got wrong or vague:

1. There are **two** auto-resolve systems, not one. The configurable minutes/hours/
   days knob belongs to the general **open**-conversation sweep (System A); the
   AI-assistant sweep (System B) runs on a **fixed ~1 hour** timer that is **not**
   configurable.
2. System B targets **bot-handling (pending)** conversations, not open ones.
3. The "nudge / anything-else" notion was wrong. The real pre-close branch is
   **resolve vs. hand-off-to-human**, driven (in smart mode) by an LLM completeness
   verdict on the transcript.
4. Resolution/hand-off copy for the AI system is **per-assistant**, not per-account;
   the per-account closing message belongs to System A.
5. The AI completeness evaluation is unmetered and runs on the system LLM credential.

## Sources read (public upstream)

- The general account-wide idle-resolution sweep job and its per-account scheduler.
- The account settings governing idle duration (minutes; floor 10), closing message,
  label-on-resolve, and the skip-waiting toggle, plus the open/waiting conversation
  scopes.
- The closing-message poster, including its messaging-window suppression behavior.
- The enterprise scheduler extension that additionally fans out per AI-handled inbox.
- The AI inbox pending-resolution job (the three modes, the fixed cutoff, the
  resolve-vs-handoff branch, private notes, out-of-office handling, re-check guard).
- The AI completeness-evaluation service (system credential, no metering, transcript
  in / {complete, reason} out).
- The in-conversation agentic "resolve" capability and its guards.
