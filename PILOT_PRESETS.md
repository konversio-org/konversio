# Pilot Provider Presets

This document lists copy-paste-ready environment variable blocks for the LLM
providers Pilot supports. Each block configures the Pilot AI module
(`Custom::Pilot::*`) for one provider. Pick one, set the variables on the
target host (Heroku, Docker, systemd, etc.), and Pilot will route every
inference call through that provider.

Pilot reads every `PILOT_*` variable through `GlobalConfigService`, which
checks the process environment first and falls back to the
`installation_configs` table. The first read of an ENV-only value also writes
it back to the DB so the Super Admin UI surfaces the effective value.

> **Note:** Pilot does NOT read `PILOT_*` environment variables. If your
> install previously ran the Pilot enterprise module, the `PILOT_*` keys
> are inert from Pilot's perspective.

---

## Picking a provider

| Provider | Briefing | Copilot (tool calls) | Autopilot (agentic) | EU residency | Cost |
|---|---|---|---|---|---|
| **OpenAI** (`gpt-4o-mini`) | ✅ | ✅ | ✅ | ❌ (US) | $$ |
| **Scaleway** (`gemma-4-26b-a4b-it`) | ✅ fast (~0.4s) | ✅ highly reliable | ✅ | ✅ | $ |
| **Nebius** (Qwen / Llama) | ✅ | ⚠️ same caveats as Scaleway | ⚠️ partial | ✅ | $ |

**Rule of thumb:** if Pilot just needs a one-shot reply draft (Briefing, Summary, Rewrite, Follow-up), any EU-residency preset works fine and is cheaper. If Pilot needs to invoke tools mid-conversation (Copilot, Autopilot, Logbook extraction with tool calls), strict-JSON / tool-call compliance matters and OpenAI's GPT-4 family or Scaleway's Gemma 4 MoE preset is the safest bet today. Mixed mode is supported — set `PILOT_OPEN_AI_<FEATURE>_MODEL` to override per sub-feature (see "Per-feature model overrides" below).

---

## Scaleway (EU-residency default)

Recommended for any Konversio install that needs European data residency or
GDPR-clean hosting. Validated end-to-end using Gemma 4 26B-a4b-it, which delivers
exceptional tool-calling, natural Dutch and English responses, and very low MoE latency.

```sh
export PILOT_OPEN_AI_API_KEY="<scaleway secret key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.scaleway.ai"
export PILOT_OPEN_AI_MODEL="gemma-4-26b-a4b-it"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

# Embeddings — Qwen3-Embedding-8B is native 4096 dims. We request 1536 via
# the provider's dimensions parameter to fit the locked pgvector column.
# Scaleway's UI currently says this model cannot be reduced, but live API
# tests confirm first-prefix truncation plus L2 renormalization.
export PILOT_EMBEDDING_MODEL="qwen3-embedding-8b"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

For Heroku:

```sh
heroku config:set -a konversio \
  PILOT_OPEN_AI_API_KEY=... \
  PILOT_OPEN_AI_ENDPOINT=https://api.scaleway.ai \
  PILOT_OPEN_AI_MODEL=gemma-4-26b-a4b-it \
  PILOT_OPEN_AI_API_PROVIDER=openai_compatible \
  PILOT_EMBEDDING_MODEL=qwen3-embedding-8b \
  PILOT_EMBEDDING_DIMENSIONS=1536
```

---

## OpenAI (recommended for Copilot / Autopilot)

Most reliable for tool-calling and strict-JSON response schemas. Use this
preset when Copilot, Autopilot, or any Pilot sub-feature that calls tools
mid-conversation needs to work end-to-end. Validated against the Pilot V1
prompt format: `gpt-4o-mini` returns clean 3-key JSON (`reasoning`,
`content`, `reply_suggestion`) without leaking tool function names into the
response — open-source models on other providers tend to leak.

```sh
export PILOT_OPEN_AI_API_KEY="<openai api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.openai.com"
export PILOT_OPEN_AI_MODEL="gpt-4o-mini"
# Leave PILOT_OPEN_AI_API_PROVIDER unset (or set to "openai") so RubyLLM's
# model registry validates the model name.

export PILOT_EMBEDDING_MODEL="text-embedding-3-small"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

For Heroku:

```sh
heroku config:set -a konversio \
  PILOT_OPEN_AI_API_KEY=sk-... \
  PILOT_OPEN_AI_ENDPOINT=https://api.openai.com \
  PILOT_OPEN_AI_MODEL=gpt-4o-mini \
  PILOT_EMBEDDING_MODEL=text-embedding-3-small \
  PILOT_EMBEDDING_DIMENSIONS=1536
```

> **EU residency trade-off:** OpenAI processes inference outside the EU
> (US-based by default). If GDPR data residency is a hard requirement, use
> Scaleway or Nebius for the EU-resident path and override the model just for
> Copilot/Autopilot via `PILOT_OPEN_AI_COPILOT_MODEL` etc.

---

## Mistral La Plateforme

Tool calling works for simple cases; the larger models (`mistral-large-latest`)
are more reliable than `mistral-small-latest` for Copilot.

```sh
export PILOT_OPEN_AI_API_KEY="<mistral api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.mistral.ai"
export PILOT_OPEN_AI_MODEL="mistral-small-latest"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

export PILOT_EMBEDDING_MODEL="mistral-embed"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

---

## Nebius Token Factory

```sh
export PILOT_OPEN_AI_API_KEY="<nebius api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.tokenfactory.nebius.com"
export PILOT_OPEN_AI_MODEL="meta-llama/Meta-Llama-3.1-70B-Instruct"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

export PILOT_EMBEDDING_MODEL="Qwen/Qwen3-Embedding-8B"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

---

## Groq

Fast inference at low latency. Useful for Briefing where the agent is
waiting on the response in real time. Not ideal for Copilot or Autopilot
because Groq's hosted models lack robust tool-calling support.

```sh
export PILOT_OPEN_AI_API_KEY="<groq api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.groq.com/openai"
export PILOT_OPEN_AI_MODEL="llama-3.1-70b-versatile"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

# Groq does not host embedding models — point embeddings at a separate
# provider (OpenAI, Mistral, Scaleway) when using Groq for chat.
```

---

## Ollama (local / self-hosted)

For laptop development or air-gapped deployments. Ollama exposes an
OpenAI-compatible endpoint at `/v1` on its default port.

```sh
export PILOT_OPEN_AI_API_KEY="ollama"     # any non-empty value; Ollama ignores it
export PILOT_OPEN_AI_ENDPOINT="http://localhost:11434"
export PILOT_OPEN_AI_MODEL="llama3.1:8b-instruct"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

# Local embedding model (also via Ollama).
export PILOT_EMBEDDING_MODEL="nomic-embed-text"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

---

## Per-feature model overrides

Any feature can be pinned to a different model via
`PILOT_OPEN_AI_<FEATURE>_MODEL`. Useful when you want, say, a small/fast
model for translation and a stronger one for Autopilot replies:

```sh
export PILOT_OPEN_AI_MODEL="mistral-small-3.2-24b-instruct-2506"
export PILOT_OPEN_AI_TRANSLATION_MODEL="mistral-tiny"
export PILOT_OPEN_AI_BRIEFING_MODEL="mistral-large-latest"
```

The available feature keys are: `briefing`, `copilot`, `autopilot`,
`logbook`, `summary`, `csat_analysis`, `follow_up`, `rewrite`,
`label_suggestion`, `translation`, `embedding`.

---

## Verifying the configuration

After setting the env vars, restart the Rails process and confirm via the
Rails console:

```ruby
Llm::Config.api_base                # => "https://api.scaleway.ai"
Llm::Config.model_for(:briefing)    # => "mistral-small-3.2-24b-instruct-2506"
Llm::Config.model_options(:briefing)
# => { provider: "openai", model: "mistral-small-3.2-24b-instruct-2506",
#      assume_model_exists: true }
```

The Pilot onboarding wizard (section 8 of the Pilot rollout) ships a
"Test connection" button that performs the same check from the dashboard.
