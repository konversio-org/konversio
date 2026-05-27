# Pilot FAQ Generation — Prompting Approach

## Preamble

Pilot (Konversio's AI assistant) builds an assistant's knowledge base by turning
ingested **documents** (crawled web pages, uploaded PDFs) into **FAQ
question/answer pairs**. Those pairs are queued for human review, embedded for
vector retrieval, and then used to answer end-customer questions (Autopilot) and
assist agents (Copilot).

This document describes the prompting approach behind that generation step: what
it is for, the design goals, the prompt itself and the rationale for each rule,
the constraints it must respect, how we tested it, and what remains open.

It exists because a reviewer hit a concrete failure: a generated FAQ titled
*"Is there medical assistance available during the application process?"* — with
no indication of **which** process. Lifted out of its source document into a
review list, a search index, or a bot answer, "the application process" has no
referent. That single observation drove the work recorded here.

## Where it is used

- **Entry point:** `Pilot::DocumentResponseBuilderJob` (`app/jobs/pilot/document_response_builder_job.rb`).
- **Input:** a `Pilot::Document` with populated `content` (plus its `name`/title).
- **Output:** one `Pilot::AssistantResponse` row per pair, `status: pending`,
  surfaced in the **Pending FAQs** review UI (Autopilot → FAQs).
- **Downstream:** an `after_commit` hook enqueues `Pilot::UpdateEmbeddingJob`,
  which embeds each approved/pending pair for similarity search. Retrieval then
  feeds Autopilot answers and Copilot suggestions.
- **Dedup:** `Custom::Pilot::FaqMiningDeduper` filters near-duplicates against the
  assistant's existing corpus (cosine distance threshold).

The model and provider are resolved per-feature via `Llm::Config` (multi-provider;
currently Scaleway, an EU-sovereign OpenAI-compatible endpoint).

## Goals

1. **Self-contained questions.** Every question must stand on its own, outside
   the source document. No dangling references ("the process", "this form").
2. **Source-language fidelity.** Output stays in the language of the source
   content. No silent translation into an operator/account language.
3. **Extraction quality.** Capture substantive content exhaustively; ignore page
   chrome; never emit "go look elsewhere" FAQs; preserve concrete specifics
   (amounts, IDs, steps, limits).
4. **Robust structure.** Valid JSON in a fixed shape, enforced at the API layer
   where the provider supports it.
5. **Multi-tenant safety.** The prompt serves every account and domain, so it
   must be entirely domain-agnostic and language-agnostic.

## The approach

### System prompt

The prompt lives as `SYSTEM_PROMPT` in `Pilot::DocumentResponseBuilderJob`:

```
You are a content writer specializing in creating FAQ sections from source documents.

You will be given a document title and the document content. The title is context to help you identify the subject. Use it only to anchor questions — never treat the title as a fact to repeat in answers.

## Requirements
- Extract ALL substantive information from the content into question/answer pairs. This is exhaustive extraction, not a summary.
- Ignore non-informational page furniture (navigation, menus, headers/footers, structural boilerplate). Draw only from real subject matter.
- Base answers strictly on the provided content. Do NOT invent facts.
- Write every question and answer in the same language as the document content. Do NOT translate.
- Preserve concrete specifics: steps, examples, identifiers, numeric limits, and enumerated items.
- Drop any pair whose only value is deferring elsewhere (e.g. "see another page", "contact someone"). Every answer must fully answer its own question.
- Return valid JSON with this exact structure:

```json
{ "faqs": [ { "question": "...", "answer": "..." } ] }
```

## Self-contained questions (important)
- Each question must be fully understandable on its own, with no access to the source document.
- Name the actual subject explicitly. Do NOT lean on context-dependent references — pronouns, demonstratives, or vague pointers whose referent is clear only from the source.
- When the body text is ambiguous about what it refers to, use the provided title to make the subject explicit in the question.

## Guidelines
- Questions should sound natural ("What is...?", "How do I...?").
- Answers should be complete and self-contained.
- Generate between 1 and 25 FAQ pairs depending on content size.
- If no qualifying content exists, return { "faqs": [] }.
- Always return valid JSON.
```

### Rule-by-rule rationale

| Rule | Why |
|---|---|
| **Self-contained questions** + named subject | The core fix. A question gets pulled away from its source into lists/search/answers, so its referent must be inside the question itself. |
| **Title context, injected separately** | The model is given the document title to anchor an ambiguous subject — but told not to parrot the title as a fact. |
| **Same-language, no translation** | FAQs surface to the same audience that reads the source; translating into an operator language both mismatches that audience and risks corrupting exact details (amounts, official terms). |
| **Ignore page furniture** | Crawled pages carry nav/menus/footers; without this rule those become junk FAQs. |
| **Anti-deflection** | A FAQ whose answer just says "see another page" is worse than none — it answers nothing. |
| **Preserve specifics** | Summary-style answers that drop numbers/IDs/steps are useless for support. |
| **Empty-set fallback + fixed JSON shape** | The parser depends on `{ "faqs": [...] }`; an explicit empty fallback avoids garbage on no-content pages. |

### Title injection (code)

The job passes both the title and the body to the model:

```ruby
chat.ask("Document title: #{document.name}\n\nDocument content:\n#{document.content}")
```

### JSON mode (code)

Where the provider supports it, JSON validity is enforced at the API layer rather
than only requested in the prompt; `sanitize_json` remains as a fallback:

```ruby
chat.with_params(response_format: { type: 'json_object' })
```

This was verified against the live provider (Scaleway / `gemma-4-26b`): responses
parse without the sanitizer.

## Constraints

- **Domain-agnostic.** The prompt runs for every tenant. No subject-matter
  vocabulary or examples may be baked in (no immigration/legal/industry nouns).
  Illustrative anti-examples use grammatical categories ("pronouns, demonstratives,
  vague pointers"), never domain words.
- **Language-agnostic.** The prompt is authored in English but must work for any
  source language. The self-containment rule is expressed as a grammatical
  *category*, so it generalises (e.g. it catches Dutch *het/dit/dat* equally),
  and output language follows the source, not the prompt.
- **Fixed output contract.** `{ "faqs": [ { "question", "answer" } ] }`; the
  persistence layer depends on this shape.
- **Original engineering.** The prompt is authored from the observed failure
  mode and first-principles FAQ-quality requirements for this product.

## Testing methodology

The headline metric is **% self-contained questions**, scored by a blind judge.

### Controlled generation

To remove model/time confounds, both prompts were run **fresh on the same source
documents with the same model** (`gemma-4-26b`):

- **OLD system:** previous prompt, content-only input, no JSON mode.
- **NEW system:** current prompt, title+content input, JSON mode.

### Blind self-containment judge

Each generated question is shown **alone, with no source document**, to an
LLM-judge that returns a yes/no verdict on whether the question is understandable
on its own. The same judge scores both systems, so it is apples-to-apples.

### Eval set (10 docs)

- **Improvement set (5):** documents whose existing questions contained dangling
  references — where we expected a gain.
- **Control set (5):** documents whose questions were already clean — a
  **regression check**, to confirm the new prompt does not degrade good output.

### Drop classification (follow-up)

When the new prompt produced fewer questions on some docs, a second judge — this
one **with the source** — classified each dropped question as: `covered`,
`chrome`, `deflection`, `missing_substantive`, or `unsupported`. The
`missing_substantive` items (the only true regression category) were printed
verbatim for human verification rather than trusted blindly.

### Known measurement limitations

- **n = 10** documents; a demonstration-grade, not population-grade, sample.
- The judge is the **same model family** as the generator — imperfect, though
  consistent across both systems.
- **Generation is non-deterministic.** Raw question *counts* vary run-to-run, so
  conclusions rely on **rates** (self-containment %), which are far more stable,
  not on absolute counts.
- Answer **completeness/accuracy** was only spot-checked, not scored at scale.

## Results

**Self-containment rate (blind judge):**

| Set | OLD | NEW |
|---|---|---|
| Improvement (5 docs) | 78.8% (41/52) | **94.4%** (51/54) |
| Control (5 docs) | 92.0% (81/88) | **98.5%** (67/68) |
| **All (10 docs)** | **87.1%** (122/140) | **96.7%** (118/122) |

Dangling questions fell from **12.9% → 3.3%** (~75% reduction). On several docs
the new prompt improved self-containment *while producing more questions* — so
the gain is not an artifact of emitting fewer, safer questions.

**Regression check (drop classification):** No demonstrated loss of substantive
coverage. On the two docs where counts fell, the drop was explained by:

- **Chrome consolidation** — a stats page whose dropped questions were 92%
  already-covered/consolidated by the new set, with the source heavy in nav
  boilerplate; only 2 trivial meta-misses.
- **Run variance + decomposition** — an index/hub page where the "drop" did not
  even reproduce across runs (the new prompt produced *more* on a re-run), and
  the flagged items were broad umbrella questions the new prompt decomposed into
  granular ones rather than losing.

## Examples (before → after)

**The originating case (English, asylum source):**
- OLD: *"Is there medical assistance available during **the application process**?"*
- NEW: *"…during **the asylum process in the Netherlands**?"* — and the single
  bloated card was split into atomic, individually self-contained FAQs (purpose /
  location / mandatory / fee).

**Source-language fidelity (Dutch source):**
- Source body: *"Tijdens **het proces** krijgt u een gratis medisch onderzoek…"*
- NEW: *"Wordt er tijdens **de aanvraag van een verblijfsvergunning in Nederland**
  een medisch onderzoek aangeboden?"* — self-contained **and** in Dutch, produced
  from an English prompt.

**Specificity from content (English source):**
- OLD: *"How can using Migrately.nl help reduce delays in **the application
  process**?"*
- NEW: *"What is the typical processing time for a Dutch **Family Reunification
  (Form 7018)** application?"*

## Open items / future work

- **Hub vs. leaf pages (ingestion-layer).** Index/hub pages (e.g. a "Residence in
  the Netherlands" landing page) are link-lists, not FAQ material — but they are
  essential **crawl seeds** for discovering the leaf pages that *are* FAQ-worthy.
  The right handling is at ingestion: classify hub vs. leaf, route hub pages to
  **link discovery** (extract URLs, enqueue children) and **skip FAQ generation**
  on them; route leaf pages to the FAQ generator. This is not a prompt change.
- **Title vs. slug anchoring.** Title injection only helps when `document.name` is
  page-specific. For sources whose pages share a generic site title, the subject
  lives in the URL slug — injecting a cleaned slug as additional context would
  anchor better.
- **Re-embedding.** Embeddings were migrated to a locked 1536 dimension; existing
  rows need re-embedding before retrieval is fully functional.
- **Regenerating existing FAQs.** Already-generated pending FAQs were produced
  with the old prompt; they do not improve retroactively. Re-syncing a document
  regenerates cleanly under the new prompt (it replaces that document's pairs).
- **Larger, scored eval.** A population-grade eval that also scores answer
  completeness/accuracy would turn the demonstration-grade result above into a
  measured guarantee.

## AGY: Feedback & Recommendations for Further Improvement

- **AGY: API-enforced JSON Mode in Conversation Mining (`FaqMiningService`).** While `DocumentResponseBuilderJob` enforces JSON output at the API layer with `chat.with_params(response_format: { type: 'json_object' })`, the `FaqMiningService` relies purely on text instruction and regex-based sanitization. Adding the JSON format option to the conversation LLM call will prevent parsing issues and drop-offs.
- **AGY: Align Conversation Mining Prompt with Document Quality Rules.** The conversation mining prompt is currently very brief compared to the document builder. It should be augmented to explicitly cover pronoun/demonstrative resolution (crucial in chat logs where subjects are heavily context-dependent) and source-language preservation to avoid silent English translation of foreign-language customer chats.
- **AGY: Smart/Non-Destructive Sync for Documents.** The current document builder destroys all existing responses via `document.responses.destroy_all`. This deletes manual improvements or approvals/rejections made by human agents. Updating the logic to target only unedited, pending responses (e.g. `document.responses.where(status: :pending, edited: false).destroy_all`) or performing a similarity-based diff merge will prevent work loss.
- **AGY: Assistant/Brand/Product Context Injection.** Injected documents and transcripts do not reference the assistant's name or brand. Supplying `"The name of the company/product is: [Assistant Name]"` in the system prompt gives the LLM context to ground ambiguous pronouns (e.g., changing "How do I request a refund?" to "How do I request a refund from [Brand]?").
- **AGY: Granular Deduplication Comparison.** The `FaqMiningDeduper` concatenates `"<question>: <answer>"` and compares vector distances. While efficient, this may lead to false duplicate detection when questions match but answers have updated or refined facts. Comparing questions and answers separately, or using matching logic to detect updates instead of simple exclusion, would improve content freshness.

## CODEX: Feedback & Recommendations for Further Improvement

- **CODEX: Add a faithfulness score to the eval.** The current eval is strong for self-contained questions, but the next measured risk is answer correctness. A larger run should score whether answers preserve source facts exactly, especially prices, dates, form numbers, eligibility rules, policy exceptions, and enumerated steps.
- **CODEX: Add source-span traceability before persistence.** During generation or validation, each FAQ should be traceable to the source sentence or paragraph that supports it. That source span does not have to be shown in the UI, but it gives the system a practical way to reject unsupported answers and debug bad generations.
- **CODEX: Add a post-generation repair gate.** A lightweight validator can catch issues the prompt will not eliminate reliably: dangling referents, redirect-only answers, empty or malformed answers, unsupported claims, language mismatch, and excessive overlap with already-generated pairs. Repair or drop should happen before rows are created.
- **CODEX: Turn open items into implementation-sized tickets.** The current future-work section is directionally right; the next step is to split it into discrete changes with acceptance criteria: hub/leaf classification, slug-derived subject anchoring, safe regeneration behavior, larger eval fixtures, and conversation-mining prompt parity.
