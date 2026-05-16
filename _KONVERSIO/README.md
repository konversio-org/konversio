# Konvers.io — Open Customer Conversations. BYO-key AI Operators.

## What This Is

Konversio is an open-source (MIT) customer support platform forked from
Chatwoot v4.13.0 (April 17, 2026). We dropped every line of proprietary
enterprise code and are building our own fully open BYO-key AI layer called
**Operator**.

Chatwoot ships two editions: Community (MIT) and Enterprise (proprietary,
in the `enterprise/` directory). Their "Captain" AI agent is enterprise-only
— $200/month for 10,000 responses, vendor-locked.

Konversio keeps everything MIT, strips the enterprise lock-in, and replaces
Captain with Operator: you bring your own API key from any provider (OpenAI,
Scaleway, Mistral, Groq, Ollama — anything OpenAI-compatible).

## Fork Lineage

```
Chatwoot v4.13.0 (MIT core + proprietary enterprise/)
    │
    ├── Removed: enterprise/ (all proprietary code)
    ├── Removed: Captain AI UI + API (dead without enterprise backend)
    ├── Stubbed: Copilot/AI reply composables (rebuilding as Operator)
    ├── Renamed: Chatwoot → Konversio (upcoming)
    │
    └── Konversio v0.1.0 (100% MIT)
            │
            └── Phase 2: Build Operator (BYO-key AI)
```

## What Was Stripped

### Entirely Deleted

| Directory | Contents | Reason |
|-----------|----------|--------|
| `enterprise/` | All EE code (~200+ Ruby files) | Proprietary license |
| `spec/enterprise/` | EE test suite | Proprietary |
| `app/javascript/dashboard/api/enterprise/` | EE API client | Calls deleted EE routes |
| `app/javascript/dashboard/api/captain/` | Captain API client | Calls deleted EE routes |
| `app/javascript/dashboard/components-next/captain/` | 61 Captain UI components | Dead UI |
| `app/javascript/dashboard/routes/dashboard/captain/` | Captain page routes | Dead routes |
| `app/javascript/dashboard/routes/dashboard/settings/captain/` | Captain settings | Dead settings |
| `app/javascript/dashboard/store/captain/` | Captain Vuex stores | Dead stores |
| `app/javascript/dashboard/composables/captain/` | Captain composables | Dead logic |
| Captain/copilot spec files | EE test files | Tests for deleted code |
| Captain image assets | Icons/illustrations | Dead assets |

### Stubbed Out

These features called enterprise-only APIs and would crash. They're now safe no-ops:

| File | What Changed |
|------|-------------|
| `useCopilotReply.js` | Returns inactive state; reset/execute/accept are no-ops |
| `useLabelSuggestions.js` | Returns empty arrays; feature flags always false |
| `TagTools.vue` | Empty template — no captain tools to show |
| `accounts.js` (store) | checkout/subscription/limits log a console warning |
| `PurchaseCreditsModal.vue` | Top-up purchase is a no-op |
| `CustomerSatisfactionPage.vue` | Utility analyzer hidden (needed captain) |
| `billing/Index.vue` | Captain limits section removed |
| `BulkSelectBar.vue` | Placeholder component (was in captain dir) |

### Cleaned Config

- `LICENSE` — Pure MIT. Attribution: "Based on Chatwoot v4.13.0 (MIT)"
- `config/application.rb` — Removed all enterprise load paths
- `tailwind.config.js` — Removed enterprise view paths

### Safe to Leave (CE infrastructure)

These remain because they're MIT-licensed infrastructure we'll reuse:

- `app/models/concerns/captain_featurable.rb` — LLM model/feature config
- `app/models/concerns/account_captain_auto_resolve.rb` — Auto-resolve mode
- `app/controllers/api/v1/accounts/captain/preferences_controller.rb` — Settings endpoint
- `lib/llm/models.rb` — LLM model registry
- `lib/llm/config.rb` — LLM configuration
- `config/initializers/01_inject_enterprise_edition_module.rb` — Extension hook system
- `lib/chatwoot_app.rb` — `ChatwootApp.enterprise?` now always returns false

## What Remains (MIT Core)

Everything from Chatwoot Community Edition:

- **Omnichannel inbox**: Live chat, email, WhatsApp, Facebook, Instagram, Telegram, SMS, Line
- **Help center**: Articles, FAQs, portals, categories
- **Automation**: Rules engine, macros, canned responses
- **Routing**: Round-robin, labels, teams, assignment policies
- **Reports**: Agent, inbox, label, team, CSAT, SLA reports
- **Collaboration**: Private notes, @mentions, teams
- **Integrations**: Slack, Shopify, Linear, Dialogflow, Google Translate, Stripe
- **Widget**: Embeddable chat widget (Vue.js)
- **API**: REST API, webhooks, custom attribute definitions
- **Multi-tenant**: Account isolation, super admin console
- **Security**: MFA/2FA, SAML SSO, audit logs (CE version)
- **i18n**: 30+ languages via Crowdin

## Architecture for Operator (Phase 2)

Chatwoot's enterprise module uses a `prepend` hook pattern:

```ruby
# CE base implementation (ours)
class Inbox < ApplicationRecord
  prepend_mod_with('Inbox')  # hooks enterprise module if available

  def member_ids_with_assignment_capacity
    members.ids
  end
end
```

Operator will use the same `prepend_mod_with` mechanism via the `custom/`
directory (already supported by `ChatwootApp.extensions`):

```
custom/
├── app/
│   ├── models/custom/
│   │   ├── conversation.rb       # preprends AI reply logic
│   │   └── message.rb            # preprends AI summarization
│   ├── controllers/custom/
│   │   └── operator_controller.rb
│   └── services/custom/
│       ├── operator/
│       │   ├── reply_service.rb
│       │   ├── summarize_service.rb
│       │   └── label_service.rb
│       └── operator_service.rb
├── config/
│   └── initializers/
└── lib/
    └── operator/
```

### Operator Features (planned)

1. **BYO-key**: User configures provider (OpenAI, Scaleway, Mistral, etc.) + API key + endpoint URL
2. **Smart reply suggestions**: AI-generated reply drafts for agents
3. **Conversation summarization**: Auto-summarize long threads
4. **Label suggestions**: AI-suggested labels based on conversation content
5. **Help-center aware**: Pulls from knowledge base articles for accurate answers
6. **Auto-triage**: Route conversations based on AI-classified intent
7. **Human handoff**: Seamless transition from AI to human agent
8. **No vendor lock-in**: Switch providers anytime, run local models via Ollama

### Provider Support

Any OpenAI-compatible API. Tested targets:
- OpenAI (GPT-4o, GPT-4o-mini)
- Scaleway (Mistral, Llama)
- Mistral (la Plateforme)
- Groq (fast inference)
- Ollama (local, air-gapped)
- Anthropic (Claude, via compatible proxy)
- Google Gemini (via compatible proxy)

## Rename Pass (Upcoming)

Global rename: `Chatwoot` → `Konvers`, `chatwoot` → `konvers`, `CW_` → `KV_`, etc.

## Commands

```bash
cd /Users/rcoenen/Dev/Konversio
git log --oneline -1    # Should show v4.13.0 tag
git branch              # Should be on 'main'
```

## License

MIT — see `LICENSE`.

Based on Chatwoot v4.13.0, copyright (c) 2017-2024 Chatwoot Inc.
Konversio modifications copyright (c) 2026.
