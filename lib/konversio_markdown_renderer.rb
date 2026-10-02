require 'nokogiri'
require 'cgi'
require 'uri'
require 'yaml'

class KonversioMarkdownRenderer
  # Matches columnResizing({ cellMinWidth: 50 }) in @chatwoot/prosemirror-schema
  # so cells without an explicit colwidth render the same minimum here as in the editor.
  TABLE_CELL_MIN_WIDTH_PX = 50
  COLWIDTHS_COMMENT = /<!--cw-colwidths:([\d,]+)-->/
  COLWIDTHS_CODE = /\Acw-colwidths:([\d,]+)\z/

  def initialize(content)
    @content = content
  end

  def render_message
    return render_as_html_safe('') if @content.blank?

    # 1. Render markdown to HTML using Commonmarker 2.x
    html = Commonmarker.to_html(@content, options: { extension: { strikethrough: true, autolink: true } })

    # 2. Post-process to adjust images (formerly BaseMarkdownRenderer)
    processed_html = adjust_image_tags(html)

    render_as_html_safe(processed_html)
  end

  def render_article
    return render_as_html_safe('') if @content.blank?

    # 1. Render markdown to HTML using Commonmarker 2.x. The editor's table-width
    #    markers are HTML comments, which the safe renderer would strip, so encode
    #    them as inline code first and decode after rendering.
    html = Commonmarker.to_html(encode_colwidth_markers(@content), options: { extension: { table: true } })

    # 2. Post-process embeds, tables, and superscripts (formerly CustomMarkdownRenderer)
    processed_html = process_article_html(html)

    render_as_html_safe(processed_html)
  end

  def render_markdown_to_plain_text
    return '' if @content.blank?

    doc = Commonmarker.parse(@content)
    text = []
    doc.walk do |node|
      case node.type
      when :text, :code, :code_block
        text << node.string_content
      when :softbreak
        text << ' '
      when :linebreak
        text << "\n"
      end
    end
    text.join.strip
  end

  private

  def adjust_image_tags(html)
    doc = Nokogiri::HTML.fragment(html)
    doc.css('img').each do |img|
      src = img['src']
      next if src.blank?

      apply_image_sizing(img, src)
    end
    doc.to_html
  end

  def apply_image_sizing(img, src)
    width = extract_px_param(src, 'cw_image_width')
    if width
      img['style'] = "width: #{width}; max-width: 100%; height: auto;"
      return
    end

    height = query_param(src, 'cw_image_height')
    return unless height

    img['height'] = height
    img['width'] = 'auto'
  end

  def query_param(src, key)
    query = URI.parse(src).query
    query && CGI.parse(query)[key]&.first
  rescue URI::InvalidURIError
    nil
  end

  def extract_px_param(src, key)
    return unless query_param(src, key) =~ /\A(\d+)px\z/

    px = Regexp.last_match(1).to_i
    "#{px}px" if px.between?(1, 2000)
  end

  def process_article_html(html)
    doc = Nokogiri::HTML.fragment(html)

    process_tables(doc)
    process_embeds(doc)
    process_superscripts(doc)

    # Apply image sizing (cw_image_width / cw_image_height) for article images
    doc.css('img').each do |img|
      apply_image_sizing(img, img['src']) if img['src'].present?
    end

    doc.to_html
  end

  # Wrap tables in tableWrapper, consuming any preceding colwidths marker
  def process_tables(doc)
    doc.css('table').each do |table|
      widths = consume_colwidths(table)
      table.replace(table_wrapper_html(table, widths))
    end
  end

  # Process embedded links (equivalent to CustomMarkdownRenderer#link)
  def process_embeds(doc)
    doc.css('a').each do |a|
      link_url = a['href']
      next if link_url.blank?

      embed_html = find_matching_embed(link_url)
      next unless embed_html && isolated_link?(a)

      replace_link_with_embed(a, apply_embed_width(embed_html, link_url))
    end
  end

  def replace_link_with_embed(anchor, embed_html)
    parent = anchor.parent
    if parent && parent.name == 'p' && parent.children.reject { |c| c.text? && c.text.strip.empty? }.size == 1
      parent.replace(embed_html)
    else
      anchor.replace(embed_html)
    end
  end

  # Process superscripts (^text^) in text nodes (equivalent to CustomMarkdownRenderer#text)
  def process_superscripts(doc)
    doc.xpath('.//text()').each do |text_node|
      next if %w[script style code pre].include?(text_node.parent&.name)

      content = text_node.content
      next unless content.include?('^')

      segments = content.split(/(\^[^\^]+\^)/).map do |segment|
        if segment.start_with?('^') && segment.end_with?('^')
          "<sup>#{CGI.escapeHTML(segment[1..-2])}</sup>"
        else
          CGI.escapeHTML(segment)
        end
      end

      text_node.replace(Nokogiri::HTML.fragment(segments.join))
    end
  end

  # Replaces `<!--cw-colwidths:...-->` markers with an inline-code token so they
  # survive the safe CommonMarker render and can be decoded next to their table.
  def encode_colwidth_markers(content)
    content.gsub(COLWIDTHS_COMMENT) { "`cw-colwidths:#{Regexp.last_match(1)}`" }
  end

  # Consumes the inline-code marker paragraph the editor emits immediately before
  # a resized table and returns the widths, or nil for an unsized table.
  def consume_colwidths(table)
    node = table.previous_sibling
    node = node.previous_sibling while node&.text? && node.content.strip.empty?
    return nil unless node&.name == 'p'

    code = node.at_css('code')
    return nil unless code

    match = code.text.strip.match(COLWIDTHS_CODE)
    return nil unless match

    node.remove
    match[1].split(',').map(&:to_i)
  end

  def table_wrapper_html(table, widths)
    if sized_widths?(widths)
      %(<div class="tableWrapper"#{table_wrapper_style(widths)}>#{sized_table_html(table, widths)}</div>)
    else
      %(<div class="tableWrapper">#{table.to_html}</div>)
    end
  end

  def sized_widths?(widths)
    widths.is_a?(Array) && widths.any? { |w| w.to_i.positive? }
  end

  def fully_sized?(widths)
    widths.all? { |w| w.to_i.positive? }
  end

  # Fully-sized tables hug their exact width so the card doesn't trail empty space;
  # partial tables stay a plain full-width card so flexible columns can expand.
  def table_wrapper_style(widths)
    return '' unless fully_sized?(widths)

    %( style="width: #{total_width(widths)}px; max-width: 100%;")
  end

  # Total table width: each column's saved width, or the cell min for unsized ones.
  def total_width(widths)
    widths.sum { |w| w.to_i.positive? ? w.to_i : TABLE_CELL_MIN_WIDTH_PX }
  end

  # Fully sized → lock to the exact total (min-width too, so a narrow saved width
  # beats the portal's `[&_table]:!min-w-full`). Partial → `max(100%, total)` fills
  # the container (flexible columns) yet scrolls when the sized columns exceed it.
  def table_sizing_style(widths)
    total = total_width(widths)
    return "table-layout: fixed; min-width: max(100%, #{total}px) !important;" unless fully_sized?(widths)

    "table-layout: fixed; width: #{total}px !important; min-width: #{total}px !important;"
  end

  def colgroup_html(widths)
    cols = widths.map { |w| w.to_i.positive? ? %(<col style="width: #{w.to_i}px;">) : '<col>' }
    "<colgroup>#{cols.join}</colgroup>"
  end

  def sized_table_html(table, widths)
    table.to_html.sub(/<table[^>]*>/, %(<table style="#{table_sizing_style(widths)}">\n#{colgroup_html(widths)}))
  end

  # The editor stores a resized embed's width (cw_video_width) on the link.
  # Percentage padding (aspect-ratio boxes) resolves against the containing
  # block, so the saved width goes on a wrapper and the root fills it.
  def apply_embed_width(html, link_url)
    width = extract_px_param(link_url, 'cw_video_width')
    return html unless width

    fragment = Nokogiri::HTML.fragment(html)
    root = fragment.elements.first
    root['style'] = [root['style'], 'width: 100%; height: auto;'].compact.join(' ')
    %(<div style="width: #{width}; max-width: 100%;">#{fragment.to_html}</div>)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def isolated_link?(a)
    # Check preceding siblings
    curr = a.previous
    preceding_ok = false
    while curr
      if curr.name == 'br'
        preceding_ok = true
        break
      elsif curr.text?
        text = curr.content
        if text.include?("\n")
          preceding_ok = (text.split("\n").last || '').strip.empty?
          break
        else
          unless text.strip.empty?
            preceding_ok = false
            break
          end
        end
      else
        preceding_ok = false
        break
      end
      curr = curr.previous
    end
    preceding_ok = true if curr.nil?

    return false unless preceding_ok

    # Check succeeding siblings
    curr = a.next
    succeeding_ok = false
    while curr
      if curr.name == 'br'
        succeeding_ok = true
        break
      elsif curr.text?
        text = curr.content
        if text.include?("\n")
          succeeding_ok = (text.split("\n").first || '').strip.empty?
          break
        else
          unless text.strip.empty?
            succeeding_ok = false
            break
          end
        end
      else
        succeeding_ok = false
        break
      end
      curr = curr.next
    end
    succeeding_ok = true if curr.nil?

    preceding_ok && succeeding_ok
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def find_matching_embed(link_url)
    embed_regexes.each do |embed_key, regex|
      match = link_url.match(regex)
      next unless match

      return render_embed_from_match(embed_key, match)
    end

    nil
  end

  def embed_regexes
    @embed_regexes ||= embed_config.transform_values { |config| Regexp.new(config['regex']) }
  end

  def embed_config
    @embed_config ||= YAML.load_file(Rails.root.join('config/markdown_embeds.yml'))
  rescue Errno::ENOENT
    {}
  end

  def render_embed_from_match(embed_key, match_data)
    config = embed_config[embed_key]
    return nil unless config

    template = config['template']
    # Captured values land inside HTML attributes, so escape them before
    # substitution; an unescaped quote in a crafted URL would break out.
    match_data.named_captures.each do |var_name, value|
      template = template.gsub("%{#{var_name}}", CGI.escapeHTML(value))
    end
    template
  end

  def render_as_html_safe(html)
    # rubocop:disable Rails/OutputSafety
    html.html_safe
    # rubocop:enable Rails/OutputSafety
  end
end
