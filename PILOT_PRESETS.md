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

> **Note:** Pilot does NOT read `CAPTAIN_*` environment variables. If your
> install previously ran the Captain enterprise module, the `CAPTAIN_*` keys
> are inert from Pilot's perspective.

---

## Scaleway (EU-residency default)

Recommended for any Konversio install that needs European data residency or
GDPR-clean hosting. Validated end-to-end at ~0.5 s round-trip on Mistral
Small 3.2 24B with fluent Dutch responses.

```sh
export PILOT_OPEN_AI_API_KEY="<scaleway secret key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.scaleway.ai"
export PILOT_OPEN_AI_MODEL="mistral-small-3.2-24b-instruct-2506"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

# Embeddings — Scaleway hosts BGE multilingual at 768 dims natively; we ask
# the server to upscale/truncate to 1536 to fit the existing pgvector column.
export PILOT_EMBEDDING_MODEL="bge-multilingual-gemma2"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

For Heroku:

```sh
heroku config:set -a konversio \
  PILOT_OPEN_AI_API_KEY=... \
  PILOT_OPEN_AI_ENDPOINT=https://api.scaleway.ai \
  PILOT_OPEN_AI_MODEL=mistral-small-3.2-24b-instruct-2506 \
  PILOT_OPEN_AI_API_PROVIDER=openai_compatible \
  PILOT_EMBEDDING_MODEL=bge-multilingual-gemma2 \
  PILOT_EMBEDDING_DIMENSIONS=1536
```

---

## Mistral La Plateforme

```sh
export PILOT_OPEN_AI_API_KEY="<mistral api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.mistral.ai"
export PILOT_OPEN_AI_MODEL="mistral-small-latest"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

export PILOT_EMBEDDING_MODEL="mistral-embed"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

---

## Nebius AI Studio

```sh
export PILOT_OPEN_AI_API_KEY="<nebius api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.studio.nebius.ai"
export PILOT_OPEN_AI_MODEL="meta-llama/Meta-Llama-3.1-70B-Instruct"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

export PILOT_EMBEDDING_MODEL="BAAI/bge-en-icl"
export PILOT_EMBEDDING_DIMENSIONS="1536"
```

---

## Groq

Fast inference at low latency. Useful for Briefing and Copilot where the
agent is waiting on the response in real time. Not ideal for Autopilot
because Groq's models lack robust tool-calling support.

```sh
export PILOT_OPEN_AI_API_KEY="<groq api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.groq.com/openai"
export PILOT_OPEN_AI_MODEL="llama-3.1-70b-versatile"
export PILOT_OPEN_AI_API_PROVIDER="openai_compatible"

# Groq does not host embedding models — point embeddings at a separate
# provider (OpenAI, Mistral, Scaleway) when using Groq for chat.
```

---

## OpenAI

```sh
export PILOT_OPEN_AI_API_KEY="<openai api key>"
export PILOT_OPEN_AI_ENDPOINT="https://api.openai.com"
export PILOT_OPEN_AI_MODEL="gpt-4o-mini"
# Leave PILOT_OPEN_AI_API_PROVIDER unset (or set to "openai") so RubyLLM's
# model registry validates the model name.

export PILOT_EMBEDDING_MODEL="text-embedding-3-small"
export PILOT_EMBEDDING_DIMENSIONS="1536"
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
