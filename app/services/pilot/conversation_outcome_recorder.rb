# frozen_string_literal: true

module Pilot
  # The single write path for `pilot_conversation_outcomes`. Outcome tracking
  # is a secondary effect of the customer-facing flow, so every public method
  # is failure-isolated: any error is logged and reported to the exception
  # tracker, never raised into the message, handoff, resolution, or survey
  # flow that triggered it. Terminal events with no covering episode are
  # no-ops rather than errors.
  class ConversationOutcomeRecorder
    def initialize(conversation:, assistant: nil)
      @conversation = conversation
      @assistant = assistant
    end

    # Open the conversation's first episode the moment Pilot becomes eligible
    # to respond. Idempotent: once any episode exists, later eligibility
    # signals are ignored.
    def record_eligibility(at:)
      safely(:record_eligibility) { perform_eligibility(at) }
    end

    # Close the currently open episode and start a reopen-triggered successor,
    # attributed to the inbox's currently attached assistant when one exists.
    # A conversation with no episode history records nothing.
    def record_reopen(at:)
      safely(:record_reopen) { perform_reopen(at) }
    end

    # Stamp the handoff time and categorized reason on the episode covering
    # `at`, then resnapshot its AI reply facts.
    def record_handoff(at:, reason_category:)
      safely(:record_handoff) { perform_handoff(at, reason_category) }
    end

    # Stamp the resolution time on the episode covering `at`, then resnapshot
    # its AI reply facts.
    def record_resolution(at:)
      safely(:record_resolution) { perform_resolution(at) }
    end

    # Record the first qualifying human reply on the episode covering the
    # message's creation time. Idempotent per episode.
    def record_human_reply(message:)
      safely(:record_human_reply) { perform_human_reply(message) }
    end

    # Record a CSAT rating and its receipt time on the episode covering the
    # survey message's creation time. Responses covered by no episode record
    # nothing.
    def record_csat(response:)
      safely(:record_csat) { perform_csat(response) }
    end

    private

    def perform_eligibility(at)
      return if at.blank? || assistant.blank?
      return unless account&.feature_enabled?('pilot')
      return if episodes.exists?

      create_episode(episode_trigger: 'initial', started_at: at, assistant: assistant)
    end

    def perform_reopen(at)
      return if at.blank? || episodes.empty?

      closing = episodes.where(ended_at: nil).order(started_at: :desc).first
      closing&.update!(ended_at: at)
      attribution = assistant || closing&.assistant || episodes.chronological.last&.assistant
      return if attribution.blank?

      create_episode(episode_trigger: 'reopen', started_at: at, assistant: attribution)
    end

    def perform_handoff(at, reason_category)
      episode = covering_episode(at)
      return if episode.blank?

      episode.update!(handoff_at: at, handoff_reason_category: reason_category)
      snapshot_reply_facts(episode)
    end

    def perform_resolution(at)
      episode = covering_episode(at)
      return if episode.blank?

      episode.update!(resolved_at: at)
      snapshot_reply_facts(episode)
    end

    def perform_human_reply(message)
      return unless human_reply?(message)

      episode = covering_episode(message.created_at)
      return if episode.blank? || episode.first_human_reply_at.present?

      episode.update!(first_human_reply_at: message.created_at)
    end

    def perform_csat(response)
      message = response&.message
      return if message.blank?

      episode = covering_episode(message.created_at)
      return if episode.blank?

      episode.update!(csat_rating: response.rating, csat_received_at: response.created_at)
    end

    def create_episode(episode_trigger:, started_at:, assistant:)
      episodes.create!(
        account: account,
        assistant: assistant,
        conversation: @conversation,
        inbox: @conversation.inbox,
        episode_trigger: episode_trigger,
        started_at: started_at
      )
    end

    def snapshot_reply_facts(episode)
      scope = @conversation.messages
                           .where(message_type: :outgoing, private: false)
                           .where(sender_type: 'Pilot::Assistant')
                           .where('messages.created_at >= ?', episode.started_at)
      scope = scope.where('messages.created_at < ?', episode.ended_at) if episode.ended_at.present?

      episode.update!(
        ai_reply_count: scope.count,
        first_ai_reply_at: scope.minimum(:created_at),
        last_ai_reply_at: scope.maximum(:created_at)
      )
    end

    def covering_episode(at)
      return nil if at.blank?

      episodes.covering(at).first
    end

    # Public, outgoing, non-private message authored by a human agent — or a
    # human reply echoed back from an external channel. Automation-rule and
    # campaign messages are excluded by `Message#human_response?`.
    def human_reply?(message)
      return false if message.blank? || message.private?
      return false unless message.respond_to?(:human_response?) && message.human_response?
      return false unless message.conversation_id == @conversation.id

      true
    end

    def episodes
      @conversation.conversation_outcomes
    end

    def account
      @conversation&.account
    end

    # Falls back to the inbox's attached assistant so callers that only know
    # the conversation (reopen, resolution, handoff) still attribute correctly.
    def assistant
      @assistant ||= attached_assistant
    end

    def attached_assistant
      return nil if @conversation&.inbox_id.blank?

      ::Pilot::Inbox.find_by(inbox_id: @conversation.inbox_id)&.assistant
    end

    def safely(operation)
      yield
    rescue StandardError => e
      Rails.logger.error("[pilot.conversation_outcome_recorder] #{operation} failed: #{e.class}: #{e.message}")
      KonversioExceptionTracker.new(e, account: account).capture_exception
      nil
    end
  end
end
