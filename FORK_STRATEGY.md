# Konversio Fork & Reimplementation Strategy

This document explains how Konversio came to exist legally and how the Pilot AI
layer was built without reusing protected expression from Chatwoot's proprietary
Captain AI feature. It exists so that any contributor, user, or lawyer can
verify the project's provenance against the git history.

---

## The Fork

Konversio is a **hard fork** of Chatwoot v4.13.0, performed in May 2026 and
maintained with **no upstream tracking**. The fork preserves Chatwoot's MIT
license and copyright notice; the new project is also fully MIT, self-hosted
only, with no SaaS tier.

### What was kept

Everything under `app/`, `lib/`, `spec/`, and the other top-level directories
that Chatwoot publishes under the MIT license. MIT explicitly grants the right
to "use, copy, modify, merge, publish, distribute, sublicense" — provided the
copyright notice is preserved, which it is, in `LICENSE`.

### What was deleted

The entire `enterprise/` directory, which contained Chatwoot's proprietary
("Chatwoot Enterprise Edition License") features — including Captain AI, SLA,
audit logs, custom roles, and other commercial add-ons. Roughly 55,000 lines
removed in a single commit (`461d6ab36`). None of this code survives in the
Konversio tree, and none of it was used as a reference when building Pilot
(see below).

### Why fork at all

To rebuild the AI layer as MIT-licensed, EU-jurisdiction, self-hosted only.
The original Captain feature is paid, US-hosted, and OpenAI-backed. Konversio's
target is the opposite: free, self-hosted, with EU-sovereign LLM providers
(Scaleway, Qwen3) so customer conversations stay inside EU jurisdiction.

---

## The Reimplementation (Captain → Pilot)

Pilot is Konversio's AI layer. It does broadly the same things Captain does
(answer FAQs, ingest documents, run scenarios, suggest replies, hand
conversations back to humans), but it shares no source code with Captain.

The implementation followed a **three-phase clean-room methodology**, executed
by three separate AI coding-agent sessions with explicit walls between them.
This is the same legal pattern Compaq used to reimplement IBM's BIOS in the
1980s — separation of observation from implementation, mediated by a written
specification — strengthened by the fact that no agent in this project ever
read Captain's source code.

### Phase 1 — Blind Purge

One AI agent session was tasked solely with deleting the `enterprise/`
directory. The agent was explicitly instructed **not to read the contents** of
any file under `enterprise/captain/*` — only to remove the directory. In
practice this meant the agent used directory-level removal commands; no `cat`,
`Read`, or content-inspecting tool calls were issued against Captain's source.
Captain's source expression never entered that agent's analytical context.

Commits: `ed3be41ef`, `461d6ab36`.

### Phase 2a — Behavioral Specification

A separate AI agent session was used to write the `pilot-full` OpenSpec. Its
only inputs were:

1. Behavioral observation of Captain as a **running product**, accessed by the
   project owner as an ordinary end-user customer of Chatwoot.
2. Descriptions of intended functionality.

This agent never read Captain's source either — only its observable behavior
through the user interface. The resulting OpenSpec captures *what* the feature
does (FAQs, document ingestion, scenarios, reply suggestions, handover) but
not *how* Captain implements it.

This matters legally because copyright protects **expression**, not **ideas or
functionality**. "Has an FAQ feature" is not copyrightable. The spec lives
entirely in the unprotectable layer.

### Phase 2b — Spec-Only Build

A third AI agent session (Claude, working in this repository) implemented
Pilot's backend. Its working tree had `enterprise/` already removed; its only
input besides the existing Konversio codebase was the OpenSpec from Phase 2a.
The agent had no access to Captain's source expression at any point during
implementation.

Resulting files:

- `app/models/pilot/*` (Assistant, Document, Scenario, etc.)
- `app/services/pilot/*` (including `Pilot::AutopilotService`, `Pilot::HandoverEvaluator`)
- `app/jobs/pilot/*`
- `lib/pilot/*` (prompts, tools)

Built on the [`ai-agents`](https://github.com/chatwoot/ai-agents) SDK with
multi-provider LLM routing for EU-sovereign deployment.

Initial commit: `8bcabe45f`. Further development under the `purge-captain`
branch.

### Why this is stronger than the textbook Chinese Wall

Classical clean-room methodology (Compaq vs. IBM, 1982) allowed the "dirty"
team to **read** the original source as long as they only emitted a functional
spec. Konversio's approach is stricter: the dirty team only ever saw the
running product, never the source. No human or AI session that wrote a line
of Pilot code had Captain's source expression in its working context.

### One honest asterisk

Claude (and other LLMs used) were trained on public GitHub data, which
includes Chatwoot's repository — including the `enterprise/` directory, which
is public source despite being under a stricter license. This is the same
incidental training exposure that exists for every LLM and every codebase on
GitHub. Copyright requires substantial similarity in the **output**, not
absence of training exposure; Pilot's code is not substantially similar to
Captain's code, which can be verified directly (see "How to audit" below).

---

## The MIT-Fork Half (UI shell and controllers)

A portion of the original Captain feature lived not in `enterprise/` but in
Chatwoot's MIT-licensed core: the Vue frontend (`app/javascript/dashboard/.../captain/*`)
and the HTTP controllers (`app/controllers/api/v1/accounts/captain/*`).

These were handled differently from the AI backend. Because they are MIT, they
can be legitimately forked, modified, and redistributed — which is what the
MIT license is for. Some of these files were cherry-picked from upstream
Chatwoot (e.g. `faf45ef8b`) and then renamed Captain → Pilot in the
`purge-captain` branch (commits `58ecfd852`, `b2213840f`).

This is **not** a clean-room reimplementation — it's an ordinary MIT fork
with rename. It doesn't need to be clean-room, because the MIT grant
authorizes exactly this. Attribution is preserved in `LICENSE`.

---

## Rules Going Forward

These rules exist to preserve the clean-room defense over time. Any
contributor (human or AI) extending Pilot must follow them.

1. **Do not resurrect deleted files from git history.** `enterprise/captain/*`
   was deleted in `461d6ab36`; treat it as if it never existed. Do not run
   `git show 461d6ab36^:enterprise/captain/...` to "see how Captain did it"
   when extending Pilot. This is the single rule that keeps the Chinese Wall
   intact.
2. **New Pilot features follow the same methodology.** Behavior is observed
   or specified; implementation is built from the spec; the implementer does
   not read protected source. This applies whether the work is done by a human
   or an AI agent.
3. **Do not feed `enterprise/captain/*` source to any AI tool.** Including
   indirectly — e.g. don't paste it into a Claude session even "just to ask
   questions about it."
4. **The UI shell remains MIT-fork territory.** Files under
   `app/javascript/dashboard/.../pilot/*` and `app/controllers/.../pilot/*`
   can continue to be improved by cherry-picking from upstream Chatwoot MIT
   and renaming, as long as the cherry-picked source is MIT-licensed.
5. **Attribution stays in `LICENSE`.** Chatwoot's copyright line stays
   regardless of how much Konversio diverges. MIT requires it; honesty also
   requires it.

---

## How to audit

Anyone who wants to verify that Pilot does not contain protected expression
from Captain can do so directly:

```bash
# Extract the deleted Captain source from git history into a temp location
git show 461d6ab36^:enterprise/app/models/captain/assistant.rb > /tmp/captain_assistant.rb
git show 461d6ab36^:enterprise/lib/captain/prompts/  # etc.

# Diff against Pilot's equivalent files
diff /tmp/captain_assistant.rb app/models/pilot/assistant.rb

# Or grep Pilot source for distinctive Captain identifiers / prompt strings
grep -r "<distinctive captain string>" app/models/pilot/ app/services/pilot/ lib/pilot/
```

The legal test is substantial similarity in expression, not the existence of
shared functionality. Shared functionality is expected — both projects do
broadly the same job, by design. Shared *expression* (identifier names,
prompt wording, schema field names, method signatures, comments) would be
evidence of copying.

---

## Plain-language summary

Chatwoot has a free part (MIT) and a paid part (proprietary, including its
"Captain" AI). Konversio took the free part legally, deleted the paid part
without reading it, and built its own AI ("Pilot") from a spec written by
observing how Captain behaves as a user — not by looking at Captain's source.
The whole result is free, open-source, MIT-licensed, self-hosted, with
EU-based AI providers. The Chatwoot copyright notice stays in the LICENSE
file as credit and as legal requirement.
