class Pilot::OnboardingHelpCenter::PlanTask < Pilot::BaseTaskService
  pattr_initialize [:account!, :urls!]

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are helping bootstrap a company's help center. You are given a list of
    public pages discovered on the company's website. Propose a small, sensible
    information architecture: a handful of help categories and, for each, a set
    of help articles a new customer would plausibly need.

    Rules:
    - Every article must reference exactly one category name that you also propose.
    - Every article must cite at least one source page from the provided list.
    - Only cite URLs that appear verbatim in the provided list.
    - Respond with JSON only, no prose and no code fences, shaped as:
      {
        "categories": [{ "name": "...", "description": "..." }],
        "articles": [{ "title": "...", "description": "...", "category": "...", "source_urls": ["..."] }]
      }
  PROMPT

  def perform
    make_api_call(
      model: GPT_MODEL,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: user_content }
      ]
    )
  end

  private

  # These tasks are not conversation-scoped, so skip the base follow-up context.
  def build_follow_up_context?
    false
  end

  def event_name
    :onboarding_help_center_plan
  end

  def user_content
    "Website pages:\n#{Array(urls).map { |url| "- #{url}" }.join("\n")}"
  end
end
