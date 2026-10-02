# Read-only campaign outcome reporting for WhatsApp one-off campaigns.
#
# The aggregate endpoint answers "how did this campaign do", and the contacts
# endpoint lists each recipient's outcome (optionally filtered by status) so an
# operator can see who was skipped or failed and why.
class Api::V1::Accounts::Campaigns::AnalyticsController < Api::V1::Accounts::BaseController
  PER_PAGE = 25

  before_action :fetch_campaign
  before_action :authorize_campaign
  before_action :ensure_whatsapp_oneoff_campaign

  def metrics
    render json: Pilot::CampaignRecipient.summary_for(@campaign)
  end

  def contacts
    recipients = paginated_recipients

    render json: {
      payload: recipients.map { |recipient| outcome_payload(recipient) },
      meta: {
        current_page: recipients.current_page,
        total_pages: recipients.total_pages,
        total_count: recipients.total_count
      }
    }
  end

  private

  def fetch_campaign
    @campaign = Current.account.campaigns.find_by!(display_id: params[:id])
  end

  def authorize_campaign
    authorize @campaign, :show?
  end

  def ensure_whatsapp_oneoff_campaign
    return if @campaign.one_off? && @campaign.inbox.inbox_type == 'Whatsapp' && Current.account.feature_enabled?(:whatsapp_campaign)

    raise Pundit::NotAuthorizedError
  end

  def paginated_recipients
    scope = @campaign.pilot_campaign_recipients.includes(:contact).order(created_at: :desc)
    scope = scope.where(status: params[:status]) if Pilot::CampaignRecipient.statuses.key?(params[:status])
    scope.page(params[:page]).per(PER_PAGE)
  end

  def outcome_payload(recipient)
    {
      contact: {
        id: recipient.contact.id,
        name: recipient.contact.name,
        phone_number: recipient.contact.phone_number
      },
      status: recipient.status,
      message_content: recipient.message_content,
      error_code: recipient.error_code,
      error_title: recipient.error_title,
      error_message: recipient.error_message
    }
  end
end
