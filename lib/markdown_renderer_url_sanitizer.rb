module MarkdownRendererUrlSanitizer
  # Match the commonmarker safe renderer while retaining application protocols such as mention://.
  DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
  SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i

  private

  def sanitize_dangerous_urls(doc)
    doc.css('a').each { |anchor| anchor['href'] = sanitized_url(anchor['href']) }
    doc.css('img').each { |img| img['src'] = sanitized_url(img['src']) }
  end

  def sanitized_url(url)
    url = url.to_s.strip
    return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)

    url
  end

  # Drag-resize from the reply editor encodes the chosen width as cw_image_width
  # on the URL; the older message-signature picker uses cw_image_height. Width
  # wins when both are set so the agent's most recent intent is honored.
  def extract_image_sizing_style(src)
    query_params = parse_query_params(src)
    width = sanitize_pixel_value(query_params['cw_image_width']&.first)
    return "width: #{width}; max-width: 100%; height: auto;" if width

    height = sanitize_pixel_value(query_params['cw_image_height']&.first)
    height ? "height: #{height};" : nil
  end

  # Only allow a bounded `<digits>px` value so the decoded query param can't
  # break out of the inline style attribute (HTML attribute injection).
  def sanitize_pixel_value(raw)
    return unless raw =~ /\A(\d+)px\z/

    px = Regexp.last_match(1).to_i
    "#{px}px" if px.between?(1, 2000)
  end

  def parse_query_params(url)
    parsed_url = URI.parse(url)
    CGI.parse(parsed_url.query || '')
  rescue URI::InvalidURIError
    {}
  end
end
