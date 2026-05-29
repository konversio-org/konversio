require 'nokogiri'
require 'cgi'
require 'uri'
require 'yaml'

class KonversioMarkdownRenderer
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

    # 1. Render markdown to HTML using Commonmarker 2.x
    html = Commonmarker.to_html(@content, options: { extension: { table: true } })

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

  def process_article_html(html)
    doc = Nokogiri::HTML.fragment(html)

    # 1. Wrap tables in tableWrapper (equivalent to CustomMarkdownRenderer#table)
    doc.css('table').each do |table|
      table.replace("<div class=\"tableWrapper\">#{table.to_html}</div>")
    end

    # 2. Process embedded links (equivalent to CustomMarkdownRenderer#link)
    doc.css('a').each do |a|
      link_url = a['href']
      next if link_url.blank?

      embed_html = find_matching_embed(link_url)
      next unless embed_html && isolated_link?(a)

      p = a.parent
      if p && p.name == 'p' && p.children.reject { |c| c.text? && c.text.strip.empty? }.size == 1
        p.replace(embed_html)
      else
        a.replace(embed_html)
      end
    end

    # 3. Process superscripts (^text^) in text nodes (equivalent to CustomMarkdownRenderer#text)
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

      new_node = Nokogiri::HTML.fragment(segments.join)
      text_node.replace(new_node)
    end

    doc.to_html
  end

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
    match_data.named_captures.each do |var_name, value|
      template = template.gsub("%{#{var_name}}", value)
    end
    template
  end

  def render_as_html_safe(html)
    # rubocop:disable Rails/OutputSafety
    html.html_safe
    # rubocop:enable Rails/OutputSafety
  end
end
