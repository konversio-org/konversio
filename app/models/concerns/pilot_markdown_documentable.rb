# frozen_string_literal: true

# Markdown as a Pilot knowledge source. A markdown document is file-backed:
# its body arrives either as an uploaded `.md` file or as pasted text that we
# synthesize into a `.md` attachment, so both variants share one storage
# model. It becomes `available` immediately (no crawl) and is excluded from
# URL re-sync and customer-visible citation links.
module PilotMarkdownDocumentable
  extend ActiveSupport::Concern

  MARKDOWN_MAX_CHARS = 10_000
  MARKDOWN_CONTENT_TYPES = %w[text/markdown text/x-markdown text/plain].freeze

  included do
    has_one_attached :markdown_file

    # Virtual attribute for the pasted-text variant. The concern turns it into
    # a real `.md` attachment before validation so downstream code only ever
    # sees the file-backed representation.
    attr_accessor :markdown_content

    before_validation :materialize_markdown_source
    before_validation :assign_markdown_external_link

    validate :markdown_attachment_format, if: -> { markdown_file.attached? }
    validate :markdown_content_present, if: :markdown_document?
    validate :markdown_content_length, if: :markdown_document?
    validate :single_file_attachment
  end

  # A markdown document is either backed by an attached `.md` file or already
  # stamped with a synthetic file link (the latter covers rows loaded after the
  # attachment metadata has been detached from the in-memory record).
  def markdown_document?
    markdown_file.attached? || external_link.to_s.start_with?(Pilot::Document::MARKDOWN_LINK_PREFIX)
  end

  private

  # Pulls pasted text into a `.md` attachment, then marks the document
  # available. Runs before validations so the length/format checks and the
  # `external_link` assignment see the final shape. Uploaded file bodies are
  # read by the controller (ActiveStorage defers a new record's blob upload
  # until save), so `content` is already populated here for that variant.
  def materialize_markdown_source
    materialize_pasted_markdown if markdown_content.present? && !markdown_file.attached?
    return unless markdown_file.attached?

    self.status = :available
    self.name ||= markdown_file.filename.base
  end

  def materialize_pasted_markdown
    self.content = markdown_content.to_s
    markdown_file.attach(
      io: StringIO.new(markdown_content.to_s),
      filename: "pasted-#{Time.current.to_i}.md",
      content_type: 'text/markdown'
    )
    self.name ||= 'Pasted markdown'
  end

  def assign_markdown_external_link
    return unless markdown_document?
    return if external_link.present?

    self.external_link = "#{Pilot::Document::MARKDOWN_LINK_PREFIX} #{markdown_file.filename.base}_#{Time.current.iso8601}"
  end

  def markdown_attachment_format
    filename = markdown_file.filename.to_s
    content_type = markdown_file.blob&.content_type.to_s

    errors.add(:markdown_file, 'must be a .md file') unless filename.downcase.end_with?('.md')
    return if MARKDOWN_CONTENT_TYPES.include?(content_type)

    errors.add(:markdown_file, 'must be a markdown or plain-text file')
  end

  def markdown_content_present
    errors.add(:markdown_content, 'is required') if content.blank?
  end

  def markdown_content_length
    return if content.to_s.length <= MARKDOWN_MAX_CHARS

    errors.add(:markdown_content, "is too long (maximum is #{MARKDOWN_MAX_CHARS} characters)")
  end

  def single_file_attachment
    return unless pdf_file.attached? && markdown_file.attached?

    errors.add(:base, 'a document can only have one file attachment')
  end
end
