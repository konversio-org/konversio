## 1. Backend Data And Filtering

- [ ] 1.1 Confirm the existing Pilot assistants API payload includes attached inbox ids, names, and channel metadata needed for sidebar rendering.
- [ ] 1.2 Add a conversation finder filter for `pilot_assistant_id` that matches conversations with messages authored by the selected `Pilot::Assistant`.
- [ ] 1.3 Ensure the AI-agent participation filter composes with existing inbox, status, team, label, search, and permission scoping.
- [ ] 1.4 Add conversation payload metadata for visible AI agents that participated in each listed conversation.
- [ ] 1.5 Check the generated SQL for duplicate conversations and add `distinct` or a subquery if the message join can duplicate rows.

## 2. Frontend Routing And Sidebar

- [ ] 2.1 Add conversation routes for AI-agent filtered lists and AI-agent-plus-inbox drill-down lists.
- [ ] 2.2 Load or reuse Pilot assistant records in the main sidebar context.
- [ ] 2.3 Build the **AI Agents** sidebar group from customer-facing assistants with connected inboxes.
- [ ] 2.4 Render AI-agent child entries for connected inboxes/channels using existing channel icon patterns where practical.
- [ ] 2.5 Wire sidebar links so selecting an AI agent or AI-agent channel child applies the correct conversation list params.
- [ ] 2.6 Replace the Mine/Unassigned/All tabs in the conversation list header with Active (Autopilot), Handed Off, and Resolved (Contained) tabs when an AI Agent route is active.
- [ ] 2.7 Wire frontend filters to query the appropriate statuses and assignees for each AI-lifecycle tab (Active (Autopilot), Handed Off, Resolved (Contained)).
- [ ] 2.8 Disable triggering markMessagesRead when a conversation is viewed under an active AI Agent route to ensure spectator mode.


## 3. Conversation Cards

- [ ] 3.1 Add a compact AI-agent chip to conversation cards when payload metadata reports AI-agent participation.
- [ ] 3.2 Keep AI-agent chips visually distinct from business labels and do not add them to the label list.
- [ ] 3.3 Ensure card layout remains stable when labels, SLA chips, priority, inbox icon, and AI-agent chips appear together.

## 4. Copy And Naming

- [ ] 4.1 Add English i18n strings for **AI Agents** sidebar labels and any empty/loading states.
- [ ] 4.2 Keep user-facing copy in this feature on **AI Agents** and participation/touched language, not bare **Agents** or resolved/handled language.
- [ ] 4.3 Keep internal code integrations on existing `Pilot::Assistant` records and avoid introducing persistent `ai_agent` table/column names in this change.

## 5. Verification

- [ ] 5.1 Verify an account with Mira connected to Web and WhatsApp shows one **AI Agents** entry with both channel children.
- [ ] 5.2 Verify selecting Mira shows only conversations containing Mira-authored `Pilot::Assistant` messages.
- [ ] 5.3 Verify selecting Mira's WhatsApp child shows only WhatsApp conversations containing Mira-authored messages.
- [ ] 5.4 Verify conversations without AI-agent participation do not show an AI-agent chip.
- [ ] 5.5 Verify no conversation labels are created or modified when AI-agent participation is surfaced.
- [ ] 5.6 Verify selecting the 'Active (Autopilot)' tab shows only unassigned open conversations containing Mira messages.
- [ ] 5.7 Verify selecting the 'Handed Off' tab shows only assigned open conversations containing Mira messages.
- [ ] 5.8 Verify selecting the 'Resolved (Contained)' tab shows only unassigned resolved conversations containing Mira messages.
- [ ] 5.9 Verify that viewing an unread conversation under the AI Agent view does not mark it as read or decrease the unread count.


