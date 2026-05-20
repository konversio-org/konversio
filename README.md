<img src="./.github/screenshots/header.png#gh-light-mode-only" width="100%" alt="Header light mode"/>
<img src="./.github/screenshots/header-dark.png#gh-dark-mode-only" width="100%" alt="Header dark mode"/>

___

# Konversio

The modern customer support platform, an open-source alternative to Intercom, Zendesk, Salesforce Service Cloud etc.

<!-- @TODO: All badges below point at chatwoot/chatwoot (CircleCI, Docker, Crowdin, Discord, status, ArtifactHub). Replace with Konversio-owned equivalents or remove. -->
<p>
  <img src="https://img.shields.io/circleci/build/github/chatwoot/chatwoot" alt="CircleCI Badge">
    <a href="https://hub.docker.com/r/chatwoot/chatwoot/"><img src="https://img.shields.io/docker/pulls/chatwoot/chatwoot" alt="Docker Pull Badge"></a>
  <a href="https://hub.docker.com/r/chatwoot/chatwoot/"><img src="https://img.shields.io/docker/cloud/build/chatwoot/chatwoot" alt="Docker Build Badge"></a>
  <img src="https://img.shields.io/github/commit-activity/m/chatwoot/chatwoot" alt="Commits-per-month">
  <a title="Crowdin" target="_self" href="https://chatwoot.crowdin.com/chatwoot"><img src="https://badges.crowdin.net/e/37ced7eba411064bd792feb3b7a28b16/localized.svg"></a>
  <a href="https://discord.gg/cJXdrwS"><img src="https://img.shields.io/discord/647412545203994635" alt="Discord"></a>
  <a href="https://status.chatwoot.com"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fchatwoot%2Fstatus%2Fmaster%2Fapi%2Fchatwoot%2Fuptime.json" alt="uptime"></a>
  <a href="https://status.chatwoot.com"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fchatwoot%2Fstatus%2Fmaster%2Fapi%2Fchatwoot%2Fresponse-time.json" alt="response time"></a>
  <a href="https://artifacthub.io/packages/helm/chatwoot/chatwoot"><img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artifact-hub" alt="Artifact HUB"></a>
</p>


<!-- @TODO: Dashboard screenshots are still Chatwoot's. Swap once Konversio UI diverges visibly. -->
<img src="./.github/screenshots/dashboard.png#gh-light-mode-only" width="100%" alt="Chat dashboard dark mode"/>
<img src="./.github/screenshots/dashboard-dark.png#gh-dark-mode-only" width="100%" alt="Chat dashboard"/>

---

## About Konversio

Konversio is a hard fork of [Chatwoot Community Edition](https://github.com/chatwoot/chatwoot) v4.13.0, released under the MIT license as Konversio v0.0.1. We've kept only the MIT-licensed core — Chatwoot's Enterprise overlay (including **Captain AI**) is not included or redistributed.

On top of this foundation we're building **Pilot**, a fully open-source AI layer with **bring-your-own-key** support for any LLM provider (OpenAI, Anthropic, Mistral, local models via Ollama, etc.). Pilot was built clean-room — observed Captain's behavior as an end-user, wrote a spec, then implemented from the spec without ever reading Captain's source. See [`FORK_STRATEGY.md`](./FORK_STRATEGY.md) for the full fork lineage and clean-room methodology. If AI was your only reason for considering Chatwoot Enterprise, Pilot removes that need. *(Pilot does not replicate other Enterprise features such as SSO or advanced role management.)*

Self-hosting + BYOK means **no customer data flows through a vendor's AI sub-processor** — you control where data lives and which providers touch it. This makes Konversio a suitable building block for **EU-sovereign, GDPR-compliant deployments**. The software enables compliance; the deployment achieves it.

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


<!-- @TODO: Points at Chatwoot's Crowdin. Honest only if Konversio upstreams translation contributions — otherwise replace with Konversio's own process or remove. -->
## Translation process

The translation process for Konversio web and mobile app is managed at [https://translate.chatwoot.com](https://translate.chatwoot.com) using Crowdin. Please read the [translation guide](https://www.chatwoot.com/docs/contributing/translating-chatwoot-to-your-language) for contributing to Konversio.

## Branching model

We use the [git-flow](https://nvie.com/posts/a-successful-git-branching-model/) branching model. The base branch is `develop`.
If you are looking for a stable version, please use the `master` or tags labelled as `v1.x.x`.

<!-- @TODO: Verify SECURITY.md — likely still routes vulnerability reports to security@chatwoot.com. Update to a Konversio contact. -->
## Security

Looking to report a vulnerability? Please refer our [SECURITY.md](./SECURITY.md) file.

## Community

If you need help or just want to hang out, come, say hi on our [Discord](https://discord.gg/cJXdrwS) server.

<!-- @TODO: Verify ./LICENSE actually contains Chatwoot's MIT copyright notice. If it was stripped during the fork, restore it — required for MIT compliance. -->
## Attribution & Contributors

Konversio is built on the work of the [Chatwoot](https://github.com/chatwoot/chatwoot) team and its [wonderful contributors](https://www.chatwoot.com/docs/contributors). Original Chatwoot copyright and MIT license terms are preserved in [`LICENSE`](./LICENSE).

<a href="https://github.com/chatwoot/chatwoot/graphs/contributors"><img src="https://opencollective.com/chatwoot/contributors.svg?width=890&button=false" /></a>


*Chatwoot* &copy; 2017–2025, Chatwoot Inc — MIT License.
*Konversio* &copy; 2025–2026, Konversio Inc — MIT License (Pilot and other original code).
