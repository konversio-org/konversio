# Permission-aware finder for FAQ suggestions.
#
# Administrators see all of an account's suggestions. Non-admin agents see
# only suggestions with at least one observation on a conversation visible
# to them under `Conversations::PermissionFilterService` — suggestions are
# assistant-scoped and assistants span inboxes, so conversation-derived
# scoping reflects what an agent may actually see.
class Pilot::FaqSuggestionFinder
  def initialize(account:, user:, params: {})
    @account = account
    @user = user
    @params = params
  end

  def perform
    scope = @account.pilot_faq_suggestions
    scope = scope.where(assistant_id: @params[:assistant_id]) if @params[:assistant_id].present?
    scope = scope.where(status: @params[:status]) if @params[:status].present?
    scope = apply_search(scope)
    visible_to_user(scope).ordered
  end

  private

  def apply_search(scope)
    query = @params[:search].to_s.strip
    return scope if query.blank?

    like = "%#{query}%"
    scope.where('question ILIKE :q OR answer ILIKE :q', q: like)
  end

  def visible_to_user(scope)
    return scope if account_user&.administrator?

    scope.where(
      id: ::Pilot::FaqObservation
          .where(conversation_id: accessible_conversation_ids)
          .where.not(faq_suggestion_id: nil)
          .select(:faq_suggestion_id)
    )
  end

  def accessible_conversation_ids
    ::Conversations::PermissionFilterService
      .new(@account.conversations, @user, @account)
      .perform
      .select(:id)
  end

  def account_user
    @account_user ||= ::AccountUser.find_by(account_id: @account.id, user_id: @user.id)
  end
end
