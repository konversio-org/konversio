## 1. Model & Persistence

- [x] 1.1 Add `include Avatarable` to `Pilot::Assistant` (after the existing includes/concerns if any)
- [x] 1.2 Review/keep `avatar_url` stub and `default_avatar_url`; ensure `push_event_data` still does `avatar_url.presence || inbox&.avatar_url || default_avatar_url` (the presence check will now work for real attachments)
- [x] 1.3 Confirm that `Avatarable`'s gravatar hook and validations are safe for this model (no email, standard image types)

## 2. Backend API Controller

- [x] 2.1 Update `assistant_params` in `Api::V1::Accounts::Pilot::AssistantsController` to permit `:avatar, :avatar_url`
- [x] 2.2 Add private helper `process_avatar_from_url` (enqueue `Avatar::AvatarFromUrlJob` when `params[:avatar_url].present()` after save)
- [x] 2.3 Implement `def avatar` action that purges the attachment if present and returns the assistant (or head :ok)
- [x] 2.4 Call `process_avatar_from_url` after successful create and update (mirroring AgentBotsController)

## 3. Routes

- [x] 3.1 Inside the `namespace :pilot { resources :assistants do ... }` block in `config/routes.rb`, add `delete :avatar, on: :member`

## 4. Serialization (Jbuilders)

- [x] 4.1 Add `json.avatar_url assistant.avatar_url` (or `assistant.try(:avatar_url)`) to `app/views/api/v1/accounts/pilot/assistants/_assistant.json.jbuilder`
- [x] 4.2 Update the `pilot_assistants` block in `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` to also emit `avatar_url` for each participating assistant

## 5. Dashboard Settings UI (AssistantEditor)

- [x] 5.1 Import the Avatar component from 'next/avatar/Avatar.vue'
- [x] 5.2 Add reactive state for the current avatar preview (`avatarPreview`) and a pending file (`avatarFile`)
- [x] 5.3 Add a compact avatar section (near the top) that renders `<Avatar :src="..." :name="name" :size="56" allow-upload rounded-full @upload="handleAvatarUpload" @delete="handleAvatarDelete" />`
- [x] 5.4 Implement `handleAvatarUpload({ file, url })` that sets local preview state and stores the File
- [x] 5.5 Implement `handleAvatarDelete()` that clears the local file/preview and immediately calls delete for edits
- [x] 5.6 On submit, after main create/update, if a new file is pending use the lightweight `uploadAvatar` multipart call (or deleteAvatar)
- [x] 5.7 After successful save + avatar upload, the editor emits 'saved' (parent refetches) and local state is cleared

## 6. Store & API Client (if extension needed)

- [x] 6.1 Added `uploadAvatar(id, file)` and `deleteAvatar(id)` to PilotAssistantsAPI (lightweight multipart + delete). Editor uses them directly after main save for MVP (avoids big FormData refactor in store for now).
- [x] 6.2 The store mutations (UPDATE_RECORD / ADD_RECORD) receive the full record from the main save (which now includes `avatar_url` thanks to the jbuilder). Avatar-specific calls are best-effort follow-ups.

## 7. i18n (English only)

- [x] 7.1 Added `PILOT.SETTINGS.FORM.AVATAR_HINT` to en/pilot.json with the hint text for the control.
- [x] 7.2 Only touched the English file.

## 8. Verification & Edge Cases

- [ ] 8.1 Manually (or via existing test data) create a new Pilot assistant and upload a small PNG/JPEG; confirm `avatar_url` is present in the show response and in a test message's sender data
- [ ] 8.2 Start a conversation that triggers the assistant; verify the custom image appears in the web widget next to the assistant message
- [ ] 8.3 In the dashboard, confirm the assistant appears with its custom avatar in the Autopilot settings list/picker and that the conversation card AI agent chip can surface the image (via the updated meta)
- [ ] 8.4 Remove the avatar via the editor; confirm fallback to konversio_bot.svg (or inbox avatar) is restored in subsequent messages and lists
- [ ] 8.5 Test the `avatar_url` remote path: pass a public image URL on create/update and confirm the job attaches it
- [ ] 8.6 Attempt an oversized or invalid file upload; confirm validation error and that no bad attachment is left behind
- [ ] 8.7 (Optional but recommended) Exercise the flow in both host dev mode and container mode to confirm ActiveStorage + Vite asset serving works

**Note (post-implementation):** Linting (RuboCop + ESLint) passes for the changed files. Limits tightened to 1MB / 512x512 as requested. Code is on `feat/pilot-assistant-avatars`.

## 9. Cleanup / Follow-ups (non-blocking for initial PR)

- [ ] 9.1 Consider enhancing `AssistantPicker.vue` items and `ConversationCard` AI chips to render the real avatar (with sparkle as a small overlay or removed) for stronger branding
- [ ] 9.2 Add a small note or screenshot to relevant Pilot docs (e.g. docs/agents-and-bots.md or PILOT_PRESETS.md) if the feature warrants user-facing documentation
- [ ] 9.3 If the multipart update path in the store feels awkward, extract a tiny composable or helper for "avatar-aware" resource updates (future polish only)

**Implementation status:** Core feature (model, API, routes, serialization, editor UI + persistence) is complete and lint-clean on the branch. Verification steps (8.x) are manual / require running app + data. Extra: global avatar limits reduced to 1MB + 512x512px.