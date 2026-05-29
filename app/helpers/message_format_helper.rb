module MessageFormatHelper
  def transform_user_mention_content(message_content)
    # attachment message without content, message_content is nil
    return '' unless message_content.presence

    KonversioMarkdownRenderer.new(message_content).render_markdown_to_plain_text
  end

  def render_message_content(message_content)
    KonversioMarkdownRenderer.new(message_content).render_message
  end
end
