require 'rails_helper'

RSpec.describe Pilot::StructuredReply do
  describe '.parse' do
    it 'degrades a plain string to a single citation-free part' do
      reply = described_class.parse('Just a plain answer.')

      expect(reply.parts.size).to eq(1)
      expect(reply.parts.first.text).to eq('Just a plain answer.')
      expect(reply.parts.first.citations).to eq([])
      expect(reply.plain_text).to eq('Just a plain answer.')
    end

    it 'parses structured parts in order, trimming text' do
      reply = described_class.parse(
        'parts' => [
          { 'text' => ' First. ', 'source_indexes' => [1, 2] },
          { 'text' => 'Second.', 'citations' => [2] }
        ]
      )

      expect(reply.parts.map(&:text)).to eq(['First.', 'Second.'])
      expect(reply.parts.map(&:citations)).to eq([[1, 2], [2]])
    end

    it 'parses a JSON string into structured parts' do
      reply = described_class.parse('{"parts":[{"text":"Answer","source_indexes":[3]}]}')

      expect(reply.parts.map(&:text)).to eq(['Answer'])
      expect(reply.parts.first.citations).to eq([3])
    end

    it 'drops malformed, blank, and non-text entries' do
      reply = described_class.parse(
        'parts' => [
          { 'text' => 'Kept.' },
          { 'text' => '   ' },
          { 'source_indexes' => [1] },
          'not a part',
          { 'text' => 'Also kept.' }
        ]
      )

      expect(reply.parts.map(&:text)).to eq(['Kept.', 'Also kept.'])
    end

    it 'treats a hash without parts as plain text' do
      reply = described_class.parse('response' => 'Fallback text.')

      expect(reply.parts.map(&:text)).to eq(['Fallback text.'])
    end
  end

  describe 'index normalization' do
    it 'keeps positive integers only, deduplicating in order' do
      reply = described_class.parse(
        'parts' => [{ 'text' => 'Hi', 'source_indexes' => [2, 2, 0, -1, '3', 'x', 1.5] }]
      )

      expect(reply.parts.first.citations).to eq([2, 3])
    end
  end

  describe '#plain_text' do
    it 'joins parts with a blank line' do
      reply = described_class.parse('parts' => [{ 'text' => 'One' }, { 'text' => 'Two' }])

      expect(reply.plain_text).to eq("One\n\nTwo")
    end
  end

  describe '#render' do
    let(:reply) do
      described_class.parse(
        'parts' => [
          { 'text' => 'First', 'source_indexes' => [1] },
          { 'text' => 'Second', 'source_indexes' => [1, 2] }
        ]
      )
    end

    it 'numbers unique URLs in first-appearance order and reuses them' do
      rendered = reply.render(1 => 'https://a.example/doc', 2 => 'https://b.example/doc')

      expect(rendered).to eq(
        "First [1](https://a.example/doc)\n\nSecond [1](https://a.example/doc) [2](https://b.example/doc)"
      )
    end

    it 'drops indexes without an eligible URL' do
      rendered = reply.render(2 => 'https://b.example/doc')

      expect(rendered).to eq("First\n\nSecond [1](https://b.example/doc)")
    end

    it 'places citation links on a new line after a code fence' do
      fenced = described_class.parse('parts' => [{ 'text' => "Example:\n```ruby\nx = 1\n```", 'source_indexes' => [1] }])

      rendered = fenced.render(1 => 'https://a.example/doc')

      expect(rendered).to end_with("```\n[1](https://a.example/doc)")
    end

    it 'markdown-escapes parentheses in URLs' do
      rendered = described_class.parse('parts' => [{ 'text' => 'See', 'source_indexes' => [1] }])
                                .render(1 => 'https://example.com/a_(b)')

      expect(rendered).to eq('See [1](https://example.com/a_%28b%29)')
    end
  end

  describe '#without_citations' do
    it 'preserves text and order with emptied citations' do
      reply = described_class.parse('parts' => [{ 'text' => 'One', 'source_indexes' => [1] }, { 'text' => 'Two' }])

      stripped = reply.without_citations

      expect(stripped.parts.map(&:text)).to eq(%w[One Two])
      expect(stripped.parts.map(&:citations)).to eq([[], []])
      expect(reply.parts.first.citations).to eq([1])
    end
  end
end
