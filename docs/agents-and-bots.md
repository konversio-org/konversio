# Agents, Bots, Autopilot & Copilot

A plain-English explainer of who (or what) can handle a conversation in Konversio, and how to think about them. Audience: anyone — engineer, admin, or new team member.

## The four roles

Every conversation in Konversio is handled by exactly one of these. Plus, optionally, **Copilot** as an assist layer on top.

| Role | Who/what is "the brain"? | Where the brain lives |
|---|---|---|
| **Agent** *(human)* | A person on your team | The dashboard, between two ears |
| **Bot** *(legacy auto-agent)* | Code you write | An external server you host, called via webhook |
| **Autopilot** *(AI Agent)* | Built-in LLM + your knowledge base | Inside Konversio |
| **Copilot** *(assist tool, not a responder)* | Built-in LLM, drafts suggestions | Inside Konversio, surfaced in the agent's UI |

### Agent (human)

The original. A real person logged into the dashboard, reading messages and typing replies. Nothing AI-related.

When we say **"Agent"** by itself, we always mean a human. If we mean something else, we'll say so explicitly (**Bot**, **Autopilot**).

### Bot (legacy auto-agent)

A **non-Konversio service** you build and host yourself. The flow:

1. A customer message arrives in an inbox connected to a Bot.
2. Konversio sends a **webhook event** (`message_created`, etc.) to a URL you provided.
3. **Your code** decides what to do — keyword match, decision tree, call OpenAI, look up an order, whatever.
4. Your code **posts a reply back** via the Konversio API.
5. The Bot can hand off to a human Agent at any point.

Bots are infrastructure-neutral. They can be dumb (regex matcher), classic NLU (Rasa/Dialogflow), or modern (your own LLM service). Konversio doesn't care — it's just messaging plumbing.

**Internal name:** `AgentBot` model. We don't say "Agent Bot" in user-facing copy — just **"Bot"**.

### Autopilot (AI Agent)

The **built-in AI responder**. The flow:

1. A customer message arrives in an inbox connected to an Autopilot **Assistant**.
2. Konversio's LLM reads the message + conversation history + your uploaded knowledge base.
3. The LLM **drafts and posts a reply** directly, no external server involved.
4. Autopilot can hand off to a human Agent at any point (same as Bot).

What you provide: documents (FAQ, help center, product docs), prompts, optional custom tools. What Konversio provides: the LLM, the RAG pipeline, the API integration, the UI.

**Internal name:** `Pilot::Assistant` (was `Captain::Assistant` upstream).

**Conceptually,** Autopilot is "a Bot whose brain Konversio writes for you." From the customer's point of view, both Bot and Autopilot are the same thing: a non-human responder. The difference is who built the response logic.

### Copilot (assist tool)

The odd one out: **Copilot does not talk to customers.** It talks to your human Agents.

- Suggests replies in the composer
- Summarizes long threads
- Powers the sparkle-menu utilities

Copilot is a **tool used by an Agent (human)**, not a responder in its own right. It can be enabled on any inbox staffed by humans, regardless of whether other inboxes use Bot or Autopilot.

**Internal name:** `pilot_copilot_enabled` account flag, plus `Pilot::CopilotThread` records.

## The one-responder-per-inbox rule

**An inbox has exactly one "primary responder":**

- **Agent (human)** — staffed by your team
- **Bot** — your webhook responder
- **Autopilot** — Konversio's built-in AI

You shouldn't run a Bot **and** an Autopilot on the same inbox. There is **no automatic enforcement** today — the Bot Configuration UI (`BotConfiguration.vue`) only handles Bot assignment, and Pilot/Autopilot inbox attachment currently has no frontend or controller of its own. So it's a convention you have to keep yourself: pick one responder per inbox. If both records are wired up via the API, both listeners (`agent_bot_listener.rb` and `pilot_autopilot_listener.rb`) will fire on every customer message and the customer will receive two competing replies.

**Different inboxes can use different responders.** A realistic Konversio setup:

| Inbox | Responder | Why |
|---|---|---|
| Website widget (Support) | **Autopilot** | RAG over help-center docs — easy to set up, covers most FAQ |
| WhatsApp (Sales) | **Bot** | Strict ordering flow, integrates with CRM, needs deterministic logic |
| Email (Returns) | **Agent (human)** only | Always goes straight to staff — too nuanced for automation |
| Facebook Messenger | **Bot** | Custom auth + order-status lookup against your backend |

**Copilot is orthogonal.** Enable it on whatever human-staffed inboxes you want.

## The handoff lifecycle

All three responder types share the same conversation lifecycle:

```
new conversation
       │
       ▼
   ┌──────────┐
   │ pending  │  ← Bot or Autopilot owns it. Replies autonomously.
   └────┬─────┘
        │  (responder decides to escalate, or rule fires)
        ▼
   ┌──────────┐
   │   open   │  ← Human Agent owns it. Bot/Autopilot stops replying.
   └────┬─────┘
        │  (agent finishes)
        ▼
   ┌──────────┐
   │ resolved │
   └──────────┘
```

A human can also flip a conversation **back** to `pending` if they want the Bot/Autopilot to take it again — useful for "let the bot try first, escalate if needed, but if it's something simple after the human glance, hand it back."

## Choosing between Bot and Autopilot

| Question | Bot | Autopilot |
|---|---|---|
| Who writes the response logic? | You (your code) | Konversio (the LLM) |
| Who hosts it? | You (your server) | Konversio |
| Do you need a developer? | Yes | No — admin can configure in the UI |
| Can it call external APIs? | Yes (you write it) | Yes (via custom tools) |
| Can it use AI? | Yes if you wire one up | Always |
| Best for | Strict business logic, integrations, deterministic flows | FAQ-style support, knowledge-base answering, conversational triage |

If you find yourself building a Bot that *is just an LLM with your help docs as context*, you've reinvented Autopilot. Use Autopilot.

If you need strict guarantees ("never refund without a manager approval", "always check stock before quoting"), Bot is the safer choice — you control the code path.

## A quick glossary recap

- **Agent** → person
- **Bot** → external webhook responder
- **Autopilot** → built-in AI responder (also called "AI Agent")
- **Copilot** → AI assist for the human Agent, not a responder
- **Pilot** → internal namespace covering both Copilot and Autopilot. Not a user-facing concept; don't use in copy.
- **Captain** → the upstream Chatwoot name for what we call Pilot. Konversio renamed it.

## Where the code lives

| Concept | Model / file |
|---|---|
| Agent (human) | `User` (with `role: agent`) |
| Bot | `AgentBot`, `AgentBotInbox` |
| Autopilot | `Pilot::Assistant`, `Pilot::Inbox`, `Pilot::AutopilotInferenceJob` |
| Copilot | `Pilot::CopilotThread`, `Pilot::CopilotMessage` |
| Listeners | `app/listeners/agent_bot_listener.rb`, `app/listeners/pilot_autopilot_listener.rb` |
