class Pilot::OnboardingHelpCenter::StatusService
  def initialize(account)
    @account = account
  end

  def perform
    pointer = @account.custom_attributes[Pilot::OnboardingHelpCenter::GENERATION_KEY]
    return empty_status if pointer.blank?

    portal = @account.portals.order(:id).first

    {
      generation_id: pointer,
      state: Pilot::OnboardingHelpCenter::GenerationTracker.new(pointer).state,
      articles_count: portal ? portal.articles.count : 0,
      categories_count: portal ? portal.categories.count : 0
    }
  end

  private

  def empty_status
    { generation_id: nil, state: nil, articles_count: 0, categories_count: 0 }
  end
end
