# Konversio

The open-source AI Customer Concierge platform — an alternative to Intercom, Zendesk, and Salesforce Service Cloud.

## About Konversio

Konversio is a hard fork of [Chatwoot Community Edition](https://github.com/chatwoot/chatwoot) v4.13.0, released under the MIT license. We retain the fully open-source, MIT-licensed core platform. **Chatwoot's Enterprise overlay — including the Captain AI layer — has been removed and is not redistributed.**

In its place we ship **Pilot**, an **independently re-expressed AI integration layer built on a custom SDK**. Pilot targets feature parity with Captain on an MIT-licensed, open-source footing, and supports **bring-your-own-key** (BYO-Key) for any LLM provider — OpenAI, Anthropic, Mistral, or local models via Ollama.

By offering self-hosting and BYO-Key support, Pilot ensures that **no customer data flows through a vendor's AI sub-processor** — you control exactly where data lives and which models process it. This makes Konversio an ideal platform for 🇪🇺 **EU-sovereign, GDPR-compliant deployments**.

---

## 🚀 Getting Started

Run Konversio locally with Docker Compose in four steps. See [`docs/getting-started.md`](./docs/getting-started.md) for the full walkthrough.

---

### ✨ Pilot – Open-Source BYOK AI Layer

Pilot is Konversio's open-source AI layer for customer support — the open alternative to closed AI add-ons. Pilot is **bring-your-own-key**: you supply credentials for OpenAI, Anthropic, Mistral, or point it at a local model via Ollama. No customer data is routed through a vendor's AI sub-processor, making Pilot a fit for 🇪🇺 EU-sovereign deployments and regulated industries.

### 💬 Omnichannel Support Desk

Konversio centralizes all customer conversations into one powerful inbox, no matter where your customers reach out from. It supports live chat on your website, email, Facebook, Instagram, Twitter, WhatsApp, Telegram, Line, SMS etc.

### 📚 Help center portal

Publish help articles, FAQs, and guides through the built-in Help Center Portal. Enable customers to find answers on their own, reduce repetitive queries, and keep your support team focused on more complex issues.

### 🗂️ Other features

#### Collaboration & Productivity

- Private Notes and @mentions for internal team discussions.
- Labels to organize and categorize conversations.
- Keyboard Shortcuts and a Command Bar for quick navigation.
- Canned Responses to reply faster to frequently asked questions.
- Auto-Assignment to route conversations based on agent availability.
- Multi-lingual Support to serve customers in multiple languages.
- Custom Views and Filters for better inbox organization.
- Business Hours and Auto-Responders to manage response expectations.
- Teams and Automation tools for scaling support workflows.
- Agent Capacity Management to balance workload across the team.

#### Customer Data & Segmentation
- Contact Management with profiles and interaction history.
- Contact Segments and Notes for targeted communication.
- Pilot Logbook for grounding AI in customer history.
- Campaigns to proactively engage customers.
- Custom Attributes for storing additional customer data.
- Pre-Chat Forms to collect user information before starting conversations.

#### Integrations
- Slack Integration to manage conversations directly from Slack.
- Dialogflow Integration for chatbot automation.
- Dashboard Apps to embed internal tools within Konversio.
- Shopify Integration to view and manage customer orders right within Konversio.
- Use Google Translate to translate messages from your customers in realtime.
- Create and manage Linear tickets within Konversio.

#### Reports & Insights
- Live View of ongoing conversations for real-time monitoring.
- Conversation, Agent, Inbox, Label, and Team Reports for operational visibility.
- CSAT Reports to measure customer satisfaction.
- Downloadable Reports for offline analysis and reporting.


## Branching model

We use the [git-flow](https://nvie.com/posts/a-successful-git-branching-model/) branching model. The base branch is `develop`.
If you are looking for a stable version, please use the `master` or tags labelled as `v1.x.x`.

<!-- @TODO: Verify SECURITY.md — likely still routes vulnerability reports to security@chatwoot.com. Update to a Konversio contact. -->
## Security

Looking to report a vulnerability? Please refer our [SECURITY.md](./SECURITY.md) file.

## License

Licensed under the MIT Expat license. See [`LICENSE`](./LICENSE).
