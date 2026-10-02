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

  describe 'sized tables' do
    let(:plain_table) { "| A | B |\n| --- | --- |\n| 1 | 2 |\n" }

    def render_table(markdown)
      described_class.new(markdown).render_article.to_s
    end

    it 'does not emit the marker comment into the rendered html' do
      expect(render_table("<!--cw-colwidths:120,200-->\n#{plain_table}")).not_to include('cw-colwidths')
    end

    context 'when every column has a saved width' do
      it 'lays the table out at the total width with a sized colgroup' do
        output = render_table("<!--cw-colwidths:120,200-->\n#{plain_table}")

        expect(output).to include('<div class="tableWrapper" style="width: 320px; max-width: 100%;">')
        expect(output).to include('table-layout: fixed; width: 320px !important; min-width: 320px !important;')
        expect(output).to include('<col style="width: 120px;">')
        expect(output).to include('<col style="width: 200px;">')
      end
    end

    context 'when only some columns have a saved width' do
      it 'fills the container so unsized columns stay flexible, floored at the sized total' do
        output = render_table("<!--cw-colwidths:150,0-->\n#{plain_table}")

        expect(output).to include('table-layout: fixed; min-width: max(100%, 200px) !important;')
        expect(output).to include('<col style="width: 150px;">')
        expect(output).to include('<col>')
        expect(output).to include('<div class="tableWrapper"><table')
        expect(output).not_to include('width: 200px !important')
      end
    end

    it 'renders an unsized table full width' do
      expect(render_table(plain_table)).to include('<div class="tableWrapper"><table>')
    end

    it 'associates each marker with the table that follows it' do
      markdown = "#{plain_table}\n<!--cw-colwidths:150,250-->\n| P | Q |\n| --- | --- |\n| a | b |\n"
      output = render_table(markdown)

      expect(output).to include('<div class="tableWrapper"><table>')
      expect(output).to include('width: 400px !important;')
      expect(output).to include('<col style="width: 250px;">')
      expect(output.scan('colgroup').length).to eq(2)
    end
  end

  describe 'sized images and embeds' do
    def render_article(markdown)
      described_class.new(markdown).render_article.to_s
    end

    it 'renders an image width in px with responsive cap and auto height' do
      output = render_article('![Sample](https://example.com/image.jpg?cw_image_width=400px)')

      expect(output).to include('style="width: 400px; max-width: 100%; height: auto;"')
    end

    it 'ignores a non-numeric image width' do
      output = render_article('![Sample](https://example.com/image.jpg?cw_image_width=auto)')

      expect(output).not_to include('style=')
    end

    it 'sizes a video from a cw_video_width param without leaking it into the source' do
      output = render_article('[video](https://example.com/video.mp4?cw_video_width=480px)')

      expect(output).to include('<div style="width: 480px; max-width: 100%;">')
      expect(output).to match(/<video[^>]+style="width: 100%; height: auto;"/)
      expect(output).to include('<source src="https://example.com/video.mp4" type="video/mp4">')
    end

    it 'keeps percentage padding relative to the saved width' do
      output = render_article('[video](https://www.youtube.com/watch?v=VIDEO_ID&cw_video_width=480px)')

      expect(output).to include('<div style="width: 480px; max-width: 100%;">')
      expect(output).to include('padding-bottom: 62.5%; height: 0; width: 100%; height: auto;')
    end
  end
end
