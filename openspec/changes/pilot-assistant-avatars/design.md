## Context

Pilot assistants are defined in `app/models/pilot/assistant.rb`. Today the model explicitly stubs `avatar_url` to always return nil and hard-codes `default_avatar_url` to the konversio bot SVG. The model does not include `Avatarable`.

The account-scoped API lives at `Api::V1::Accounts::Pilot::AssistantsController`. It only permits name/description/config fields; there is no avatar handling and no `avatar` member action.

Routes under `namespace :pilot do resources :assistants` have no avatar route (contrast with sibling resources like agent_bots and inboxes that declare `delete :avatar, on: :member`).

Serialization:
- Assistant resource partial (`app/views/api/v1/accounts/pilot/assistants/_assistant.json.jbuilder`) emits core fields but no avatar_url.
- Conversation meta partial emits `pilot_assistants` with only id + name.
- `Message#push_event_data` + `merge_sender_attributes` calls `sender.push_event_data` for a Pilot::Assistant sender, which currently produces the fallback.

Frontend:
- `AssistantEditor.vue` (used from AutopilotIndex) has a complete form for all other assistant settings but no avatar control.
- The `pilot/assistants` store and API client do generic CRUD.
- `components-next/avatar/Avatar.vue` already supports `allowUpload`, file selection, drag/drop, preview, and delete emission.
- Widget `AgentMessage.vue` already reads `message.sender.avatar_url` (or falls back to the SVG / inbox avatar).
- `ConversationCard.vue` renders participating AI agents using `PilotSparkleIcon` + name from the conversation meta.

The proposal (see proposal.md) establishes the motivation and the single new capability `pilot-assistant-avatars`.

Existing patterns to follow exactly: `AgentBot` (includes Avatarable, permitted_params has :avatar + :avatar_url, `def avatar` purges, `process_avatar_from_url`, route), `Avatarable` concern, `Avatar::AvatarFromUrlJob`, contacts/inboxes controllers, and the new Avatar component.

CLAUDE.md constraints apply: host/container dev modes, Tailwind only, Composition API + script setup, i18n only in en files, minimal happy-path changes, no unnecessary guards, use existing infrastructure.

## Goals / Non-Goals

**Goals:**
- Allow a user to upload or provide a URL for a custom avatar image on any Pilot::Assistant.
- Persist the image via ActiveStorage using the standard `Avatarable` concern.
- Return a usable `avatar_url` (or empty/falsy) from the model so that all existing sender and list paths light up automatically.
- Surface upload/remove controls inside the existing AssistantEditor form using the standard Avatar component.
- Make the custom avatar appear (when set) for widget messages, conversation inbox cards/chips, assistant lists and pickers.
- When no custom avatar exists, preserve 100% of today's fallback behavior (inbox avatar or the konversio_bot.svg).
- Follow the exact controller/route/model patterns already proven for AgentBot and other avatarable resources.
- Keep the diff small and contained to the Pilot assistant vertical.

**Non-Goals:**
- New image processing, cropping UI, or transformations beyond what `avatar.representation(resize_to_fill: [250, nil])` + ActiveStorage already provide.
- Animated or non-image avatar support.
- Per-inbox avatar overrides for an assistant (the existing `inbox&.avatar_url` fallback in push_event_data remains unchanged).
- Changes to how Copilot suggestions vs full Autopilot responses attribute the assistant.
- Backfills, data migrations, or bulk avatar import.
- A standalone avatar management page or super-admin flows.
- Supporting avatar on the v2 pilot responses or other Pilot sub-resources.
- Automatic generation of avatars (initials are already handled by the Avatar component when no src).

## Decisions

**Decision: Include `Avatarable` on `Pilot::Assistant` (instead of hand-rolling has_one_attached + methods).**

Rationale: The concern is intentionally small and already used by AgentBot (the closest analog). Its `after_save :fetch_avatar_from_gravatar` is a no-op for this model (early return unless `saved_changes.key?(:email)`). Validation and `avatar_url` implementation are reused for free. Duplicating the code would violate "least code change" and "remove dead/unreachable code" guidance.

Alternative considered: a custom concern or direct attachment only on the model + custom `avatar_url` override. Rejected for duplication.

**Decision: Handle avatar on the existing `assistants_controller` under the pilot namespace + add `delete :avatar, on: :member` route.**

Rationale: All other assistant configuration (name, instructions, tools, features) lives in one controller and one route block. Adding a parallel top-level avatar resource would be inconsistent with how agent_bots and inboxes are done inside account scope. The purge action + permitted params + process_avatar_from_url trio is a well-established local pattern.

**Decision: Emit `avatar_url` from the assistant resource partial and from the conversation meta's `pilot_assistants` array.**

Rationale: 
- The assistant resource is what the settings editor and pickers consume.
- Conversation meta (`participating_pilot_assistants`) is what powers the AI agent chips on `ConversationCard.vue`.
- Message sender avatar already flows for free once `Pilot::Assistant#push_event_data` (and the underlying `avatar_url`) returns a real value. Adding the two serialization sites is the minimal surface to satisfy "everywhere the AI agent's identity is rendered".

**Decision: Place the avatar control near the top of `AssistantEditor.vue` (inside or right after the Basic Details grid) and use `<Avatar :allowUpload ...>` + event wiring.**

Rationale: The Avatar component already provides upload overlay, drag/drop, remove "x" button on hover, preview, and emits 'upload' / 'delete'. Using it gives instant consistency with contacts, users, etc. Placing it early makes the feature discoverable for branding use cases. We will keep the control compact.

Alternative (dedicated dropzone elsewhere in the form) rejected for duplication and inconsistency.

**Decision: Support both file upload (multipart) and `avatar_url` (remote fetch job) on create/update, mirroring AgentBot exactly.**

Rationale: The backend already has `::Avatar::AvatarFromUrlJob`. The frontend may want to support pasting a URL in some flows (or future bulk import). The controller pattern (`permitted_params.except(:avatar_url); ... ; process_avatar_from_url`) is proven.

**Decision: Keep fallback logic inside `push_event_data` (and any direct `avatar_url` callers) rather than pushing fallback resolution into the view layer.**

Rationale: Current code already does `avatar_url.presence || inbox&.avatar_url || default_avatar_url`. Once the real `avatar_url` from Avatarable returns a truthy string when attached (and '' when not), the presence check continues to work with zero behavior change for the no-avatar case.

## Risks / Trade-offs

- [Adding an ActiveStorage attachment to a model that previously had none] → No schema change or migration is required; attachments are dynamic. Risk of surprising blob behavior on existing records is minimal because the accessors are only exercised when we render or update avatar. Mitigation: the same include pattern used by AgentBot for years.
- [Form layout shift in AssistantEditor] → Adding the avatar row early in the form may push other sections down slightly. Trade-off accepted for discoverability. Mitigation: use a small size (e.g. 48px) and keep the section visually light.
- [New English-only i18n strings required] → Per project rules we only edit en.yml / en.json. Any new labels ("Assistant avatar", "Upload avatar", remove tooltip, etc.) must be added. This is normal for a feature.
- [Widget and message consumers must tolerate a new key or a real URL] → They already read `avatar_url` from sender and fall back gracefully. Risk is low.
- [Store update path for multipart] → The current pilot assistants store uses plain JSON payloads. We may need a small branch to use FormData when an avatar file is present (or POST the file separately). Trade-off: slightly more frontend code vs. a dedicated avatar endpoint. We will prefer the smallest change that re-uses the existing update action where possible.

## Migration Plan

- This is a purely additive feature. No database migration, no data backfill.
- Deploy order: backend (model + controller + routes + jbuilders) then frontend (editor + any store tweaks). Because the model change is safe (nil/'' avatar_url continues to trigger the old fallback path), partial deploys are low risk.
- Rollback: revert the code changes. Any blobs that were uploaded will remain in storage but will no longer be referenced (acceptable data orphaning for this scope; a future cleanup rake is out of scope).
- No feature flag — the assistants UI is already only shown when the account has pilot + pilot_autopilot enabled.
- Verification after deploy: create/edit an assistant with an image, confirm `avatar_url` appears in the show response and in a test conversation's message sender, confirm the image renders in the widget preview and in a conversation card, then delete the avatar and confirm fallback behavior returns.

## Open Questions

- Final microcopy and helper text for the avatar control (product + i18n review will refine the English strings we add).
- Whether the AssistantPicker dropdown items and the AI-agent chips in ConversationCard should render the real avatar image (with sparkle as a small badge or removed) or keep the sparkle icon as the primary "this is AI" signifier. Recommended to show the avatar for branding fidelity, but can be a fast follow-up PR.
- Should the initial creation flow in the editor support setting an avatar on first save, or only on subsequent edits? Backend will support it either way; frontend start simple (edit path) is acceptable.
- Any additional surfaces (e.g. public help center, email notifications, Linear integration) that render assistant identity and might want the avatar later. Out of scope for the initial change.