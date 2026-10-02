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
# Indexes
#
#  index_pilot_documents_on_account_id                      (account_id)
#  index_pilot_documents_on_account_id_and_sync_status      (account_id,sync_status)
#  index_pilot_documents_on_assistant_id                    (assistant_id)
#  index_pilot_documents_on_assistant_id_and_external_link  (assistant_id,external_link) UNIQUE
#  index_pilot_documents_on_status                          (status)
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

  # Synthetic `external_link` prefix for file-backed markdown rows, mirroring
  # the PDF placeholder. Keeps the per-assistant source-link uniqueness
  # constraint intact for sources that have no web URL.
  MARKDOWN_LINK_PREFIX = 'MD:'.freeze

  include PilotMarkdownDocumentable

  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :account
  has_many :responses,
           class_name: 'Pilot::AssistantResponse',
           as: :documentable,
           dependent: :destroy
  has_one_attached :pdf_file

  enum :status, { in_progress: 0, available: 1, failed: 2 }
  enum :sync_status, { syncing: 0, synced: 1, failed: 2 }, prefix: :sync

  store_accessor :metadata, :crawl_job_id, :error_message, :customer_visible,
                 :content_fingerprint, :last_sync_failure_category, :refresh_phase

  validates :external_link, presence: true, unless: -> { pdf_file.attached? }
  validates :external_link, uniqueness: { scope: :assistant_id }, allow_blank: true
  validates :content, length: { maximum: 200_000 }

  before_validation :ensure_account_id
  before_validation :set_external_link_for_pdf
  before_validation :normalize_external_link

  # Pin in_progress rows to the top (so an actively-crawling seed stays
  # visible at the top of the list while child docs stream in below it),
  # then newest-first within each status group.
  scope :ordered, -> { order(Arel.sql("(status = #{statuses[:in_progress]}) DESC, created_at DESC")) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }

  after_create_commit :enqueue_crawl_job
  after_commit :enqueue_response_builder_job

  def pdf_document?
    return true if pdf_file.attached? && pdf_file.blob.content_type == 'application/pdf'

    external_link&.ends_with?('.pdf')
  end

  # Documents are customer-visible unless an operator explicitly flags them
  # otherwise. Uploaded PDFs never carry a customer-resolvable link.
  def customer_visible?
    value = metadata&.dig('customer_visible')
    value.nil? || ActiveModel::Type::Boolean.new.cast(value)
  end

  # File-backed documents (uploaded PDF or markdown) have no web page to
  # re-fetch and no customer-resolvable source URL.
  def file_document?
    pdf_document? || markdown_document?
  end

  def web_document?
    !file_document?
  end

  # A document is eligible for refresh only when it is a URL-backed source.
  # Callers additionally require `available?` for manual refreshes.
  def syncable?
    web_document? && external_link.present?
  end

  # True when the document's last successful sync is older than its account's
  # effective refresh cadence. Never-synced documents are stale.
  def sync_stale?(interval_hours = account&.pilot_document_sync_interval_hours || Pilot::SyncLimits::DEFAULT_REFRESH_INTERVAL_HOURS)
    return true if last_synced_at.blank?

    last_synced_at < interval_hours.hours.ago
  end

  def sync_in_progress?
    sync_status == 'syncing'
  end

  # The trusted, customer-resolvable URL for this document, or nil when the
  # document is not customer-visible, is file-backed, or fails the network-level
  # eligibility checks.
  def customer_visible_source_url
    return nil unless customer_visible?
    return nil if file_document?

    ::Pilot::CitationUrlValidator.eligible_url(external_link)
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
