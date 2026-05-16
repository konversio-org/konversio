# Konversio — Open Customer Support, BYO-key AI

Open-source (MIT). Forked from Chatwoot. Built for self-hosters who want
the full Chatwoot toolset plus AI features without the Enterprise license.

## Naming model (strict — used throughout this codebase)

| Layer | Name | Notes |
|---|---|---|
| **Platform / product** | **Konversio** | The fork. Replaces "Chatwoot" everywhere in code. |
| **AI module (future)** | **Pilot** | Replacement for Chatwoot's Enterprise "Captain". Not built yet — Phase 2. |
| **Human support staff** | Agents | Unchanged from Chatwoot terminology. |
| **Chatwoot's AI brand** | Captain | Referenced only for context; the code was stripped. |

## What This Is

Konversio is an open-source (MIT) customer support platform forked from
Chatwoot v4.13.0 (April 17, 2026). We dropped every line of proprietary
enterprise code, leaving a clean MIT base. The AI layer that Chatwoot
sells as "Captain" (Enterprise-only, $200/month for 10,000 responses,
vendor-locked) will be replaced by **Pilot** — a fully open, BYO-key,
multi-provider AI module that lives in `custom/app/services/custom/pilot/`.

**Pilot is not built yet.** Today Konversio is "Chatwoot CE, stripped and
rebranded." Pilot lands in Phase 2.

## Fork Lineage

```
Chatwoot v4.13.0 (MIT core + proprietary enterprise/)
    │
    ├── Removed: enterprise/ (all proprietary code)
    ├── Removed: Captain AI UI + API (dead without enterprise backend)
    ├── Stubbed: Copilot/AI reply composables (will be rebuilt as Pilot)
    ├── Renamed: Chatwoot → Konversio
    │
    └── Konversio v0.1.0 (100% MIT, no AI yet)
            │
            └── Phase 2: Build the Pilot AI module (BYO-key)
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

## Architecture for Pilot AI (Phase 2)

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

Pilot will use the same `prepend_mod_with` mechanism via the `custom/`
directory (already supported by `ChatwootApp.extensions`):

```
custom/
├── app/
│   ├── models/custom/
│   │   ├── conversation.rb       # preprends AI reply logic
│   │   └── message.rb            # preprends AI summarization
│   ├── controllers/custom/
│   │   └── pilot_controller.rb
│   └── services/custom/
│       ├── pilot/
│       │   ├── reply_service.rb
│       │   ├── summarize_service.rb
│       │   └── label_service.rb
│       └── pilot_service.rb
├── config/
│   └── initializers/
└── lib/
    └── pilot/
```

### Config naming

Pilot config uses **`PILOT_*`** env vars / `InstallationConfig` keys, never
`CAPTAIN_*`. This is a deliberate break from upstream Chatwoot:

| Chatwoot | Pilot |
|---|---|
| `CAPTAIN_OPEN_AI_API_KEY` | `PILOT_OPEN_AI_API_KEY` |
| `CAPTAIN_OPEN_AI_ENDPOINT` | `PILOT_OPEN_AI_ENDPOINT` |
| `CAPTAIN_OPEN_AI_MODEL` | `PILOT_OPEN_AI_MODEL` |
| `CAPTAIN_OPEN_AI_API_PROVIDER` | `PILOT_OPEN_AI_API_PROVIDER` |
| `CAPTAIN_EMBEDDING_MODEL` | `PILOT_EMBEDDING_MODEL` |
| `CAPTAIN_EMBEDDING_DIMENSIONS` | `PILOT_EMBEDDING_DIMENSIONS` |
| `CAPTAIN_OPEN_AI_TRANSLATION_MODEL` | `PILOT_OPEN_AI_TRANSLATION_MODEL` |
| `CAPTAIN_FIRECRAWL_API_KEY` | `PILOT_FIRECRAWL_API_KEY` |

Migrating Chatwoot users have to rename their env vars once. The
brand-consistent naming wins long-term over the one-time migration cost.

### Pilot Features (planned)

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

Global rename: `Chatwoot` → `Pilot`, `chatwoot` → `pilot`, `CW_` → `PLT_`, etc.

## Commands

```bash
cd /Users/rcoenen/Dev/Konversio
git log --oneline -1    # Should show v4.13.0 tag
git branch              # Should be on 'main'
```

## License

MIT — see `LICENSE`.

Based on Chatwoot v4.13.0, copyright (c) 2017-2024 Chatwoot Inc.
Pilot modifications copyright (c) 2026.
