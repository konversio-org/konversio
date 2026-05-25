# EU-Sovereign Model Selection

This document captures the design rationale and empirical evidence behind
Konversio's choice of LLM provider and chat model. It is the *why* companion
to [`PILOT_PRESETS.md`](./PILOT_PRESETS.md), which is the *how* (copy-paste
env blocks for each supported provider).

If you are operating an install, start with `PILOT_PRESETS.md`. If you are
deciding which model to put in the chat slot — or evaluating a candidate
replacement — read this.

---

## Constraints

Konversio is positioned as an EU-sovereign customer-support platform.
"EU-sovereign" here means a specific, testable claim, not marketing:

1. **EU-hosted inference.** The provider runs the model on infrastructure
   located inside the EU.
2. **No US parent.** The provider's corporate parent is not subject to the
   US CLOUD Act. (Iliad Group, the parent of Scaleway, is French.)
3. **GDPR-bound by default.** No data-processing exceptions or extra-EU
   transfer mechanisms required.
4. **No silent fallback.** Pilot must never fall back to OpenAI or another
   US provider on error — failures must raise, surface the real cause, and
   stop. (See the in-repo failure handling in `Pilot::BaseTaskService` and
   the `[BACKEND_ERROR]` convention used by tools.)

These constraints rule out the entire Captain reference architecture
(`gpt-4o-mini` / `gpt-4.1-mini` on OpenAI), even though it is otherwise the
faithful design Konversio's Pilot module reconstructs.

---

## Provider: Scaleway

[Scaleway Generative APIs](https://www.scaleway.com/en/generative-apis/) is
the current default provider. It satisfies all four constraints above and
exposes an OpenAI-compatible HTTP surface, which means RubyLLM (the
underlying chat library) can talk to it with `provider: :openai` and
`assume_model_exists: true` — wired up in `lib/llm/config.rb`.

The provider is **swappable**. The slot system in `Llm::ProviderRegistry` /
`Llm::Config` was deliberately built so that chat / embedding / audio can
each point at a different OpenAI-compatible provider. Nebius and direct
OpenAI are also wired and documented in `PILOT_PRESETS.md`. None of the
business logic depends on Scaleway specifically — only on "an
OpenAI-compatible endpoint hosting a model that meets the requirements
below."

---

## Capability requirements derived from features

Pilot features have different model-capability profiles. The chat slot must
satisfy the union of these:

| Feature                  | Needs reliable tool calling? | Needs strict JSON / schema? | Needs strong multilingual? |
|--------------------------|------------------------------|------------------------------|----------------------------|
| Reply suggestion (briefing) | Yes — calls `search_documentation` to ground replies in approved FAQs | No | Yes — customer messages are not all English |
| Copilot (agent-facing)   | Yes — multiple tools (docs, conversation, contact) | Yes | Yes |
| Autopilot (customer-facing) | Yes — search + handoff tools | Yes | Yes |
| Summarization / rewrite  | No | Sometimes | Yes |

"Reliable tool calling" is the load-bearing requirement. If the model is in
`tool_choice: "auto"` mode and decides not to call the search tool when a
relevant FAQ exists, the entire grounded-reply value proposition collapses
into "a generic LLM with a polite tone." Konversio's product differentiation
depends on the model actually using its tools when appropriate.

---

## Empirical comparison (2026-05-22)

Two Scaleway-hosted models were tested head-to-head against the same
reply-suggestion flow, same prompt, same approved FAQ, same conversation.

**Test setup.** Account 1, FAQ #852 ("Where can I find information about
tax and finance?" → "You can find information about tax and finance by
visiting the [Tax & Finance](https://migrately.nl/help/tax-finance)
category."), `tool_choice` left at the library default (effectively
"auto"). Two conversations exercised: (a) the existing polluted conversation
display_id 38 (contains prior failed bot responses + transfer attempts),
and (b) a freshly created clean conversation with only the single customer
message. Adapter calls and outbound HTTP payloads were captured directly
via Faraday and `Pilot::RubyLlmToolAdapter#execute` instrumentation.

| Model | Polluted thread | Clean thread |
|---|---|---|
| `mistral-small-3.2-24b-instruct-2506` | No tool call. Reply: *"I'd be happy to help! Could you please clarify what specific information you're looking for regarding taxes and finance?"* | No tool call. Reply: *"I'd be happy to help! Could you please clarify what specific information you're looking for regarding taxes and finance?"* |
| `gemma-4-26b-a4b-it` | Tool called with query `"tax and finance information"`. Reply: *"You can find all that information in our [Tax & Finance](https://migrately.nl/help/tax-finance) category."* | Tool called with query `"Where can I find information about tax and finance?"`. Reply: *"You can find all the information you need in our Tax & Finance category here: https://migrately.nl/help/tax-finance"* |

The integration and prompt were identical across all four runs. The only
variable was the model slug in the chat slot. Mistral Small 3.2 24B
consistently skipped the available tool; Gemma 4 26B-a4b-it consistently
invoked it and grounded the reply.

### Reading the result

- The architecture is correct. Tools were emitted in the outbound payload
  in both cases; the prompt rendered the `has_search_tool` instruction
  block in both cases. The model receives everything it needs to invoke
  the tool.
- Model *size* is not the bottleneck. Gemma 4 26B-a4b-it is a Mixture of
  Experts model with ~4B active parameters per token — a much smaller
  compute footprint than Mistral's 24B dense. It still fires the tool
  reliably. The difference is in tool-calling tuning, not capacity.
- Thread state ("polluted" vs "clean") did not change the outcome for
  either model. An earlier external analysis claimed Mistral would fire
  the tool on a clean thread; direct replication contradicted that. The
  current data set should be treated as the authoritative observation
  for this configuration.

### What this does NOT prove

- It does not benchmark **multilingual reply quality** for either model.
  Both are advertised as multilingual; Gemma 3+ is trained on Dutch and
  major European languages, as is Mistral. Empirical multilingual
  evaluation against representative Migrately customer messages is open
  work.
- It does not benchmark **latency or aggregate monthly spend** at production
  load. The token prices are known, but real spend depends on request volume,
  prompt size, tool-use frequency, and average response length.
- It does not say anything about **agentic / multi-turn** tool use
  reliability. The reply-suggestion flow is single-turn (one tool call,
  then a final response). Autopilot's multi-turn behavior should be
  validated separately before relying on it in production.

---

## Pricing impact

Pricing below is from Scaleway's public Model-as-a-Service pricing page and
OpenAI's public API pricing page, checked on 2026-05-22. All prices are shown
in EUR. Scaleway publishes EUR prices directly. OpenAI publishes USD prices,
converted here using the 2026-05-22 reference rate `1 EUR = 1.1599 USD`
(`1 USD ~= 0.8621 EUR`).

| Provider | Slot | Model | Unit | Input / price | Output |
|---|---|---|---|---:|---:|
| Scaleway | Chat | `mistral-small-3.2-24b-instruct-2506` | 1M tokens | €0.15 | €0.35 |
| Scaleway | Chat | `gemma-4-26b-a4b-it` | 1M tokens | €0.25 | €0.50 |
| Scaleway | Embedding | `qwen3-embedding-8b` | 1M tokens | €0.10 | Free |
| Scaleway | Audio | `whisper-large-v3` | audio minute | €0.003 | n/a |
| OpenAI direct | Chat | `gpt-4.1-mini` | 1M tokens | ~€0.34 | ~€1.38 |
| OpenAI direct | Embedding | `text-embedding-3-small` | 1M tokens | ~€0.017 | n/a |
| OpenAI direct | Audio | `whisper-1` | audio minute | ~€0.0052 | n/a |

Provider matters. The same or similar model slug can be available through
multiple hosting providers, but pricing, data residency, rate limits, API
compatibility behavior, and operational guarantees are provider-specific.
When documenting or comparing a candidate, record both the provider and the
exact model slug.

Moving the chat slot from Mistral Small 3.2 to Gemma 4 therefore increases
unit token cost by:

- Input: +€0.10 / 1M tokens, roughly +67%.
- Output: +€0.15 / 1M tokens, roughly +43%.

For a representative briefing request of 2k input tokens and 1k output
tokens, the estimated chat cost is:

| Model | Estimated cost / call |
|---|---:|
| `mistral-small-3.2-24b-instruct-2506` | ~€0.00065 |
| `gemma-4-26b-a4b-it` | ~€0.00100 |

That is an incremental cost of roughly €0.00035 per briefing call:

| Monthly briefing calls | Incremental monthly cost |
|---:|---:|
| 10,000 | ~€3.50 |
| 100,000 | ~€35 |
| 1,000,000 | ~€350 |

The product trade-off is deliberate: Mistral is cheaper per token, but in
the reproduced test it returned an ungrounded clarification instead of
calling the available FAQ search tool. Gemma costs more per token, but it
grounded the reply in the approved FAQ. For support workflows, correctness
and tool-call reliability are the load-bearing requirements; the pricing
uplift is acceptable unless production traffic proves otherwise.

### OpenAI direct versus Scaleway

For current Captain-equivalent comparisons, use the `all-openai` preset as
the baseline and `all-scaleway` as the EU-sovereign replacement:

| Slot | OpenAI direct baseline | Scaleway EU replacement | EUR pricing impact |
|---|---|---|---|
| Chat | `gpt-4.1-mini` | `gemma-4-26b-a4b-it` | Scaleway is cheaper: ~€0.25/€0.50 versus ~€0.34/€1.38 per 1M input/output tokens. |
| Embedding | `text-embedding-3-small` | `qwen3-embedding-8b` | Scaleway is more expensive per embedding token: €0.10 versus ~€0.017 per 1M input tokens. Re-embedding cost must be planned separately. Both produce 1536-dim vectors (Scaleway via MRL-aware truncation), so the pgvector column does not need to change. |
| Audio | `whisper-1` | `whisper-large-v3` | Scaleway is cheaper: €0.003 versus ~€0.0052 per audio minute. |

In EUR, Scaleway Gemma remains cheaper than OpenAI direct `gpt-4.1-mini`
even though it is more expensive than Scaleway Mistral Small.

| Provider | Model | Input / 1M | Output / 1M |
|---|---|---:|---:|
| OpenAI direct | `gpt-4.1-mini` | ~€0.34 | ~€1.38 |
| Scaleway | `gemma-4-26b-a4b-it` | €0.25 | €0.50 |
| Scaleway | `mistral-small-3.2-24b-instruct-2506` | €0.15 | €0.35 |

For the same representative briefing request of 2k input tokens and 1k
output tokens:

| Provider | Model | Estimated cost / call |
|---|---|---:|
| OpenAI direct | `gpt-4.1-mini` | ~€0.00207 |
| Scaleway | `gemma-4-26b-a4b-it` | ~€0.00100 |
| Scaleway | `mistral-small-3.2-24b-instruct-2506` | ~€0.00065 |

So moving from OpenAI direct `gpt-4.1-mini` to Scaleway
`gemma-4-26b-a4b-it` is not a price hike. It is roughly a 50% chat-token
cost reduction on this representative request, while also satisfying the
EU-sovereign provider constraints. The real trade-off is not cost; it is
whether the chosen EU-hosted model preserves the tool-calling reliability
that made the OpenAI baseline viable.

---

## How the comparison was run

The comparison was driven by a single Rails runner script that exercised
the real `Pilot::ReplySuggestionService` against the real Scaleway
endpoint and captured every interesting boundary along the way. The script
lived in `tmp/` (gitignored — see `.gitignore`); its essential pieces are
reproduced below so the procedure is preserved even though the file is
not.

### 1. Swap the chat model for the duration of the run

The chat slot model is resolved at request time via
`Llm::Config.model_for(:default)`. For a one-off test, the cleanest swap
is to redefine that method on the singleton — no env vars, no DB writes,
no container restarts, no leakage between runs:

```ruby
TARGET_MODEL = 'gemma-4-26b-a4b-it'   # or any slug returned by /v1/models
original_model_for = Llm::Config.method(:model_for)
Llm::Config.define_singleton_method(:model_for) do |feature|
  feature.to_s == 'default' ? TARGET_MODEL : original_model_for.call(feature)
end
```

The rest of the resolution chain (provider, endpoint, API key, embedding
model, instrumentation) is untouched — only the chat model string changes.

### 2. Hook the adapter to know whether the tool actually fired

The LLM's response can claim anything; the only ground truth that the
tool ran is that `Pilot::RubyLlmToolAdapter#execute` was called on the
Ruby side. `prepend` a module that records each invocation:

```ruby
tool_calls = []
Pilot::RubyLlmToolAdapter.prepend(Module.new do
  define_method(:execute) do |**params|
    result = super(**params)
    tool_calls << { params: params, result_preview: result.to_s[0, 300] }
    result
  end
end)
```

### 3. Hook the HTTP layer to rule out integration bugs

To prove the tool definition actually reached Scaleway (and was not
stripped by RubyLLM or by the OpenAI-compat shim), wrap Faraday's `post`
and capture both the outbound request body and the parsed response:

```ruby
http_capture = { payload: nil, response_summary: nil }
Faraday::Connection.prepend(Module.new do
  define_method(:post) do |*args, &block|
    response = super(*args, &block)
    # extract response.env.url; if it's the chat endpoint, parse
    # response.env.request_body for { model, tools, messages, ... }
    # and parse response.body for finish_reason / tool_calls / content
    response
  end
end)
```

This is what confirmed the tool definition was present in every request —
ruling out "the integration silently dropped the tool" as a candidate
explanation for Mistral's miss.

### 4. Fixtures

- **Account 1**, features `pilot` and `pilot_tasks` enabled
- **FAQ 852**: approved, embedded, with a distinctive answer containing
  `migrately.nl/help/tax-finance` so grounded-ness can be detected by a
  cheap substring check on the final reply
- **Conversation 38**: a real, polluted conversation — prior bot
  failures, a transfer message, last incoming message identical to the
  FAQ question
- **A fresh conversation**, created at the top of the script, with one
  and only one incoming message matching the FAQ question, to isolate
  model behavior from any history effects

Both conversations are exercised back-to-back in the same script run, so
the comparison is genuinely side-by-side — no chance of config drift
between models.

### 5. Signals recorded per (model, conversation) pair

- `model` and `tools.size` in the outbound Scaleway payload
- `finish_reason`, `tool_calls`, and `content` from the first Scaleway
  response (the model's pre-tool-execution turn)
- Every `Pilot::RubyLlmToolAdapter#execute` call observed — params and
  result preview
- The final suggested reply (`response[:message]`)
- A coarse grounded-ness boolean (substring match against `migrately.nl`,
  `Tax & Finance`, `category`)
- Token usage; any error string

### 6. Re-running

```sh
docker compose exec -T rails bundle exec rails runner /app/tmp/verify_gemma.rb
```

If `tmp/verify_gemma.rb` is missing (gitignored), recreate it from the
snippets above. Total script length on 2026-05-22 was under 100 lines.
Reading the printed output is the verification — no test framework
involved, intentionally.

---

## Current recommendation

For the full EU-sovereign preset, use `all-scaleway`:

```
Chat:       scaleway · gemma-4-26b-a4b-it
Embeddings: scaleway · qwen3-embedding-8b
Audio:      scaleway · whisper-large-v3
```

Embedding sits on `qwen3-embedding-8b` (Scaleway, EU-hosted by Iliad
Group, strong multilingual + Dutch performance, MRL-aware truncation).
Konversio standardizes on a 1536-dim pgvector column installation-wide
so OpenAI `text-embedding-3-small` and Scaleway `qwen3-embedding-8b`
remain interchangeable in the same column without a schema rebuild on
every provider swap. Do not swap the embedding model without re-embedding
every `pilot_assistant_responses` row — query-time and seed-time
embeddings must come from the same model for cosine similarity to mean
anything.

### Why not `bge-multilingual-gemma2`?

It was the prior Scaleway embedding choice. Removed deliberately because:

- **Fixed 3584-dim output, no truncation knob.** The BAAI model card
  declares no Matryoshka Representation Learning, and Scaleway's
  endpoint locks the dimensions slider — you cannot request 1536 from
  it. That breaks the cross-provider interop story (would require a
  schema rebuild every time you flip OpenAI ↔ Scaleway).
- **`vector(3584)` is above pgvector's 2,000-dim ivfflat/hnsw cap.**
  Sequential scan only; doesn't scale beyond FAQ-size corpora.
- **Qwen3-Embedding-8B covers the same need.** Strong multilingual
  performance, EU-hosted, MRL-aware truncation to 1536 (verified
  empirically: prefix slice + L2 renorm on Scaleway's endpoint).

If a future installation has a hard requirement for `bge-multilingual-gemma2`
specifically, the per-model column-rebuild flow tracked in
[konversio-org/konversio#12](https://github.com/konversio-org/konversio/issues/12)
must ship first.

Operational env blocks are in [`PILOT_PRESETS.md`](./PILOT_PRESETS.md).

---

## Methodology for evaluating a new candidate model

When considering a replacement for the chat slot:

1. **Confirm it satisfies the four constraints** in the section above
   (EU-hosted, no US parent, GDPR by default, no silent-fallback need).
2. **Confirm Scaleway (or the configured provider) actually serves it.**
   Hit `GET <endpoint>/v1/models` with the slot's API key and check the
   returned list. Slugs change.
3. **Run the side-by-side script.** A reproducible verification pattern
   is in `tmp/verify_gemma.rb` (gitignored — recreate as needed). It:
   - overrides `Llm::Config.model_for(:default)` to the candidate model
     for the duration of the run, without touching DB config
   - exercises both a polluted thread (existing conversation display_id
     38, or any active conversation with prior bot responses) and a
     freshly created clean conversation
   - hooks `Pilot::RubyLlmToolAdapter#execute` to record whether the
     tool fired, what query was sent, and what was returned
   - hooks `Faraday::Connection#post` to capture the outbound payload
     to the provider, confirming the tool definition was actually sent
   - prints the final suggested reply and a coarse "grounded?" check
     against the known FAQ answer
4. **Evaluate multilingual reply quality on representative messages.**
   Pull a sample of real Dutch / Polish / Romanian / Ukrainian customer
   messages from `messages` and run the briefing flow against each.
   Read the replies, not just the tool-fire rate.
5. **Spot-check latency and token cost** at a few representative request
   sizes. The slot is shared by Briefing, Copilot, and Autopilot, so a
   regression here affects all three.
6. **Only after the above passes**: update the chat-slot config in
   `/super_admin/llm_settings` (or via the env block in
   `PILOT_PRESETS.md`) and re-run the existing automated specs:
   ```
   docker compose exec -T rails bundle exec rspec spec/services/pilot \
     spec/services/custom/pilot
   ```

Document any deviation from the recommendation above in
`CHANGELOG.md` under the relevant version.

---

## Related decisions and constraints

- The fork-strategy doctrine: [`FORK_STRATEGY.md`](./FORK_STRATEGY.md).
  Pilot is a clean-room reconstruction of Captain's behavior; do not
  resurrect protected expression from git history when evaluating
  models or making changes here.
- Captain (the upstream reference implementation) is best treated as a
  `gpt-4.1-mini` baseline for current comparisons. This is OpenAI's mini
  tier — i.e. roughly the same product class as Mistral Small 3.2 and
  Gemma 4 26B-a4b. The reason Captain's auto-mode tool calling works
  reliably and Mistral's does not is post-training on tool use, not raw
  model capacity.
- The slot architecture (chat / embedding / audio independently
  configurable per provider) is the structural reason a model swap is
  a config change rather than a code change. Preserve this property
  when extending Pilot.
