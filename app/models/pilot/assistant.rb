# == Schema Information
#
# Table name: pilot_assistants
#
#  id                  :bigint           not null, primary key
#  config              :jsonb            not null
#  description         :string
#  guardrails          :jsonb
#  name                :string           not null
#  response_guidelines :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_pilot_assistants_on_account_id  (account_id)
#

# Account-scoped Autopilot assistant. Owns documents (knowledge sources),
# assistant responses (the searchable knowledge base), scenarios (rule-based
# behavior), and inbox attachments. The underlying table is still named
# `captain_assistants` per the minimal-fork doctrine — only the AR class
# carries the Pilot namespace.
class Pilot::Assistant < ApplicationRecord
  self.table_name = 'pilot_assistants'

  belongs_to :account

  has_many :documents,
           class_name: 'Pilot::Document',
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :responses,
           class_name: 'Pilot::AssistantResponse',
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :scenarios,
           class_name: 'Pilot::Scenario',
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :pilot_inboxes,
           class_name: 'Pilot::Inbox',
           foreign_key: :pilot_assistant_id,
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :inboxes, through: :pilot_inboxes
  has_many :messages, as: :sender, dependent: :nullify

  store_accessor :config,
                 :product_name,
                 :feature_faq,
                 :feature_memory,
                 :feature_contact_attributes,
                 :feature_citation,
                 :citation_behavior,
                 :welcome_message,
                 :handoff_message,
                 :resolution_message,
                 :instructions,
                 :temperature

  validates :name, presence: true
  validates :account_id, presence: true

  # Documentation-search citation toggle (default "on"). When "off", the
  # documentation-search tool MUST suppress `Source: <file>` lines for
  # PDF-origin matches; URL-origin matches always surface the URL.
  def citation_behavior
    config&.dig('citation_behavior').presence || 'on'
  end

  scope :ordered, -> { order(created_at: :desc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def available_name
    name
  end

  # No avatar attachment support yet; subclasses or future migrations can
  # override. Until then `avatar_url` is always nil so push_event_data
  # falls through to `default_avatar_url`.
  def avatar_url(*)
    nil
  end

  def default_avatar_url
    '/assets/images/konversio_bot.svg'
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || inbox&.avatar_url || default_avatar_url,
      description: description,
      type: 'agent_bot'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'pilot_assistant'
    }
  end
end
