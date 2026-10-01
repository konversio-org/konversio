## ADDED Requirements

### Requirement: Pilot assistant supports a custom avatar image
The system SHALL allow a Pilot::Assistant to have a custom avatar image attached.

#### Scenario: Administrator uploads an image file as the assistant avatar
- **WHEN** an authorized user updates a Pilot assistant and provides a valid image file (PNG/JPEG/GIF, ≤15 MB)
- **THEN** the image is stored as an ActiveStorage attachment on the assistant
- **AND** subsequent fetches of the assistant return a non-empty avatar_url

#### Scenario: Administrator sets avatar via remote URL
- **WHEN** an authorized user creates or updates a Pilot assistant with a valid avatar_url
- **THEN** the system enqueues an AvatarFromUrlJob to fetch and attach the image
- **AND** once processed, the assistant exposes the resulting avatar_url

### Requirement: Assistant resource serializes avatar_url
The Pilot assistants API SHALL include an `avatar_url` field in responses for the assistant resource (index, show, create, update).

#### Scenario: Fetching an assistant that has a custom avatar
- **WHEN** a client GETs /api/v1/accounts/:account_id/pilot/assistants/:id (or the list)
- **THEN** the JSON includes "avatar_url": "<signed or public URL to the representation>"

#### Scenario: Fetching an assistant with no custom avatar
- **WHEN** a client GETs an assistant that has never had an avatar set
- **THEN** the JSON includes "avatar_url" as an empty string or null (consistent with other avatarable resources)

### Requirement: Message sender data carries assistant avatar
When a message is sent by a Pilot::Assistant, the serialized sender data SHALL contain the assistant's current avatar_url (or the established fallback).

#### Scenario: Autopilot or Copilot responds in a conversation
- **WHEN** a customer message triggers a Pilot assistant response and the message is pushed via ActionCable / API
- **THEN** the message payload's sender object includes avatar_url set to the assistant's custom avatar (when present)
- **AND** the widget and dashboard render that image next to the assistant message

### Requirement: Conversation metadata includes participating assistant avatars
The conversation meta object SHALL include avatar_url for each assistant listed under pilot_assistants.

#### Scenario: Loading a conversation that has had AI assistant participation
- **WHEN** the conversation JSON (or conversation list item meta) is returned
- **THEN** each object under pilot_assistants contains at minimum id, name, and avatar_url
- **AND** the dashboard ConversationCard can display the real image for the AI agent chip

### Requirement: Fallback behavior is preserved when no custom avatar is set
When a Pilot assistant has no custom avatar attached, the system SHALL continue to use the previous fallback chain (inbox avatar if present, otherwise the default konversio bot SVG).

#### Scenario: Assistant with no avatar participates in a conversation
- **WHEN** the assistant sends a message or is listed in conversation meta
- **THEN** avatar_url resolves to the inbox's avatar_url (if the inbox has one) or to /assets/images/konversio_bot.svg
- **AND** no custom image is shown

### Requirement: Avatar can be removed
The system SHALL provide a way to remove a previously set custom avatar from a Pilot assistant, after which the assistant reverts to the fallback behavior.

#### Scenario: User deletes the avatar via the settings UI or API
- **WHEN** an authorized user issues DELETE /api/v1/accounts/:account_id/pilot/assistants/:id/avatar (or the UI equivalent)
- **THEN** the attachment is purged
- **AND** subsequent reads of the assistant and its messages return no custom avatar_url (fallback applies)

### Requirement: Standard avatar validations apply
Uploads of assistant avatars SHALL be subject to the same size and content-type validations used by other avatarable resources in the system.

#### Scenario: User attempts to upload an invalid file
- **WHEN** a user selects a file that is too large (>15 MB) or of an unsupported type (e.g. PDF, SVG that is not representable)
- **THEN** the update/create is rejected with an appropriate validation error
- **AND** the previous avatar (if any) remains unchanged

### Requirement: Assistant settings UI exposes avatar control
The Pilot assistant settings form SHALL provide a control to upload, preview, and remove the assistant's custom avatar.

#### Scenario: User opens the assistant editor for an existing assistant
- **WHEN** the AssistantEditor form is rendered for an assistant that has (or can have) an avatar
- **THEN** an Avatar component instance (with allowUpload) is present and shows the current image or the generated initials/fallback
- **AND** hovering or clicking the control allows selecting a new image file or removing the current one
- **AND** saving the form persists the chosen avatar

#### Scenario: Removing the avatar in the UI
- **WHEN** the user activates the remove affordance on the avatar control and saves
- **THEN** the assistant no longer has a custom avatar and the form preview reverts to the default presentation (initials or bot glyph)