require 'nokogiri'

# Shared column-width handling for the Help Center article renderers. The article
# editor serializes resized table columns as a `<!--cw-colwidths:...-->` HTML
# comment immediately before each table. Raw HTML is omitted from the rendered
# output (unsafe rendering stays off), so the widths are read from the parsed AST
# and mapped to the tables of the rendered Nokogiri fragment in document order.
module MarkdownTableColumnWidths
  # Matches columnResizing({ cellMinWidth: 50 }) in @chatwoot/prosemirror-schema
  # so cells without an explicit colwidth render the same minimum here as in the editor.
  TABLE_CELL_MIN_WIDTH_PX = 50
  COLWIDTHS_COMMENT = /<!--cw-colwidths:([\d,]+)-->/

  def extract_colwidths(content)
    return [] if content.blank?

    doc = Commonmarker.parse(content, options: { extension: { table: true } })
    widths = []
    pending = nil
    doc.walk do |node|
      if %i[html_block html].include?(node.type)
        match = node.to_commonmark.to_s.match(COLWIDTHS_COMMENT)
        pending = match[1].split(',').map(&:to_i) if match
      elsif node.type == :table
        widths << pending
        pending = nil
      end
    end
    widths
  end

  def sized_widths?(widths)
    widths.is_a?(Array) && widths.any? { |w| w.to_i.positive? }
  end

  def total_width(widths)
    widths.sum { |w| w.to_i.positive? ? w.to_i : TABLE_CELL_MIN_WIDTH_PX }
  end

  def apply_table_column_widths(table, widths)
    cols = widths.map { |w| %(<col style="width: #{w.to_i.positive? ? w.to_i : TABLE_CELL_MIN_WIDTH_PX}px;">) }
    colgroup = Nokogiri::HTML.fragment("<colgroup>#{cols.join}</colgroup>").children.first
    table.children.first&.add_previous_sibling(colgroup)
    table['style'] = 'table-layout: fixed; width: 100%;'
  end

  def table_wrapper(table, widths)
    if sized_widths?(widths)
      apply_table_column_widths(table, widths)
      %(<div class="tableWrapper" style="width: #{total_width(widths)}px; max-width: 100%;">#{table.to_html}</div>)
    else
      %(<div class="tableWrapper">#{table.to_html}</div>)
    end
  end
end
