class Api::V1::Accounts::Pilot::DocumentsController < Api::V1::Accounts::BaseController
  PER_PAGE = 25
  MAX_PDF_BYTES = 25.megabytes
  SYNC_STATE_FILTERS = %w[stale synced syncing failed].freeze
  SOURCE_FILTERS = %w[web pdf markdown].freeze

  before_action :ensure_feature_enabled
  before_action :load_assistant, only: [:create]
  before_action :load_document, only: [:show, :destroy, :refresh]
  before_action :authorize_request

  def index
    scope = Current.account.pilot_documents.ordered
    scope = scope.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = apply_sync_state_filter(scope)
    scope = apply_source_filter(scope)

    @documents = scope.page(current_page).per(PER_PAGE)
  end

  def show; end

  def create
    @document = @assistant.documents.new(
      account: Current.account,
      external_link: document_params[:external_link],
      markdown_content: document_params[:markdown_content],
      status: :in_progress
    )
    attach_pdf_if_present
    attach_markdown_if_present
    validate_source!
    @document.save!

    # `after_create_commit :enqueue_crawl_job` on `Pilot::Document` enqueues
    # `Pilot::Documents::CrawlJob` for URL/PDF ingestion. Markdown documents
    # become `available` during validation, so no crawl is enqueued for them.
    render :show, status: :created
  end

  def refresh
    unless @document.available? && @document.syncable?
      return render json: { error: 'Only available web documents can be refreshed' }, status: :unprocessable_entity
    end

    @document.update!(
      sync_status: :syncing,
      last_sync_attempted_at: Time.current,
      metadata: (@document.metadata || {}).merge('last_sync_failure_category' => nil, 'refresh_phase' => 'queued')
    )
    ::Pilot::Documents::RefreshJob.perform_later(@document.id)
    head :accepted
  end

  def destroy
    @document.destroy!
    head :no_content
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_autopilot')

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def load_assistant
    assistant_id = params.dig(:document, :assistant_id) || params[:assistant_id]
    if assistant_id.blank?
      render json: { error: 'assistant_id is required' }, status: :unprocessable_entity
      return
    end

    @assistant = Current.account.pilot_assistants.find_by(id: assistant_id)
    render json: { error: 'Assistant not found' }, status: :not_found if @assistant.blank?
  end

  def load_document
    @document = Current.account.pilot_documents.find_by(id: params[:id])
    render json: { error: 'Resource could not be found' }, status: :not_found if @document.blank?
  end

  def authorize_request
    return if performed?

    record = @document || @assistant || Pilot::Document
    authorize(record, policy_class: Pilot::DocumentPolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  def apply_sync_state_filter(scope)
    state = params[:sync_state].presence
    return scope unless SYNC_STATE_FILTERS.include?(state)

    case state
    when 'stale'
      scope.where(status: :available).where('last_synced_at IS NULL OR last_synced_at < ?', stale_cutoff)
    when 'synced' then scope.where(sync_status: :synced)
    when 'syncing' then scope.where(sync_status: :syncing)
    when 'failed' then scope.where(sync_status: :failed)
    end
  end

  def apply_source_filter(scope)
    source = params[:source].presence
    return scope unless SOURCE_FILTERS.include?(source)

    case source
    when 'pdf' then scope.where("external_link LIKE 'PDF:%'")
    when 'markdown' then scope.where('external_link LIKE ?', "#{Pilot::Document::MARKDOWN_LINK_PREFIX}%")
    when 'web' then scope.where("external_link NOT LIKE 'PDF:%' AND external_link NOT LIKE ?", "#{Pilot::Document::MARKDOWN_LINK_PREFIX}%")
    end
  end

  def stale_cutoff
    Current.account.pilot_document_sync_interval_hours.hours.ago
  end

  def validate_source!
    return if file_source?

    link = @document.external_link.to_s
    raise ActiveRecord::RecordInvalid, @document if link.blank?

    uri = URI.parse(link)
    return if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    @document.errors.add(:external_link, 'must be a valid http(s) URL')
    raise ActiveRecord::RecordInvalid, @document
  rescue URI::InvalidURIError
    @document.errors.add(:external_link, 'must be a valid http(s) URL')
    raise ActiveRecord::RecordInvalid, @document
  end

  def file_source?
    @document.pdf_file.attached? || @document.markdown_file.attached? || @document.markdown_content.present?
  end

  def attach_pdf_if_present
    pdf = document_params[:pdf_file]
    return if pdf.blank?

    unless valid_pdf_upload?(pdf)
      @document.errors.add(:pdf_file, 'must be a PDF under 25 MB')
      raise ActiveRecord::RecordInvalid, @document
    end

    @document.pdf_file.attach(io: pdf.tempfile, filename: pdf.original_filename, content_type: pdf.content_type)
  end

  def attach_markdown_if_present
    markdown = document_params[:markdown_file]
    return if markdown.blank?

    body = markdown.tempfile.read
    markdown.tempfile.rewind
    @document.content ||= body
    @document.markdown_file.attach(io: markdown.tempfile, filename: markdown.original_filename, content_type: markdown.content_type)
  end

  def valid_pdf_upload?(pdf)
    return false unless pdf.respond_to?(:content_type) && pdf.content_type == 'application/pdf'
    return false if pdf.size.to_i > MAX_PDF_BYTES

    true
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def document_params
    params.require(:document).permit(:assistant_id, :external_link, :pdf_file, :markdown_file, :markdown_content)
  rescue ActionController::ParameterMissing
    ActionController::Parameters.new.permit(:assistant_id, :external_link, :pdf_file, :markdown_file, :markdown_content)
  end
end
