require 'rails_helper'

RSpec.describe KonversioMarkdownRenderer do
  let(:markdown_content) { 'This is a *test* content with ^markdown^' }
  let(:renderer) { described_class.new(markdown_content) }

  describe '#render_article' do
    let(:rendered_content) { renderer.render_article }

    it 'renders the markdown content to html' do
      expect(rendered_content.to_s).to eq("<p>This is a <em>test</em> content with <sup>markdown</sup></p>\n")
    end

    it 'returns an html safe string' do
      expect(rendered_content).to be_html_safe
    end

    context 'when tables in markdown' do
      let(:markdown_content) do
        <<~MARKDOWN
          This is a **bold** text and *italic* text.

          | Header1      | Header2      |
          | ------------ | ------------ |
          | **Bold Cell**| *Italic Cell*|
          | Cell3        | Cell4        |
        MARKDOWN
      end

      it 'renders tables wrapped in tableWrapper' do
        expect(rendered_content.to_s).to include('<div class="tableWrapper">')
        expect(rendered_content.to_s).to include('<table>')
        expect(rendered_content.to_s).to include('<strong>Bold Cell</strong>')
      end
    end
  end

  describe '#render_message' do
    let(:rendered_message) { renderer.render_message }

    it 'renders the markdown message to html' do
      expect(rendered_message.to_s).to eq("<p>This is a <em>test</em> content with ^markdown^</p>\n")
    end

    it 'returns an html safe string' do
      expect(rendered_message).to be_html_safe
    end

    context 'with bare URLs' do
      let(:markdown_content) { 'Visit https://example.com for details' }

      it 'converts bare URLs to links' do
        expect(renderer.render_message.to_s).to eq("<p>Visit <a href=\"https://example.com\">https://example.com</a> for details</p>\n")
      end
    end
  end

  describe '#render_markdown_to_plain_text' do
    let(:rendered_content) { renderer.render_markdown_to_plain_text }

    it 'renders the markdown content to plain text' do
      expect(rendered_content).to eq('This is a test content with ^markdown^')
    end
  end
end
