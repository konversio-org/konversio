# Assistant Reasoning Tuning & Token Limits

This document describes how to configure reasoning effort and response token limits for Pilot Assistants, and details the required post-deployment steps.

## Background

The default Pilot chat model (e.g. `gemma-4-26b-a4b-it` on Scaleway) operates with **thinking/reasoning enabled by default**. When a reasoning model is active, it spends completion tokens on an internal step-by-step reasoning process before emitting the visible answer. 

Without constraints, the model's reasoning phase can consume the entire token budget, leading to high latency, increased costs, or empty responses.

To address this, we added:
1. **Per-assistant reasoning effort:** A setting (`off`, `low`, `medium`, `high`) allowing operators to tune the depth of the reasoning process.
2. **Per-assistant max output tokens:** A response token cap to ensure reasoning doesn't starve the visible answer.
3. **Model capability detection:** Automatically greys out the reasoning control in the UI if the active model does not support it.

---

## Production Deployment Step (Post-Ship)

> [!IMPORTANT]
> Immediately after deploying this change to production, the operator **MUST** set the reasoning effort and max output tokens for the default assistant (Mira) to cut down on uncontrolled reasoning costs and latency.

### Recommended Configuration for Mira:
- **Reasoning Effort:** `off` or `low` (Mira is a standard customer support bot and does not need expensive deep reasoning).
- **Max Output Tokens:** `2048` (to provide a safe buffer for both thinking and the final answer).

### Option 1: Via the Assistant Editor UI
1. Log in to the Konversio dashboard as an administrator.
2. Navigate to **Autopilot Settings** (or the Assistant list).
3. Select **Mira** and click **Edit**.
4. In the **Behavior & Configuration** section:
   - Set **Reasoning depth** to `off` (or `low` if light reasoning is desired).
   - Set **Max output tokens** to `2048`.
5. Click **Save Settings**.

### Option 2: Via Rails Console
If you have SSH or Heroku access, run:
```bash
heroku run rails console
```
Then execute:
```ruby
assistant = Pilot::Assistant.find_by!(name: 'Mira')
assistant.update!(
  config: assistant.config.merge(
    'reasoning_effort' => 'off',
    'max_tokens' => 2048
  )
)
```
This instantly applies the limit and cuts inference cost/latency on production.
