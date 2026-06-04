# Konversio

The modern customer support platform, an open-source alternative to Intercom, Zendesk, Salesforce Service Cloud etc.


---

## About Konversio

Konversio is an open-source customer support platform built on a MIT-licensed foundation, released under the MIT license. We've kept only the MIT-licensed core — no proprietary AI overlays are included or redistributed.

On top of this foundation we're building **Pilot**, a fully open-source AI layer with **bring-your-own-key** support for any LLM provider (OpenAI, Anthropic, Mistral, local models via Ollama, etc.). If AI was your only reason for considering Chatwoot Enterprise, Pilot removes that need. *(Pilot does not replicate other Enterprise features such as SSO or advanced role management.)*

Self-hosting + BYOK means **no customer data flows through a vendor's AI sub-processor** — you control where data lives and which providers touch it. This makes Konversio a suitable building block for **EU-sovereign, GDPR-compliant deployments**. The software enables compliance; the deployment achieves it.

---

## 🚀 Quick Start with Docker

The easiest way to run Konversio locally is using Docker Compose, which automatically starts PostgreSQL, Redis, Mailhog, the Rails backend, and the Vite frontend.

### 1. Copy Environment Template
```bash
cp .env.example .env
```

### 2. Boot the Containers
```bash
docker compose up -d
```
*(Wait for the `postgres` and `redis` healthchecks to pass.)*

### 3. Initialize the Database
```bash
docker compose exec rails bundle exec rails db:chatwoot_prepare
```

### 4. Access the App
Once started, the services are available at:
* **Frontend Dashboard**: [http://localhost:3000](http://localhost:3000)
* **Vite Dev Server (HMR)**: [http://localhost:3036](http://localhost:3036)
* **Mailhog Web Interface**: [http://localhost:8025](http://localhost:8025)

#### Default Development Credentials:
* **Email**: `john@acme.inc`
* **Password**: `Password1!`

---

### ✨ Pilot – Open-Source BYOK AI Layer

Pilot is Konversio's open-source AI layer for customer support — the open alternative to closed AI add-ons. Pilot is **bring-your-own-key**: you supply credentials for OpenAI, Anthropic, Mistral, or point it at a local model via Ollama. No customer data is routed through a vendor's AI sub-processor, making Pilot a fit for EU-sovereign deployments and regulated industries.

- **Pilot Logbook**: Agents can record key context about contacts to ground AI responses in customer history, ensuring Pilot has the most relevant background information.

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


## Translation process

Translation contributions are welcome. Details on the Konversio translation workflow are coming soon — watch this repo for updates.

## Branching model

We use the [git-flow](https://nvie.com/posts/a-successful-git-branching-model/) branching model. The base branch is `develop`.
If you are looking for a stable version, please use the `master` or tags labelled as `v1.x.x`.

## Security

Looking to report a vulnerability? Please refer our [SECURITY.md](./SECURITY.md) file.

## Community

If you need help or just want to hang out, come, say hi on our [Discord](https://discord.gg/cJXdrwS) server.

## Attribution & Contributors

Konversio stands on the shoulders of a large open-source community. Original copyright and MIT license terms are preserved in [`LICENSE`](./LICENSE).

*Konversio* &copy; 2025–2026, Konversio Inc — MIT License (Pilot and other original code).
