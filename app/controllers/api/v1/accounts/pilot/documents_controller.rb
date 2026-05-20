class Api::V1::Accounts::Pilot::DocumentsController < Api::V1::Accounts::BaseController
  PER_PAGE = 25
  MAX_PDF_BYTES = 25.megabytes

  before_action :ensure_feature_enabled
  before_action :load_assistant, only: [:create]
  before_action :load_document, only: [:show, :destroy]
  before_action :authorize_request

  def index
    scope = Current.account.pilot_documents.ordered
    scope = scope.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?

    @documents = scope.page(current_page).per(PER_PAGE)
  end

  def show; end

  def create
    @document = @assistant.documents.new(
      account: Current.account,
      external_link: document_params[:external_link]
    )
    attach_pdf_if_present
    validate_source!
    @document.save!

    ingest_document(@document)
    render :show, status: :created
  end

  def destroy
    @document.destroy!
    head :no_content
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_autopilot_enabled

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

  def validate_source!
    return if @document.pdf_file.attached?

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

  def attach_pdf_if_present
    pdf = document_params[:pdf_file]
    return if pdf.blank?

    unless valid_pdf_upload?(pdf)
      @document.errors.add(:pdf_file, 'must be a PDF under 25 MB')
      raise ActiveRecord::RecordInvalid, @document
    end

    @document.pdf_file.attach(io: pdf.tempfile, filename: pdf.original_filename, content_type: pdf.content_type)
  end

  def valid_pdf_upload?(pdf)
    return false unless pdf.respond_to?(:content_type) && pdf.content_type == 'application/pdf'
    return false if pdf.size.to_i > MAX_PDF_BYTES

    true
  end

  def ingest_document(document)
    result = Custom::Pilot::DocumentIngestionService.new(document: document, account: Current.account).perform
    if result&.success?
      document.update!(content: result.content, status: :available, sync_status: :synced)
    else
      document.update!(sync_status: :failed)
    end
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def document_params
    params.require(:document).permit(:assistant_id, :external_link, :pdf_file)
  rescue ActionController::ParameterMissing
    ActionController::Parameters.new.permit(:assistant_id, :external_link, :pdf_file)
  end
end
