# Vendor of chatwoot/ai-agents PR #66 "feat: add RubyLLM provider passthrough"
# (https://github.com/chatwoot/ai-agents/pull/66).
#
# The Agents SDK calls `RubyLLM::Chat.new(model: agent.model)` without
# specifying `provider:` or `assume_model_exists:`. RubyLLM then demands the
# model exist in its in-memory registry — but Scaleway / Nebius / Ollama /
# Azure-deployment IDs aren't in that registry, so every Autopilot inference
# dies with `ModelNotFoundError` before any HTTP call is attempted.
#
# Until the PR lands and we bump the gem, this prepend defaults
# `provider: :openai, assume_model_exists: true` whenever a caller passes only
# `model:` with no provider. RubyLLM treats every slot in our config as an
# OpenAI-compatible endpoint anyway (see `Llm::Config.configure_ruby_llm`),
# so the default matches reality.
#
# This is NOT a silent fallback. The HTTP call still goes to the configured
# `openai_api_base` (Scaleway, Nebius, etc.). If the upstream provider doesn't
# serve the model ID, the real API error propagates verbatim.
#
# DELETE this file once chatwoot/ai-agents > 0.9.1 with PR #66 is in our
# Gemfile.lock and `Agents::Agent.new` / `Agents::Runner#run` thread the kwargs
# through natively.

module Konversio
  module RubyLLMChatProviderPassthrough
    def initialize(model: nil, provider: nil, assume_model_exists: false, context: nil)
      if model && provider.nil? && !assume_model_exists
        provider = :openai
        assume_model_exists = true
      end
      super(model: model, provider: provider, assume_model_exists: assume_model_exists, context: context)
    end
  end
end

RubyLLM::Chat.prepend(Konversio::RubyLLMChatProviderPassthrough)
