require 'nokogiri'
require 'uri'
require 'cgi'
require 'yaml'

class CustomMarkdownRenderer
  CONFIG_PATH = Rails.root.join('config/markdown_embeds.yml')

  def self.config
    @config ||= YAML.load_file(CONFIG_PATH)
  rescue Errno::ENOENT
    {}
  end

  def self.embed_regexes
    @embed_regexes ||= config.transform_values { |embed_config| Regexp.new(embed_config['regex']) }
  end

  def render(doc_or_text)
    html = if doc_or_text.is_a?(String)
             Commonmarker.to_html(doc_or_text, options: { extension: { table: true } })
           elsif doc_or_text.respond_to?(:to_html)
             doc_or_text.to_html
           else
             doc_or_text.to_s
           end

    process_article_html(html)
  end

  private

  def process_article_html(html)
    doc = Nokogiri::HTML.fragment(html)

    # 1. Wrap tables in tableWrapper
    doc.css('table').each do |table|
      table.replace("<div class=\"tableWrapper\">#{table.to_html}</div>")
    end

    # 2. Process embedded links
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

    # 3. Process superscripts (^text^) in text nodes
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
    self.class.embed_regexes.each do |embed_key, regex|
      match = link_url.match(regex)
      next unless match

      return render_embed_from_match(embed_key, match)
    end

    nil
  end

  def render_embed_from_match(embed_key, match_data)
    embed_config = self.class.config[embed_key]
    return nil unless embed_config

    template = embed_config['template']
    match_data.named_captures.each do |var_name, value|
      template = template.gsub("%{#{var_name}}", value)
    end
    template
  end
end
