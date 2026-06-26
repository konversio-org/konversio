module Custom
  module Pilot
    # Fix #2 — deterministic tool-skip guardrail. Post-hoc decider (sibling of
    # `HandoverEvaluator`): did the latest customer turn fall within an enabled
    # custom tool's stated purpose while the assistant called NO such tool?
    #
    # Pure decider — it never touches the runner. When `#evaluate` returns a
    # decision with `retry? == true`, the caller (`AutopilotService#run_runner`)
    # re-runs the turn exactly ONCE with that named tool forced.
    #
    # Returns `retry? == false` (no force) when any of these hold, evaluated in
    # this order so the cheap deterministic checks short-circuit before the
    # router LLM call:
    #
    #   * the assistant has no enabled custom tools
    #   * a scenario handoff already fired this turn (handover keeps precedence)
    #   * one of the assistant's custom tools already fired this turn
    #   * the router classifies the message as out-of-scope ('none')
    #
    # Off-topic restraint is preserved structurally: forcing happens ONLY on a
    # positive, named, in-catalog router match, so an off-topic decline is
    # never coerced into an invented tool call.
    class ToolSkipGuard
      Decision = Struct.new(:retry?, :forced_tool_slug, :reason, keyword_init: true)

      def initialize(assistant:, router: nil)
        @assistant = assistant
        @catalog = ::Custom::Pilot::CustomToolCatalog.for(assistant)
        @router = router || ::Custom::Pilot::ToolRouter.new(assistant: assistant)
      end

      # @param customer_message [String, nil] the latest customer turn
      # @param invoked_tool_names [Array<String>] tools that fired this turn
      # @return [Decision]
      def evaluate(customer_message:, invoked_tool_names:)
        return decline('no_custom_tools') if @catalog.empty?
        return decline('handoff_fired') if handoff_fired?(invoked_tool_names)
        return decline('custom_tool_fired') if custom_tool_fired?(invoked_tool_names)

        slug = @router.route(customer_message: customer_message, catalog: @catalog)
        return decline('router_none') if slug.blank?

        Decision.new(retry?: true, forced_tool_slug: slug, reason: 'tool_skipped')
      end

      private

      def custom_tool_fired?(invoked_tool_names)
        slugs = @catalog.map(&:slug)
        Array(invoked_tool_names).any? { |name| slugs.include?(name.to_s) }
      end

      def handoff_fired?(invoked_tool_names)
        Array(invoked_tool_names).any? { |name| name.to_s.start_with?('handoff_') }
      end

      def decline(reason)
        Decision.new(retry?: false, forced_tool_slug: nil, reason: reason)
      end
    end
  end
end
