require 'nokogiri'
require 'uri'
require 'cgi'

class BaseMarkdownRenderer
  def render(doc_or_text)
    html = if doc_or_text.is_a?(String)
             Commonmarker.to_html(doc_or_text, options: { extension: { strikethrough: true } })
           elsif doc_or_text.respond_to?(:to_html)
             doc_or_text.to_html
           else
             doc_or_text.to_s
           end

    adjust_image_tags(html)
  end

  private

  def adjust_image_tags(html)
    doc = Nokogiri::HTML.fragment(html)
    doc.css('img').each do |img|
      src = img['src']
      next if src.blank?

      begin
        parsed_url = URI.parse(src)
        query_params = CGI.parse(parsed_url.query || '')
        height = query_params['cw_image_height']&.first
        if height
          img['height'] = height
          img['width'] = 'auto'
        end
      rescue URI::InvalidURIError
      end
    end
    doc.to_html
  end
end
