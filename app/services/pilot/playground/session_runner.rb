# frozen_string_literal: true

module Pilot
  module Playground
    # Runs one configured playground turn: builds the validated per-run
    # configuration, wires the run-report collector into `AutopilotService`, and
    # returns the additive response hash (reply, invoked tools, run report).
    #
    # Raises `Pilot::Playground::SessionConfig::Invalid` before any inference
    # when the supplied configuration is malformed.
    class SessionRunner
      def self.call(**)
        new(**).call
      end

      def initialize(assistant:, payload:, message: nil, message_history: nil, account: nil)
        @assistant = assistant
        @payload = payload
        @message = message
        @message_history = message_history
        @account = account
      end

      def call
        config = SessionConfig.build(payload, assistant: assistant)
        report = RunReport.new(assistant: assistant, config: config)
        result = ::Custom::Pilot::AutopilotService.new(
          assistant: assistant,
          message: message,
          message_history: message_history,
          account: account,
          source: 'playground',
          runtime_config: config,
          run_callbacks: report.callbacks
        ).perform
        report.finish!

        {
          reply: result.reply,
          invoked_tool_names: result.invoked_tool_names,
          run_report: report.to_h
        }
      end

      private

      attr_reader :assistant, :payload, :message, :message_history, :account
    end
  end
end
