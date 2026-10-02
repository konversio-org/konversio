class Api::V1::Accounts::Companies::ContactsController < Api::V1::Accounts::Companies::BaseController
  RESULTS_PER_PAGE = 15

  before_action :authorize_company_read!, only: [:index, :search]
  before_action :authorize_company_update!, only: [:create, :destroy]
  before_action :set_current_page, only: [:index, :search]
  before_action :fetch_member, only: [:destroy]

  def index
    @contacts = paginate(@company.contacts.order(:name, :id))
    @contacts_count = @contacts.total_count
  end

  def search
    return render json: { error: 'Specify search string with parameter q' }, status: :unprocessable_entity if params[:q].blank?

    @contacts = paginate(candidate_contacts)
    @contacts_count = @contacts.total_count
  end

  def create
    @contact = Current.account.contacts.find(params[:contact_id])
    membership_service.assign(contact: @contact)
  end

  def destroy
    membership_service.remove(contact: @member)
    head :ok
  end

  private

  def membership_service
    @membership_service ||= Companies::ContactMembershipService.new(company: @company)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def paginate(scope)
    scope.includes({ avatar_attachment: [:blob] }, :company).page(@current_page).per(RESULTS_PER_PAGE)
  end

  def fetch_member
    @member = @company.contacts.find(params[:id])
  end

  def candidate_contacts
    pattern = "%#{params[:q].to_s.strip}%"
    Current.account.contacts
           .where('contacts.company_id IS NULL OR contacts.company_id != ?', @company.id)
           .where(
             'contacts.name ILIKE :pattern OR contacts.email ILIKE :pattern ' \
             'OR contacts.phone_number ILIKE :pattern OR contacts.identifier ILIKE :pattern',
             pattern: pattern
           )
           .order(:name, :id)
  end
end
