module Custom
  module Pilot
    # Canonical `{slug, description}` list of an assistant's enabled custom HTTP
    # tools. Shared by the system-prompt policy
    # (`AutopilotService#custom_tools_policy`) and the runtime tool-skip
    # guardrail (`ToolSkipGuard` / `ToolRouter`) so the two views of "what tools
    # exist" are built from one place and can never drift.
    module CustomToolCatalog
      Entry = Struct.new(:slug, :description, keyword_init: true)

      module_function

      # @param assistant [Pilot::Assistant, nil]
      # @return [Array<Entry>] one entry per enabled custom tool (empty when none)
      def for(assistant)
        Array(assistant&.enabled_custom_tools).map do |tool|
          Entry.new(slug: tool.slug.to_s, description: tool.description.presence || tool.title.to_s)
        end
      end
    end
  end
end
