## Tasks

### Backend

1. - [x] **Migration** — add nullable `reply_to_email` string column to `channel_email`; no default, no uniqueness constraint.
2. - [x] **Model** — add `:reply_to_email` to `Channel::Email::EDITABLE_ATTRS`; add optional format validation (valid email or blank).
3. - [x] **ReplyToBuilder** — change logic to `channel.reply_to_email.presence || channel.email`; remove the temporary `forward_to_email.presence` workaround committed earlier.
4. - [x] **Jbuilder** — expose `reply_to_email` alongside `email` in `app/views/api/v1/models/_inbox.json.jbuilder`.
5. - [x] **Data fix (production)** — on `support-migrately-nl` Scalingo: reset `forward_to_email` on inbox 34 back to auto-generated value; set `reply_to_email = 'support@migrately.nl'`. (forward_to_email=4700c3d7a266a47239c307cd08a5dccf@support.migrately.nl, reply_to_email=support@migrately.nl, id=1)

### Frontend

6. - [x] **Settings UI** — add optional "Reply-To address" text input in the email inbox configuration page (`ConfigurationPage.vue` or equivalent), below the existing email address field; save via existing inbox update API; show only for email-type inboxes.

### Validation

7. - [x] **Unit test** — `Email::ReplyToBuilder` spec: assert Reply-To uses `reply_to_email` when set, falls back to `channel.email` when nil.
8. - [ ] **Manual smoke test** — send email to `support@migrately.nl`; verify outbound reply from Konversio carries `Reply-To: support@migrately.nl`.

## Dependencies / Order

Tasks 1 → 2 → 3 must be sequential. Task 4 can run in parallel with 2–3. Task 6 depends on 4. Task 5 runs after deploy. Tasks 7–8 validate the whole chain.
