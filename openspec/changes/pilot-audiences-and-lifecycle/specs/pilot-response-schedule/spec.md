## Capability: pilot-response-schedule

Per-assistant response windows that gate Pilot engagement to always, business hours only, or outside business hours only, evaluated against the inbox's working-hours configuration.

---

## ADDED Requirements

### Requirement: Response window setting per assistant

Each `Pilot::Assistant` SHALL support an optional response-window setting with exactly three values: engage at all times, engage only during the inbox's configured business hours, or engage only outside those hours. A blank or absent value SHALL behave as "at all times". Any other value MUST be rejected by model validation.

#### Scenario: default is always

- Given a new assistant with no response-window config
- When a conversation is evaluated for engagement at any time
- Then the schedule check passes

#### Scenario: invalid window value is rejected

- Given an assistant update with an unrecognized response-window value
- When the assistant is saved
- Then validation fails with a config error

---

### Requirement: Window evaluation against inbox working hours

Schedule availability SHALL be evaluated per conversation against that conversation's inbox. When the inbox has working hours enabled, "business hours only" SHALL pass while the inbox is inside working hours and fail outside them; "outside business hours only" SHALL pass while the inbox is outside working hours and fail inside them. When the inbox does not have working hours enabled, every window value SHALL pass.

#### Scenario: business-hours window inside working hours

- Given an assistant configured to engage only during business hours
- And the inbox has working hours enabled and is currently open
- When a conversation is evaluated
- Then the schedule check passes

#### Scenario: business-hours window outside working hours

- Given an assistant configured to engage only during business hours
- And the inbox is currently outside its working hours
- When a conversation is evaluated
- Then the schedule check fails and the conversation starts `open`

#### Scenario: outside-hours window during working hours

- Given an assistant configured to engage only outside business hours
- And the inbox is currently inside its working hours
- When a conversation is evaluated
- Then the schedule check fails and the conversation starts `open`

#### Scenario: inbox without working hours is always available

- Given an assistant configured to engage only during business hours
- And the conversation's inbox has working hours disabled
- When the conversation is evaluated
- Then the schedule check passes

---

### Requirement: Schedule combines with audience as one engagement decision

The engagement decision for a conversation SHALL require both the audience check and the schedule check to pass. Either failing MUST result in the conversation starting `open` with no AI assignee.

#### Scenario: audience matches but schedule fails

- Given an assistant whose audience matches the contact
- And whose response window excludes the current time
- When the conversation is created
- Then its status is `open` and no AI assignee is set

#### Scenario: both checks pass

- Given an assistant whose audience matches the contact
- And whose response window includes the current time
- When the conversation is created
- Then its status is `pending` and the assistant is set as AI assignee

---

### Requirement: Schedule settings UI

The Pilot assistant settings MUST provide a schedule editor presenting the three response-window options as mutually exclusive choices with explanatory text, pre-selected from the assistant's current config, saving through the assistant update API.

#### Scenario: current selection is pre-populated

- Given an assistant configured to engage only outside business hours
- When the user opens the schedule settings
- Then the outside-business-hours option is selected

#### Scenario: saving updates the window

- Given the user selects the business-hours option
- When the user saves
- Then the assistant update API is called with the corresponding response-window value
- And subsequent conversations are gated accordingly
