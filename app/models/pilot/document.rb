# == Schema Information
#
# Table name: pilot_documents
#
#  id                     :bigint           not null, primary key
#  content                :text
#  external_link          :string           not null
#  last_sync_attempted_at :datetime
#  last_synced_at         :datetime
#  metadata               :jsonb
#  name                   :string
#  status                 :integer          default("in_progress"), not null
#  sync_status            :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  assistant_id           :bigint           not null
#

# Pilot knowledge-source document. Owns a source URL or an attached PDF;
# searchable knowledge derived from this row is persisted as polymorphic
# `Pilot::AssistantResponse` rows.
#
# The `status` column tracks document availability (`in_progress` → `available`)
# while `sync_status` tracks the async fetch operation (`syncing` → `synced` |
# `failed`).
class Pilot::Document < ApplicationRecord
  self.table_name = 'pilot_documents'

  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :account
  has_many :responses,
           class_name: 'Pilot::AssistantResponse',
           as: :documentable,
           dependent: :destroy
  has_one_attached :pdf_file

  enum :status, { in_progress: 0, available: 1 }
  enum :sync_status, { syncing: 0, synced: 1, failed: 2 }, prefix: :sync

  validates :external_link, presence: true, unless: -> { pdf_file.attached? }
  validates :external_link, uniqueness: { scope: :assistant_id }, allow_blank: true
  validates :content, length: { maximum: 200_000 }

  before_validation :ensure_account_id
  before_validation :set_external_link_for_pdf
  before_validation :normalize_external_link

  scope :ordered, -> { order(created_at: :desc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }

  after_create_commit :enqueue_crawl_job
  after_commit :enqueue_response_builder_job

  def pdf_document?
    return true if pdf_file.attached? && pdf_file.blob.content_type == 'application/pdf'

    external_link&.ends_with?('.pdf')
  end

  private

  def ensure_account_id
    self.account_id = assistant&.account_id if account_id.blank?
  end

  def set_external_link_for_pdf
    return unless pdf_file.attached? && external_link.blank?

    timestamp = Time.current.iso8601
    self.external_link = "PDF: #{pdf_file.filename.base}_#{timestamp}"
  end

  def normalize_external_link
    return if external_link.blank?
    return if pdf_document?

    self.external_link = external_link.delete_suffix('/')
  end

  def enqueue_crawl_job
    # Crawl job lives in section 4 controller round; for now we just enqueue
    # the response builder once content has been populated by another path.
    return unless defined?(::Pilot::Documents::CrawlJob)
    return unless in_progress?

    ::Pilot::Documents::CrawlJob.perform_later(id)
  end

  def enqueue_response_builder_job
    return if destroyed?
    return unless available?
    return if content.blank?
    return unless saved_change_to_status? || saved_change_to_content?

    ::Pilot::DocumentResponseBuilderJob.perform_later(id)
  end
end
