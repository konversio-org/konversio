# Session detail endpoint: given an AI-authored message id, returns the Pilot
# run session whose result is that message so agents can inspect the model,
# knowledge sources, and run steps behind a reply.
#
# Account scoping is enforced by loading the message through `Current.account`
# (cross-account access surfaces as 404). Visibility is authorized through the
# conversation policy; a message with no recorded session returns 404.
class Api::V1::Accounts::Pilot::AgentSessionsController < Api::V1::Accounts::BaseController
  before_action :load_message
  before_action :authorize_request
  before_action :load_session
  before_action :load_referenced_records

  def show; end

  private

  def load_message
    @message = Current.account.messages.find_by(id: params[:message_id])
    render_not_found if @message.blank?
  end

  def authorize_request
    return if performed?

    authorize(@message.conversation, :show?, policy_class: ConversationPolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  def load_session
    return if performed?

    @session = Current.account.pilot_agent_sessions
                      .where(result_type: 'Message', result_id: @message.id)
                      .order(created_at: :desc)
                      .first
    render_not_found if @session.blank?
  end

  def load_referenced_records
    return if performed?

    @cited_documents = Current.account.pilot_documents.where(id: @session.cited_document_ids).index_by(&:id)
    @used_faqs = Current.account.pilot_assistant_responses
                        .user_authored
                        .where(id: @session.used_faq_ids)
                        .index_by(&:id)
    @scenarios = Current.account.pilot_scenarios.where(id: @session.scenario_ids).index_by(&:id)
  end

  def render_not_found
    render json: { error: 'Resource could not be found' }, status: :not_found
  end
end
