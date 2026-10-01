## Why

Pilot AI assistants (Pilot::Assistant, powering Autopilot and Copilot) currently have no way to set a custom avatar. They always fall back to a hardcoded default bot glyph (`konversio_bot.svg`) everywhere their identity is shown. Human agents, classic AgentBots, inboxes, and contacts all support custom avatars via ActiveStorage. This is a cosmetic/branding gap that surfaces when embedding the widget (e.g., an assistant named "AiRno" still shows the generic bot icon) and in dashboard conversation lists and settings.

## What Changes

- Add full custom avatar support (upload, storage, delete, URL) to `Pilot::Assistant` so AI agents can have branded pictures, with the existing default as fallback.
- Backend API: permit avatar/avatar_url on create/update, add DELETE avatar member action, process URL-sourced avatars, and serialize `avatar_url` in responses and message sender data.
- Routes: register the avatar delete endpoint under the pilot assistants namespace (following the AgentBot/Inbox/Contact pattern).
- Serialization: include `avatar_url` in the assistant resource partial and in the conversation meta's `pilot_assistants` block (so inbox cards can display it).
- Model: integrate `Avatarable` (or equivalent) on `Pilot::Assistant`, keep/adapt `push_event_data` and fallback logic (`custom` → inbox avatar → default SVG).
- Frontend dashboard: add avatar upload/select UI inside `AssistantEditor.vue` (reuse the existing `components-next/avatar/Avatar.vue` with `allowUpload`).
- Ensure the avatar flows through to all identity surfaces: web widget message bubbles, conversation/inbox views (including AI agent chips), assistant pickers and lists.
- Preserve all current behavior when no avatar is set.

No breaking changes.

## Capabilities

### New Capabilities
- `pilot-assistant-avatars`: Custom avatar images for Pilot AI assistants. Covers persistence via ActiveStorage, upload/delete endpoints + avatar_url handling, serialization to messages and conversation metadata, settings UI for upload, and display in widget + dashboard surfaces with proper fallbacks.

### Modified Capabilities

(none — no existing requirement-level specs are being altered; this is additive capability for the Pilot assistant domain)

## Impact

- `app/models/pilot/assistant.rb` (add Avatarable include, avatar_url/default handling, update push_event_data)
- `app/controllers/api/v1/accounts/pilot/assistants_controller.rb` (params, avatar action, process_avatar_from_url)
- `config/routes.rb` (add `delete :avatar, on: :member` inside `namespace :pilot { resources :assistants }`)
- `app/views/api/v1/accounts/pilot/assistants/_assistant.json.jbuilder` (and show/create/update wrappers)
- `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` (add avatar_url to the pilot_assistants block)
- `app/javascript/dashboard/routes/dashboard/pilot/AssistantEditor.vue`
- `app/javascript/dashboard/store/pilot/assistants/index.js` and `app/javascript/dashboard/api/pilot/assistants.js` (avatar-aware update/create flows)
- Widget rendering paths that already read `message.sender.avatar_url` (e.g. `AgentMessage.vue`) and dashboard conversation cards / pickers (for richer AI agent display)
- Leverages existing shared infrastructure: `Avatarable` concern, `Avatar::AvatarFromUrlJob`, `components-next/avatar/Avatar.vue`, ActiveStorage, and the custom Pilot payload builder (which already defensively reads avatar_url)
- Minor i18n additions (labels/hints) only in `en.yml` / `en.json`
- Affects message push_event_data for Pilot::Assistant senders and any place assistant identity is rendered

This change is contained to the Pilot assistant feature area and follows existing avatar patterns used by AgentBot and other models.