# Konversio Pilot AI Architecture

Konversio features a modular, open-source AI integration layer called **Pilot**. Pilot is designed for self-hosters and enterprises requiring multi-provider LLM routing, bring-your-own-key (BYO-Key) capability, and strict data residency compliance (such as GDPR).

---

## 1. Core Feature Terminology

Pilot uses an aviation-themed naming convention for its AI features:

| Feature | Description |
| :--- | :--- |
| **Pilot** | The core AI module running in the background. |
| **Copilot** | Agent-facing chat assistant enabling support agents to ask questions, request conversation summaries, or rewrite drafts. |
| **Autopilot** | Customer-facing chatbot that resolves incoming support inquiries and manages handovers to human agents. |
| **Briefing** | Composer-integrated drafts providing context-aware response suggestions for agents. |
| **Logbook** | Persistent, contact-level memory allowing the AI to maintain context across historical conversations with a single user. |

---

## 2. Directory Layout & Integration Pattern

To keep the core platform clean and maintainable, Pilot is implemented under the `custom/` directory using the platform's extension mechanisms. This allows clean overriding or prepending of model behaviors without modifying core Rails entities directly.

```
custom/
├── app/
│   ├── controllers/api/v2/konversio/pilot/
│   │   ├── briefings_controller.rb       - Generation of suggested drafts
│   │   ├── copilot_messages_controller.rb - Agent-copilot chat thread management
│   │   ├── autopilot_inboxes_controller.rb - Configuration for automated widget chat
│   │   ├── logbook_controller.rb         - Contact memory management
│   │   └── settings_controller.rb        - System-wide configuration
│   ├── models/custom/pilot/
│   │   ├── copilot_thread.rb
│   │   ├── copilot_message.rb
│   │   ├── autopilot_inbox.rb
│   │   ├── logbook_entry.rb
│   │   └── pilot_setting.rb
│   └── services/custom/pilot/
│       ├── pilot_service.rb              - Base LLM provider routing and client initialization
│       ├── briefing_service.rb           - Suggested drafts rendering
│       ├── copilot/
│       │   ├── chat_service.rb           - Agent chat thread orchestrator
│       │   ├── summarize_service.rb      - Thread summarization logic
│       │   └── rewrite_service.rb        - Draft tone/style modifiers
│       ├── autopilot/
│       │   ├── reply_service.rb          - Automated response generation
│       │   ├── handover_service.rb       - Routing to human queues
│       │   └── intent_service.rb         - Classification of incoming user intent
│       ├── logbook/
│       │   ├── memorize_service.rb       - Extractor that summarizes key details post-conversation
│       │   └── recall_service.rb         - Context loader for subsequent interactions
│       └── tools/
│           ├── base_tool.rb
│           ├── add_label_tool.rb
│           ├── add_private_note_tool.rb
│           └── http_tool.rb
└── config/
    └── initializers/
        └── pilot.rb                      - Registration of the Pilot extension
```

---

## 3. Database Schema

Pilot stores configuration, memory records, and chat history in dedicated database tables:

*   `pilot_settings`: Stores provider selections, encrypted API credentials, and default model routes per account.
*   `pilot_knowledge_sources`: References URL or file uploads configured for knowledge retrieval.
*   `pilot_documents`: Stores text chunks and corresponding embedding vectors (`vector(1536)`) for document search.
*   `pilot_copilot_threads`: Groups messages exchanged between an agent and the AI assistant for a specific ticket.
*   `pilot_copilot_messages`: Individual prompts, assistant responses, and structured tool execution records.
*   `pilot_autopilot_inboxes`: Binds autopilot configurations (handover rules, guardrails) to specific conversation inboxes.
*   `pilot_logbook_entries`: Stores persistent, structured contact summaries for long-term customer history.
*   `pilot_tool_invocations`: Log of API or internal tool executions made by the agents.

---

## 4. LLM Routing & Provider Support

Pilot is provider-agnostic and routes requests through a unified adapter layer. It supports any API compatible with the standard OpenAI schema, enabling operators to choose vendors based on pricing, speed, or geographical location:

*   **Public Services**: OpenAI (GPT models), Anthropic (Claude via compatible proxy), Google Gemini (via compatible proxy).
*   **European Sovereign Providers**: Scaleway (fully hosted in EU zones), Mistral AI (la Plateforme).
*   **Self-Hosted / Air-Gapped**: Ollama (for local model hosting).
