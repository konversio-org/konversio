require 'agents'

module Custom
  module Pilot
    module Tools
      # Base class for all Pilot Copilot tools.
      #
      # Inherits from `Agents::Tool` (the ai-agents SDK base) so the runner can
      # execute the tool in-process during a multi-step agentic conversation
      # (see openspec/changes/pilot-full design D21).
      #
      # Tools are STATELESS configuration objects: per-request data (account,
      # user, conversation) is passed in via `tool_context.context`, populated
      # by `Custom::Pilot::CopilotService` when it builds the runner context.
      #
      # Subclasses MUST implement `#perform(tool_context, **params)` and SHOULD
      # return a String (the LLM consumes it as the tool result). On failure
      # return a short user-friendly string rather than raising — the runner
      # treats raised exceptions as fatal and aborts the whole turn.
      class Base < ::Agents::Tool
        private

        # Look up the Account record for the currently-running tool call. The
        # account_id is set on the runner context by CopilotService. We re-fetch
        # rather than passing the AR object through the context (Agents SDK
        # deep-copies the context hash for thread safety; passing AR objects
        # through that copy would break lazy-loading).
        def account_for(tool_context)
          account_id = tool_context.context[:account_id]
          return nil if account_id.blank?

          ::Account.find_by(id: account_id)
        end
      end
    end
  end
end
