# frozen_string_literal: true

module Runsheets
  # Finds fenced code blocks in markdown and rewrites their info strings.
  #
  # kramdown's GFM parser only accepts a single word as the info string, so
  # "```bash run" is not even recognised as a code block. Before rendering,
  # every fence with an info string is rewritten to "lang?rs=N" where N is
  # the fence's index. kramdown passes "lang?opts" through as the language,
  # which Renderer::HtmlConverter intercepts to wrap block N.
  #
  # Fences are found where kramdown finds them: at the top level (indented
  # up to three spaces), inside list items (indented to the item's content),
  # and inside blockquotes.
  module Fences
    Fence = Data.define(:info, :code, :line)

    MARKER    = "?rs="
    OPEN      = /\A( {0,3})(`{3,}|~{3,})[ \t]*(.*?)[ \t]*\z/
    INDENTED  = /\A( *)(`{3,}|~{3,})[ \t]*(.*?)[ \t]*\z/
    QUOTE     = /\A(?: {0,3}> ?)+/
    LIST_ITEM = /\A( *)([-*+]|\d{1,9}[.)])( {1,4}(?=\S)|[ \t]*\z)/

    # Reads markdown a line at a time and says what each line is to a
    # fence. Remembers the open fence and the list item a line may belong
    # to, which is all the context a fence needs.
    class Scanner
      def initialize
        @open        = nil
        @list_indent = nil
        @after_blank = true
      end

      def open? = !@open.nil?

      # One event per line:
      #   [:open, fence]  a fence opens; fence has :quote, :lead, :fence, :info, :indent
      #   [:code, text]   a line inside the fence, its blockquote marker removed
      #   [:close]        the fence's closing line
      #   [:text]         anything else
      # A fence in a blockquote ends where the blockquote does, as in
      # kramdown; the line that ends it is then read as text.
      def feed(line)
        if @open
          body = Fences.unquote(line, @open[:depth])
          return Fences.closes?(body, @open) ? close : [:code, body] if body

          @open = nil
        end
        opening(line) || text(line)
      end

      private

      def close
        @open = nil
        @after_blank = false
        [:close]
      end

      def opening(line)
        quote = line[QUOTE].to_s
        match = line[quote.size..].match(INDENTED) or return nil
        indent = match[1].size
        return nil unless indent <= 3 || in_list_item?(indent)

        @after_blank = false
        @open = { depth: quote.count(">"), char: match[2][0], len: match[2].size, indent:,
                  info: (match[3] unless match[3].empty?), quote:, lead: match[1], fence: match[2] }
        [:open, @open]
      end

      # A fence indented four or more spaces belongs to the list item above
      # it when it starts within three spaces of the item's content.
      def in_list_item?(indent) = !@list_indent.nil? && indent.between?(@list_indent, @list_indent + 3)

      def text(line)
        blank = line.strip.empty?
        if (item = line.match(LIST_ITEM))
          @list_indent = item[1].size + item[2].size + [item[3].size, 1].max
        elsif !blank && @after_blank && line[/\A */].size < @list_indent.to_i
          @list_indent = nil
        end
        @after_blank = blank
        [:text]
      end
    end

    # Returns [rewritten markdown, fences]. Fences without an info string are
    # tracked (so their contents are never mistaken for fences) but not
    # returned, since display-only blocks need no identity.
    def self.extract(markdown)
      scanner = Scanner.new
      lines   = []
      fences  = []
      open    = nil
      code    = []

      markdown.each_line(chomp: true).with_index(1) do |line, number|
        event, data = scanner.feed(line)
        if open && event != :code
          finish(fences, open, code)
          open = nil
          code = []
        end

        case event
        when :open
          open = data.merge(line: number)
          lines << opening_line(line, data, fences.size)
          next
        when :code
          code << data
        end
        lines << line
      end

      finish(fences, open, code) if open
      ["#{lines.join("\n")}\n", fences]
    end

    # The first word of an info string.
    def self.lang_of(info) = info.split.first.to_s

    # True when line is a closing fence for the open one: the same
    # character, at least as long, indented at most three spaces past the
    # opening fence's indent.
    def self.closes?(line, open)
      line.match?(/\A {0,#{open[:indent].to_i + 3}}#{Regexp.escape(open[:char])}{#{open[:len]},}[ \t]*\z/)
    end

    # +line+ with +depth+ blockquote markers removed, or nil when it has
    # fewer (the blockquote has ended). Depth 0 leaves the line alone, so
    # code inside a top-level fence may start with ">".
    def self.unquote(line, depth)
      return line if depth.zero?

      quote = line[QUOTE].to_s
      return nil if quote.count(">") < depth

      rest = line
      depth.times { rest = rest.sub(/\A {0,3}> ?/, "") }
      rest
    end

    # Remove up to +indent+ leading spaces from each code line, as kramdown does
    # for fences nested inside list items.
    def self.dedent(lines, indent)
      return "" if lines.empty?

      pattern = /\A {0,#{indent}}/
      "#{lines.map { it.sub(pattern, '') }.join("\n")}\n"
    end

    # The opening line as kramdown should see it: the info string replaced
    # by its language and the fence's index. A bare fence is left alone.
    def self.opening_line(line, open, index)
      info = open[:info] or return line
      "#{open[:quote]}#{open[:lead]}#{open[:fence]}#{lang_of(info)}#{MARKER}#{index}"
    end

    # Add the fence that just ended to +fences+, unless it is bare.
    def self.finish(fences, open, code)
      fences << build(open, code) if open[:info]
    end

    def self.build(open, code)
      Fence.new(info: open[:info], code: dedent(code, open[:indent]), line: open[:line])
    end
    private_class_method :build, :finish
  end
end
