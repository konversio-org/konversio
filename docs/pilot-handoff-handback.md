# Pilot Handoff and Handback

Handoff should not mean "Pilot stops forever." It should mean the conversation is entering a human-support path. Whether Pilot stays active, pauses, or later resumes should be policy-driven.

> [!IMPORTANT]
> **ALGY Preamble (The "Limboland" Issue & Solutions):**
> **The Issue:** When a conversation attempts a handoff to a human, it currently transitions the core status to `open`. This disables Autopilot inference. If human agents are offline or do not respond immediately, the customer is left in "limboland" — the bot remains silent, and the customer receives no help.
>
> **Suggested Solution Options based on Industry Research:**
> 1. **Co-Active Warm Bot (Tidio Lyro-style):** Keep the conversation in `open` status (so agents see it) but allow the bot to remain active and responding to customer queries under specific metadata guards (e.g. `handoff_requested`), until a human agent explicitly assigns the conversation or sends a message.
> 2. **Availability-Aware Pre-Routing (Ada/Lyro-style):** Check agent presence (`OnlineStatusTracker`) and working hours before handoff. If offline, run a fallback behavior immediately (e.g., capture email/ticket, keep the chat active) instead of opening a dead channel.
> 3. **Queue Timeout SLA Job (Zendesk/LivePerson-style):** Schedule a background task (`Pilot::HandoffTimeoutJob`) at the moment of handoff. If no agent activity occurs within $X$ minutes, transition core status back to `pending`, alert the agent timeline via an activity message, and post an apology/fallback message from the bot.
>
> We recommend implementing a combination of **Option 2 (Pre-Handoff Availability Check)** and **Option 3 (Sidekiq-based Queue Timeout Job)** as the most lightweight, robust solution.

The key product distinction is simple: a customer asking for a human is not the same as a human actually taking over.


## Current Problem

The current failure mode is dead air:

1. Customer asks for a human.
2. Pilot sends the configured handoff message.
3. `Conversation#bot_handoff!` moves the conversation to `open`.
4. `PilotAutopilotListener#message_created` stops enqueueing inference because it only runs while the conversation is `pending`.
5. If no agent replies, Pilot stays silent and the customer waits with no recovery path.

The relevant code paths are:

- `app/jobs/pilot/autopilot_inference_job.rb`: `process_handover` calls `conversation.bot_handoff!`.
- `app/models/conversation.rb`: `bot_handoff!` sets `waiting_since`, opens the conversation, and dispatches `CONVERSATION_BOT_HANDOFF`.
- `app/listeners/pilot_autopilot_listener.rb`: `message_created` returns unless `message.conversation&.pending?`.

That behavior assumes `open` means a human has taken over. For Pilot handoff, that assumption is too early. `open` should mean human control, not merely human requested.

## Product Rule

Pilot should stop responding only when a human has actually taken ownership, not merely when human help was requested.

That distinction is the difference between a smooth handoff and dead air.

> [!NOTE]
> **ALGY:** To implement this without breaking Chatwoot's core queue architecture, we should transition the conversation to `open` (so it immediately enters the agents' active queue), but update `PilotAutopilotListener` to allow bot responses on `open` conversations *if* they are in `keep_pilot_warm` mode, have no `assignee_id`, and have received zero human outgoing messages since the handoff. As soon as an agent takes ownership (assigns themselves or sends a message), the bot automatically silences itself.

Handoff should have two separate moments:

- `handoff_requested`: Pilot or the customer requested human help.
- `human_active`: an agent replied or explicitly took over.

This allows Pilot to stay warm while routing happens, and prevents the silent gap when nobody responds.

## State Model

Do not add new values to `Conversation#status`. Core status is already constrained to `open`, `resolved`, `pending`, and `snoozed`, and those values drive existing inbox filters and assignment behavior.

Use existing core statuses plus Pilot-specific metadata:

| Pilot state | Core status | Meaning |
|---|---|---|
| `pilot_active` | `pending` | Pilot is responding normally. |
| `handoff_requested` | `pending` by default | Human help was requested, but no human has taken over. Pilot may keep responding depending on policy. |
| `human_active` | `open` | An agent replied or explicitly took over. Pilot should not respond automatically. |
| `pilot_resumed` | `pending` | Pilot resumed after a timeout, failed route, or explicit handback. |
| `async_followup` | `snoozed` only when explicitly scheduled | The conversation is waiting for a later callback, ticket follow-up, or scheduled reminder. |

Store the Pilot state in conversation metadata first, not in the status enum. Prefer a dedicated nested key in `additional_attributes` to avoid colliding with customer-defined custom attributes:

```json
{
  "pilot_handoff": {
    "state": "handoff_requested",
    "requested_at": "2026-05-27T15:00:00Z",
    "reason": "customer_request",
    "mode": "keep_pilot_warm",
    "timeout_at": "2026-05-27T15:05:00Z",
    "resume_count": 0
  }
}
```

If the state later needs first-class filtering or reporting, promote it to a real column or a dedicated association. Do not overload the main conversation status for Pilot-only workflow detail.

## Handoff Policies

Each Pilot Assistant can start with account-wide defaults in `pilot_assistants.config`. If inbox-specific behavior becomes important, `pilot_inboxes` can override the assistant defaults later.

When agents are available:

- `pause_pilot`: Pilot sends a handoff message, requests human help, and waits.
- `keep_pilot_warm`: Pilot tells the customer a teammate has been notified, but continues helping until a human replies.
- `ask_customer`: Pilot asks whether the customer wants to keep troubleshooting while waiting.

When no inbox agents are available:

- `keep_pilot_active`: Pilot keeps answering.
- `capture_contact`: Pilot asks for email, callback preference, or another async contact path.
- `create_ticket`: create or mark an async follow-up.
- `resolve_with_message`: only for low-touch setups where no follow-up is expected.

When nobody replies after N minutes:

- `resume_pilot`: Pilot sends a short "I'm still here" message and continues.
- `capture_ticket`: create or mark async follow-up.
- `escalate_team`: notify another team or priority route.

Availability should be inbox-scoped. Use existing inbox membership and presence behavior rather than raw account-wide presence. `inbox.available_agents` is the right shape because it filters online users through inbox membership.

## Recommended MVP

The MVP focuses strictly on the co-active warm bot and the timeout recovery job:

1. **`keep_pilot_warm`**: When human help is requested, transition the core conversation status to `open` (so agents see it and get notified), set the Pilot metadata to `state: 'handoff_requested'` and `requested_at: Time.current`, and allow the bot to continue responding in parallel.
2. **`handoff_timeout_minutes`**: Schedule `Pilot::HandoffTimeoutJob` to run after configured timeout minutes (defaulting to 5). If no human replies or assigns in that window, transition status back to `pending` and post the configured fallback message.

This resolves the "limboland" (dead air) customer experience without introducing any agent-presence branching or custom frontend UI changes.


> [!IMPORTANT]
> **ALGY:** In Chatwoot core, conversations with a `pending` status do not trigger agent push notifications or show up in the main active/unassigned queues. Keeping the conversation `pending` during `keep_pilot_warm` would hide it from agents who do not actively check the "Bot" filter. Therefore, we should transition the conversation to `open` status immediately during handoff (triggering notifications and queue presence) but use the Pilot metadata state `handoff_requested` to permit the bot to continue responding until a human takes ownership.
>
> **Preferred Parallel Chat Option:** We select **Option 1 (Conversational Path)** as the preferred implementation. The bot will invite the customer to continue asking questions via text (e.g., *"I've notified the team. While you wait, feel free to keep asking me questions, or just wait for them to reply."*). If the customer types a question, the bot responds in parallel. This avoids frontend widget modifications and ensures a natural conversational flow.



## Timeout Job

Use a scheduled Sidekiq job rather than polling:

```ruby
Pilot::HandoffTimeoutJob.perform_in(
  assistant.handoff_timeout_minutes.minutes,
  conversation.id,
  handoff_requested_at.iso8601
)
```

When the job runs, it should no-op unless all of these are true:

- Conversation still belongs to the same account and inbox.
- Pilot metadata still has `state: handoff_requested`.
- The `requested_at` value still matches the job argument, making stale jobs harmless.
- No human outgoing message exists after `requested_at`.
- Conversation has not been resolved.

> [!NOTE]
> **ALGY:** To verify that no human outgoing message has been sent since the handoff, we can query:
> `conversation.messages.outgoing.where.not(sender_type: 'Pilot::Assistant').where('created_at >= ?', requested_at).empty?`


Do not require the conversation to be unassigned. Assignment is not the same as response. A conversation can be assigned and still ignored.

For `keep_pilot_warm`, the timeout job usually does not need to switch `open` back to `pending`, because the conversation should have stayed `pending` until human takeover. It should update Pilot metadata, optionally increment `resume_count`, and send the configured fallback message.

For legacy or `pause_pilot` behavior where handoff already moved the conversation to `open`, the timeout job may move it back to `pending` only if no human reply or explicit takeover happened.

## Human Takeover

Pilot should enter `human_active` when either:

- an agent sends an outgoing public reply, or
- an agent clicks an explicit "Take over" action.

At that point:

- set core status to `open`;
- set Pilot metadata state to `human_active`;
- store `human_takeover_at`;
- stop automatic Pilot inference for new customer messages.

This avoids bot/human collisions while keeping the initial handoff recoverable.

## Handback

Handback is the reverse path: a human returns control to Pilot.

Useful cases:

- The agent answered the sensitive or escalated part.
- The customer has follow-up questions Pilot can handle.
- The agent wants Pilot to close, summarize, collect CSAT, or continue troubleshooting.
- The conversation was escalated by mistake.

Handback should be explicit in the MVP. Automatic handback after a human reply can feel surprising and can cause bot/human collisions.

Recommended flow:

1. Agent clicks `Hand back to Pilot`.
2. Agent optionally adds an instruction, such as "Continue helping with billing setup."
3. System posts an activity message: "Conversation handed back to Pilot by Alex."
4. Pilot sends a short visible message: "I'm back and can keep helping from here."
5. Conversation returns to `pending` with Pilot metadata state `pilot_resumed`.

Expose this through a focused endpoint:

```text
POST /api/v1/accounts/:account_id/conversations/:id/handback
```

The endpoint should verify that the conversation has a Pilot assistant attached through its inbox before changing state.

## Configuration Shape

Start with config on `pilot_assistants.config`:

```json
{
  "handoff_mode_online": "keep_pilot_warm",
  "handoff_mode_offline": "keep_pilot_active",
  "handoff_timeout_minutes": 5,
  "handoff_timeout_action": "resume_pilot",
  "handoff_timeout_message": "I'm still here and can keep helping while the team gets back to you.",
  "handback_enabled": true,
  "handback_message": "I'm back and can keep helping from here."
}
```

Later, if an assistant is attached to multiple inboxes with different staffing models, add per-inbox overrides through `pilot_inboxes`.

## Events

Route lifecycle events through `Custom::Pilot::EventDispatcher.dispatch` so they persist to `pilot_events` and can populate Pilot activity views.

Recommended event names:

- `pilot.handoff.requested`
- `pilot.handoff.routed`
- `pilot.handoff.failed`
- `pilot.handoff.timeout`
- `pilot.handoff.accepted`
- `pilot.handback.requested`
- `pilot.handback.completed`
- `pilot.resumed`

Keep existing `conversation.bot_handoff` reporting behavior intact where it is already used, but avoid using it as the only source of truth for Pilot state. It currently represents a core conversation transition, not the full Pilot handoff lifecycle.

## Build Order (MVP Scope)

1. **Config**: Add assistant config accessors for `handoff_timeout_minutes` and `handoff_timeout_message` on `Pilot::Assistant` and define localized strings.
2. **Core Handoff & Scheduling**: Update `Pilot::AutopilotInferenceJob#process_handover` to populate `pilot_handoff` metadata (`state: 'handoff_requested'`, `requested_at: Time.current`) and schedule the timeout check.
3. **Core Warm Bot Mode**: Modify `PilotAutopilotListener#message_created` to allow processing incoming messages on `open` conversations when they have metadata state `handoff_requested`, are unassigned, and have no human replies since requested timestamp.
4. **Core Timeout Rescue**: Implement `Pilot::HandoffTimeoutJob` to validate parameters, revert core status to `pending`, write an activity log, and post the fallback message.
5. **Tests**: Add unit and integration tests verifying metadata setup, timeout execution, and listener guards.


## Competitive Notes

These notes are directional product research, not implementation requirements.

- Tidio Lyro has the clearest co-active pattern: online and offline handoff actions can include transferring, creating a ticket, or keeping the chat with Lyro active. This maps well to `keep_pilot_warm` and `keep_pilot_active`. Source: <https://help.tidio.com/hc/en-us/articles/5399286434460-Going-offline>
- Zendesk documents maximum queue wait time behavior for routing and call queues. The general pattern is useful: if nobody responds within a configured window, trigger a fallback action. Source: <https://support.zendesk.com/hc/en-us/articles/4408843627290-Managing-incoming-call-queue-options>
- Ada separates off-hours and transfer/error fallback handling. That supports modeling "no agents available" separately from "handoff failed." Source: <https://docs.ada.cx/docs/handoffs/handoff-management>
- HubSpot supports availability branches in chatflows, but bot handback/resume behavior is not a first-class primitive in the same way. Source: <https://knowledge.hubspot.com/chatflows/use-if-then-branches-with-chatflows>
- LivePerson has escalation and fallback-dialog mechanics. Treat that as support for explicit fallback paths, not as proof that Konversio needs to mirror LivePerson's exact event model. Source: <https://developers.liveperson.com/conversation-builder-integrations-liveperson-agent-escalation-integrations.html>

The useful pattern to copy is the combination of:

1. co-active bot while routing happens;
2. timeout-based recovery when no human replies;
3. explicit human handback to the bot.

That gives Konversio the customer experience improvement without committing to a heavy queue system in the first iteration.
