class Api::V1::Accounts::CompaniesController < Api::V1::Accounts::BaseController
  include Sift
  sort_on :name, type: :string
  sort_on :domain, type: :string
  sort_on :created_at, type: :datetime
  sort_on :last_activity_at, internal_name: :order_on_last_activity_at, type: :scope, scope_params: [:direction]
  sort_on :contacts_count, internal_name: :order_on_contacts_count, type: :scope, scope_params: [:direction]

  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :set_current_page, only: [:index, :search]
  before_action :fetch_company, only: [:show, :update, :destroy, :avatar, :destroy_custom_attributes]

  def index
    @companies = paginate(account_companies)
    @companies_count = @companies.total_count
  end

  def search
    return render_missing_query if params[:q].blank?

    @companies = paginate(account_companies.search_by_name_or_domain(params[:q]))
    @companies_count = @companies.total_count
  end

  def show; end

  def create
    @company = Current.account.companies.create!(company_params)
  end

  def update
    @company.update!(company_update_params)
  end

  def destroy
    Companies::DeleteJob.perform_later(company_id: @company.id)
    head :ok
  end

  def avatar
    @company.avatar.purge if @company.avatar.attached?
  end

  def destroy_custom_attributes
    keys = custom_attribute_keys_to_remove
    return render json: { error: 'custom_attributes must be an array' }, status: :unprocessable_entity if keys.nil?

    @company.custom_attributes = @company.custom_attributes.excluding(*keys)
    @company.save!
  end

  private

  def account_companies
    Current.account.companies
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def paginate(companies)
    filtrate(companies).page(@current_page).per(RESULTS_PER_PAGE)
  end

  def fetch_company
    @company = Current.account.companies.find(params[:id])
  end

  def render_missing_query
    render json: { error: I18n.t('errors.companies.search.query_missing') }, status: :unprocessable_entity
  end

  def company_params
    params.require(:company).permit(
      :name,
      :domain,
      :description,
      :avatar,
      additional_attributes: {},
      custom_attributes: {}
    )
  end

  def merged_custom_attributes
    incoming = company_params[:custom_attributes]
    return @company.custom_attributes if incoming.blank?

    @company.custom_attributes.merge(incoming.to_h)
  end

  def company_update_params
    company_params.except(:custom_attributes).merge(custom_attributes: merged_custom_attributes)
  end

  def custom_attribute_keys_to_remove
    return nil unless params[:custom_attributes].is_a?(Array)

    params.permit(custom_attributes: [])[:custom_attributes]
  end
end
