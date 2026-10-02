class Pilot::OnboardingHelpCenter::ArticleTask < Pilot::BaseTaskService
  pattr_initialize [:account!, :pages!, :title!]

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are drafting a single help center article for a company. You are given a
    working title and the markdown of one or more public source pages. Rewrite the
    relevant material into a clear, self-contained article a customer can follow.

    Rules:
    - Do not invent facts that are not supported by the source pages.
    - Write in the language of the source pages.
    - Respond with JSON only, no prose and no code fences, shaped as:
      { "title": "...", "description": "...", "body": "..." }
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

  def event_name
    :onboarding_help_center_article
  end

  def user_content
    sources = Array(pages).map do |page|
      "Source: #{page[:url]}\n\n#{page[:markdown]}"
    end.join("\n\n---\n\n")

    "Working title: #{title}\n\n#{sources}"
  end
end
