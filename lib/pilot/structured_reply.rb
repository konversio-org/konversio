# Value object for a Pilot AI reply expressed as an ordered list of parts, each
# carrying its customer-visible text and the numeric indexes of the knowledge
# results it relies on.
#
# Parsing is deliberately permissive: any raw model output is normalised into
# this shape, and plain/unstructured output degrades to a single citation-free
# part. Citation indexes are always resolved to customer-visible URLs on the
# server (see `Pilot::Assistant#trusted_citation_urls`); this object only
# renders links for the URLs it is given and silently drops the rest.
class Pilot::StructuredReply
  # A single reply part: its text plus the knowledge-result indexes it cites.
  Part = Struct.new(:text, :citations, keyword_init: true) do
    def indexes
      citations
    end
  end

  # Index-bearing keys accepted from model output. Our prompt uses
  # `source_indexes`; the alternatives keep parsing tolerant of small format
  # drift without accepting model-supplied URLs.
  CITATION_KEYS = %i[citations source_indexes indexes].freeze

  # Text-bearing keys accepted when a hash is not in the structured parts form.
  TEXT_KEYS = %i[text content response].freeze

  attr_reader :parts

  class << self
    def parse(raw)
      new(parse_parts(raw))
    end

    def normalize_citations(values)
      Array(values).filter_map { |value| positive_integer(value) }.uniq
    end

    private

    def parse_parts(raw)
      case raw
      when nil then []
      when String then parse_string(raw)
      when Hash then parse_hash(raw)
      when Array then parse_parts_list(raw)
      else parse_string(raw.to_s)
      end
    end

    # A string may still be JSON (the model returned structured output as text);
    # only fall back to a single plain part when it does not decode to a hash or
    # array.
    def parse_string(raw)
      text = raw.strip
      return [] if text.empty?

      if text.start_with?('{', '[')
        decoded = begin
          JSON.parse(text)
        rescue JSON::ParserError
          nil
        end
        return parse_parts(decoded) if decoded.is_a?(Hash) || decoded.is_a?(Array)
      end

      [{ text: text, citations: [] }]
    end

    def parse_hash(raw)
      parts = raw[:parts] || raw['parts']
      return parse_parts_list(parts) if parts.is_a?(Array)

      TEXT_KEYS.each do |key|
        value = raw[key] || raw[key.to_s]
        return [{ text: value.to_s, citations: [] }] if value.is_a?(String)
      end

      []
    end

    def parse_parts_list(list)
      Array(list).filter_map do |entry|
        next unless entry.is_a?(Hash)

        text = entry[:text] || entry['text']
        next unless text.is_a?(String)
        next if text.strip.empty?

        citations = CITATION_KEYS.flat_map { |key| Array(entry[key] || entry[key.to_s]) }
        { text: text.strip, citations: normalize_citations(citations) }
      end
    end

    def positive_integer(value)
      case value
      when Integer then value.positive? ? value : nil
      when String then value.match?(/\A\d+\z/) && value.to_i.positive? ? value.to_i : nil
      end
    end
  end

  # Builds a reply from already-normalised parts (each responding to `text` and
  # `citations`).
  def initialize(parts = [])
    @parts = Array(parts).map { |part| build_part(part) }
  end

  def plain_text
    parts.map(&:text).join("\n\n")
  end

  def empty?
    parts.empty?
  end

  def present?
    !empty?
  end

  def used_indexes
    parts.flat_map(&:citations).uniq
  end

  # A copy with every part's citations emptied; text and order are preserved.
  def without_citations
    self.class.new(parts.map { |part| Part.new(text: part.text, citations: []) })
  end

  # A copy with each part's text transformed by the given block. Used to strip
  # handoff/resolution sentinels before delivery without touching citations.
  def transform_texts(&block)
    return self unless block

    self.class.new(parts.map { |part| Part.new(text: yield(part.text), citations: part.citations) })
  end

  # The ordered parts in the shape persisted on the outgoing message.
  def as_message_parts
    parts.map { |part| { 'text' => part.text, 'citations' => part.citations } }
  end

  # Renders the customer-facing content: each part's text followed by its
  # citations as numbered markdown links. Display numbers are assigned per
  # unique URL in first-appearance order and reused for repeats; indexes with
  # no eligible URL are dropped silently.
  def render(citation_urls = {})
    urls = normalize_urls(citation_urls)
    numbers = {}

    rendered = parts.filter_map do |part|
      next if part.text.blank?

      append_links(part, urls, numbers)
    end

    rendered.join("\n\n")
  end

  private

  def build_part(part)
    return part if part.is_a?(Part)

    Part.new(
      text: part[:text] || part['text'],
      citations: self.class.normalize_citations(part[:citations] || part['citations'])
    )
  end

  def normalize_urls(citation_urls)
    return {} unless citation_urls.respond_to?(:to_h)

    citation_urls.to_h.each_with_object({}) do |(index, url), urls|
      urls[index.to_i] = url if url.present?
    end
  end

  def append_links(part, urls, numbers)
    links = part.citations.filter_map do |index|
      url = urls[index]
      next if url.blank?

      number = numbers[url] ||= numbers.size + 1
      "[#{number}](#{escape_markdown_url(url)})"
    end

    return part.text if links.empty?

    joined = links.join(' ')
    return "#{part.text}\n#{joined}" if part.text.end_with?('```')

    "#{part.text} #{joined}"
  end

  def escape_markdown_url(url)
    url.to_s.gsub('(', '%28').gsub(')', '%29')
  end
end
