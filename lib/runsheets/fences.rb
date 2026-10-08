# frozen_string_literal: true

module Runsheets
  # Finds fenced code blocks in markdown and rewrites their info strings.
  #
  # kramdown's GFM parser only accepts a single word as the info string, so
  # "```bash run" is not even recognised as a code block. Before rendering,
  # every fence with an info string is rewritten to "lang?rs=N" where N is
  # the fence's index. kramdown passes "lang?opts" through as the language,
  # which Renderer::HtmlConverter intercepts to wrap block N.
  module Fences
    Fence = Data.define(:info, :code, :line)

    MARKER = "?rs="
    OPEN   = /\A( {0,3})(`{3,}|~{3,})[ \t]*(.*?)[ \t]*\z/

    # Returns [rewritten markdown, fences]. Fences without an info string are
    # tracked (so their contents are never mistaken for fences) but not
    # returned, since display-only blocks need no identity.
    def self.extract(markdown)
      lines  = []
      fences = []
      open   = nil
      code   = []

      markdown.each_line(chomp: true).with_index(1) do |line, number|
        if open
          if closes?(line, open)
            fences << build(open, code) if open[:info]
            open = nil
            code = []
          else
            code << line
          end
          lines << line
        elsif (match = line.match(OPEN))
          open = { char: match[2][0], len: match[2].size, indent: match[1].size,
                   info: (match[3] unless match[3].empty?), line: number }
          lines << (open[:info] ? "#{match[1]}#{match[2]}#{lang_of(open[:info])}#{MARKER}#{fences.size}" : line)
        else
          lines << line
        end
      end

      fences << build(open, code) if open && open[:info]
      ["#{lines.join("\n")}\n", fences]
    end

    # The first word of an info string.
    def self.lang_of(info) = info.split.first.to_s

    # True when line is a closing fence for the open one.
    def self.closes?(line, open)
      line.match?(/\A {0,3}#{Regexp.escape(open[:char])}{#{open[:len]},}[ \t]*\z/)
    end

    # Remove up to +indent+ leading spaces from each code line, as kramdown does
    # for fences nested inside list items.
    def self.dedent(lines, indent)
      return "" if lines.empty?

      pattern = /\A {0,#{indent}}/
      "#{lines.map { it.sub(pattern, '') }.join("\n")}\n"
    end

    def self.build(open, code)
      Fence.new(info: open[:info], code: dedent(code, open[:indent]), line: open[:line])
    end
    private_class_method :build
  end
end
