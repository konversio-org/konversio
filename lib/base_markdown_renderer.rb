require 'nokogiri'
require 'uri'
require 'cgi'

class BaseMarkdownRenderer
  include MarkdownRendererUrlSanitizer

  def render(doc_or_text)
    html = if doc_or_text.is_a?(String)
             Commonmarker.to_html(doc_or_text, options: { extension: { strikethrough: true } })
           elsif doc_or_text.respond_to?(:to_html)
             doc_or_text.to_html
           else
             doc_or_text.to_s
           end

    process_html(html)
  end

  private

  def process_html(html)
    doc = Nokogiri::HTML.fragment(html)
    sanitize_dangerous_urls(doc)
    adjust_image_tags(doc)
    doc.to_html
  end

  # Use inline style instead of HTML width/height attributes: email clients
  # and the in-app Letter view both run images through CSS (e.g. prose /
  # lettersanitizer's `img { height: auto }`) which overrides presentational
  # attributes. Inline style has higher specificity and survives.
  def adjust_image_tags(doc)
    doc.css('img').each do |img|
      src = img['src']
      next if src.blank?

      sizing_style = extract_image_sizing_style(src)
      img['style'] = sizing_style if sizing_style
    end
  end
end
