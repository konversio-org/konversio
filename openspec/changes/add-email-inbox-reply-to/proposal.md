## Why

When an email inbox receives mail via a forwarding chain (e.g. `support@migrately.nl` → Cloudflare → `mail@support.migrately.nl` → Resend → Konversio), outbound replies carry `Reply-To: mail@support.migrately.nl` — the internal routing address — instead of the public-facing address the contact originally wrote to. Contacts who reply to that address get a confusing sender, and the address leaks infrastructure details.

The correct Reply-To is the address contacts know (`support@migrately.nl`), which may differ from both the inbox `email` (Resend catch address) and the auto-generated `forward_to_email` (Chatwoot inbound routing token). There is currently no field to store this.

A temporary workaround was applied: `Email::ReplyToBuilder` was patched to use `forward_to_email.presence || email`, and `forward_to_email` was manually set to `support@migrately.nl` in production. This is semantically incorrect — `forward_to_email` is a Chatwoot-generated inbound routing token, not a human-facing address — and will break if the inbound forwarding setup changes.

## What Changes

- Add a nullable `reply_to_email` column to `channel_email`.
- Expose it in the inbox API and the email inbox settings UI as **"Reply-To address"**.
- Update `Email::ReplyToBuilder` to use `reply_to_email` when present, falling back to `email`.
- Revert the temporary `forward_to_email` workaround: reset `forward_to_email` to its auto-generated value and migrate the `support@migrately.nl` value to `reply_to_email`.

## Capabilities

### New Capabilities
- `email-inbox-reply-to`: Configurable Reply-To address per email inbox, surfaced in inbox settings UI and applied to all outbound email replies.

### Modified Capabilities
None.

## Impact

- `channel_email` table (new nullable column, migration required)
- `Channel::Email` model (`EDITABLE_ATTRS`, no new validations needed)
- `Email::ReplyToBuilder` (one-line logic change)
- `app/views/api/v1/models/_inbox.json.jbuilder` (expose new field)
- Email inbox settings Vue component (new optional text input)
- Production data: `forward_to_email` on inbox 34 must be reset; `reply_to_email` set to `support@migrately.nl`
