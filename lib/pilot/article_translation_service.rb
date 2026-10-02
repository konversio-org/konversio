# Translates a single piece of a Help Center article (its title or its body)
# into a target language with the account's default Pilot LLM.
#
# `target_language` is the locale code from the portal; it is resolved to a
# human-readable language name through the installation's language map before
# it reaches the model instructions (falling back to the raw code when the map
# has no entry). The result is a plain string, or the base service's error hash.
class Pilot::ArticleTranslationService < Pilot::BaseTaskService
  SUPPORTED_TYPES = %i[title content].freeze

  pattr_initialize [:account!, :text!, :target_language!, :type!, { conversation_display_id: nil }]

  def perform
    raise ArgumentError, "Unsupported translation type: #{type}" unless SUPPORTED_TYPES.include?(type.to_sym)

    response = make_api_call(
      model: Llm::Config.model_for(:default),
      messages: [
        { role: 'system', content: system_instructions },
        { role: 'user', content: text }
      ]
    )
    return response if response[:error]

    response.merge(message: response[:message].to_s.strip)
  end

  private

  def system_instructions
    type.to_sym == :title ? title_instructions : content_instructions
  end

  def title_instructions
    <<~INSTRUCTIONS
      You translate help-center article titles into #{resolved_language}.
      Keep the translation natural and concise. Answer with the translated
      title only — no quotes, labels, or commentary.
    INSTRUCTIONS
  end

  def content_instructions
    <<~INSTRUCTIONS
      You translate the body of a help-center article into #{resolved_language}.

      Translate only the text a reader is meant to read. Leave every structural
      and technical element exactly as it is, including:
      - Markdown syntax: headings, emphasis, links, lists, tables, blockquotes,
        code spans and fenced code blocks, and horizontal rules.
      - HTML tags and their attributes, unless an attribute holds translated
        prose (never translate URLs, ids, classes, or data attributes).
      - URLs, image sources, and the alt text/attributes of links and images.
      - Iframes, embedded players, and any other raw HTML blocks.
      - Line breaks, blank lines, and indentation.

      Answer with the translated body only. Do not wrap it in code fences and do
      not add explanations.
    INSTRUCTIONS
  end

  def resolved_language
    language_map[target_language.to_s].presence || target_language
  end

  def language_map
    @language_map ||= YAML.load_file(Rails.root.join('config/languages/language_map.yml'))
  rescue Errno::ENOENT
    {}
  end

  def event_name
    'article_translation'
  end
end
