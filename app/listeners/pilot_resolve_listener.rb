# frozen_string_literal: true

# Hooks resolve-time Pilot mining into Chatwoot's `conversation_resolved`
# event. The deepdive's cross-cutting "listener decoupling" rule applies:
#
#   * the resolution MUST succeed even when mining fails — both mining
#     paths are enqueued via Sidekiq jobs that catch their own errors
#   * the two feature toggles (assistant FAQ-learning, assistant contact
#     memory) gate independently so an account can run one assistant
#     with FAQ mining on and another with it off
#
# This listener replaces the older direct enqueue site for
# `Pilot::LogbookExtractionJob` that earlier sub-tasks sketched into the
# Conversation model — keeping both mining paths on the same listener
# matches the reference product's single decision point.
class PilotResolveListener < BaseListener
  def conversation_resolved(event)
    conversation, account = extract_conversation_and_account(event)
    return if conversation.blank? || account.blank?
    return unless account.feature_enabled?('pilot')

    clear_pilot_handoff_metadata(conversation)

    assistant = pilot_assistant_for(conversation)

    enqueue_faq_mining(conversation, account, assistant)
    enqueue_logbook_extraction(conversation, account, assistant)
  end

  private

  def clear_pilot_handoff_metadata(conversation)
    return unless conversation.additional_attributes&.key?('pilot_handoff')

    conversation.additional_attributes.delete('pilot_handoff')
    conversation.save!
  end

  def pilot_assistant_for(conversation)
    inbox = conversation.inbox
    return nil if inbox.blank?

    pilot_inbox = ::Pilot::Inbox.find_by(inbox_id: inbox.id)
    pilot_inbox&.assistant
  end

  def enqueue_faq_mining(conversation, account, assistant)
    return unless account.feature_enabled?('pilot_autopilot')
    return if assistant.blank?
    return unless faq_learning_enabled?(assistant)

    ::Pilot::Conversations::FaqMiningJob.perform_later(conversation.id)
  end

  def enqueue_logbook_extraction(conversation, account, _assistant)
    return unless account.feature_enabled?('pilot_logbook')
    return if conversation.contact_id.blank?

    ::Pilot::LogbookExtractionJob.perform_later(conversation.id)
  end

  # Per-assistant FAQ-learning is stored in the assistant's config JSONB
  # under `feature_faq`. The deepdive mandates this is independently
  # toggleable from the contact-memory flag so a single account can mix
  # assistants with different mining policies.
  def faq_learning_enabled?(assistant)
    cfg = assistant.config || {}
    ActiveModel::Type::Boolean.new.cast(cfg['feature_faq'])
  end
end
