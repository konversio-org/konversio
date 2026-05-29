class Messages::MarkdownRenderers::BaseMarkdownRenderer
  def initialize
    @buffer = []
    @node_stack = []
  end

  def render(node)
    @buffer = []
    @node_stack = []
    process(node)
    @buffer.join
  end

  def document(_node)
    out(:children)
  end

  def paragraph(_node)
    out(:children)
    cr
  end

  def text(node)
    out(node.string_content)
  end

  def softbreak(_node)
    out(' ')
  end

  def linebreak(_node)
    out("\n")
  end

  def strikethrough(_node)
    out('<del>')
    out(:children)
    out('</del>')
  end

  private

  def process(node)
    return if node.nil?

    @node_stack.push(node)
    method_name = node.type
    if method_name == :item
      method_name = :list_item
    elsif method_name == :heading
      method_name = :header
    elsif method_name == :block_quote
      method_name = :blockquote
    end

    if respond_to?(method_name, true)
      send(method_name, node)
    else
      method_missing(method_name, node)
    end
  ensure
    @node_stack.pop
  end

  def out(*args)
    args.each do |arg|
      if arg == :children
        current_node = @node_stack.last
        current_node.each { |child| process(child) } if current_node
      else
        @buffer << arg.to_s
      end
    end
  end

  def cr
    @buffer << "\n" unless @buffer.last == "\n" || @buffer.empty?
  end

  def plain
    yield
  end

  def method_missing(method_name, node = nil, *args, **kwargs, &)
    return super unless node.is_a?(Commonmarker::Node)

    out(:children)
    cr unless %i[text softbreak linebreak].include?(node.type)
  end

  def respond_to_missing?(_method_name, _include_private = false)
    true
  end
end
