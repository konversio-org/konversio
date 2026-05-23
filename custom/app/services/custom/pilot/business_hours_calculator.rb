# frozen_string_literal: true

module Custom
  module Pilot
    # Computes the `value_in_business_hours` field for a Pilot reporting
    # event. Wraps the host `ReportingEventHelper#business_hours` helper so
    # Pilot stays aligned with the host's working-hours configuration while
    # not depending on the host listener's instance methods.
    #
    # When the inbox has no working-hours configuration, the helper returns
    # the wall-clock duration so reports always have a comparable number.
    class BusinessHoursCalculator
      include ::ReportingEventHelper

      # Returns the business-hours-adjusted duration in seconds. Falls back
      # to wall-clock when the inbox has no business hours configured.
      def self.call(inbox:, from:, to:)
        new.call(inbox: inbox, from: from, to: to)
      end

      def call(inbox:, from:, to:)
        return wall_clock(from, to) if inbox.blank? || !inbox.working_hours_enabled?

        business_hours(inbox, from, to)
      end

      private

      def wall_clock(from, to)
        return 0 if from.blank? || to.blank?

        to.to_i - from.to_i
      end
    end
  end
end
