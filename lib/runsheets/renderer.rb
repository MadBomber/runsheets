# frozen_string_literal: true

require "cgi/escape"
require "kramdown"
require "kramdown-parser-gfm"
require "rouge"

module Runsheets
  # Markdown to HTML, with executable blocks wrapped in the markup the page's
  # JavaScript needs (data attributes, toolbar, output area).
  module Renderer
    Result = Data.define(:html, :blocks)

    ROUGE_THEME = "base16.monokai.dark"

    # Rouge formatter that wraps block output the way kramdown's layout
    # expects (<div class="highlight"><pre class="highlight"><code>) without
    # going through the deprecated HTMLLegacy formatter. kramdown passes
    # wrap: false for inline code spans.
    class CodeFormatter < Rouge::Formatters::HTML
      def initialize(opts = {})
        super()
        @css_class = opts[:css_class] || "highlight"
        @wrap      = opts[:wrap] != false
      end

      def stream(tokens, &)
        return super unless @wrap

        yield %(<div class="#{@css_class}"><pre class="#{@css_class}"><code>)
        super
        yield "</code></pre></div>"
      end
    end

    KRAMDOWN_OPTIONS = {
      input:                   "GFM",
      hard_wrap:               false,
      syntax_highlighter:      "rouge",
      syntax_highlighter_opts: { css_class: "highlight", formatter: CodeFormatter }
    }.freeze

    # kramdown HTML converter that recognises the "lang?rs=N" marker Fences
    # plants and wraps the Nth block.
    class HtmlConverter < Kramdown::Converter::Html
      public_class_method :new

      MARKER = /\A(.*?)\?rs=(\d+)\z/

      attr_accessor :blocks

      def convert_codeblock(el, indent)
        match = el.options[:lang].to_s.match(MARKER)
        block = match && blocks&.[](match[2].to_i)
        return super unless block

        if match[1].empty?
          el.options.delete(:lang)
          el.attr.delete("class")
        else
          el.options[:lang]  = match[1]
          el.attr["class"]   = "language-#{match[1]}"
        end

        Renderer.wrap_block(block, super, indent)
      end
    end

    # Render markdown. Blocks get ids "#{id_prefix}-1", "#{id_prefix}-2", ...
    # +interpreters+ decides which languages can execute.
    def self.render(markdown, id_prefix:, interpreters: Block::INTERPRETERS)
      rewritten, fences = Fences.extract(markdown)
      blocks = fences.map.with_index do |fence, i|
        Block.new(id: "#{id_prefix}-#{i + 1}", index: i, info: fence.info, code: fence.code, line: fence.line, interpreters:)
      end
      link_expectations(blocks)

      doc       = Kramdown::Document.new(rewritten, **KRAMDOWN_OPTIONS)
      options   = Kramdown::Options.merge(doc.options.merge(doc.root.options[:options] || {}))
      converter = HtmlConverter.new(doc.root, options)
      converter.blocks = blocks

      Result.new(html: strip_meta(converter.convert(doc.root)), blocks:)
    end

    # Render markdown as plain HTML: nothing is executable, so no block is
    # wrapped. For prose outside a runbook, such as a library folder's README.
    def self.render_plain(markdown) = strip_meta(Kramdown::Document.new(markdown, **KRAMDOWN_OPTIONS).to_html)

    # Remove <meta> tags from rendered markdown. A meta refresh would
    # navigate the page wherever the markdown says, and no Content-Security-
    # Policy stops one; a runbook has no use for any other <meta>.
    def self.strip_meta(html) = html.gsub(/<meta\b[^>]*>/i, "")

    def self.h(value) = CGI.escapeHTML(value.to_s)

    # An expect block illustrates the nearest executable block above it.
    def self.link_expectations(blocks)
      last = nil
      blocks.each do |block|
        if block.executable?
          last = block
        elsif block.expect? && last
          block.expect_for = last.id
        end
      end
      blocks
    end

    # The <div class="rs-block"> wrapper around a highlighted code block.
    def self.wrap_block(block, code_html, indent = 0)
      pad     = " " * indent
      classes = ["rs-block", "rs-#{block.kind}"]
      classes << "rs-executable" if block.executable?
      classes << "rs-warned" if block.warnings.any?
      attrs = %(id="block-#{h block.id}" data-block="#{h block.id}" data-kind="#{block.kind}" data-lang="#{h block.lang}")
      attrs += %( data-expect-for="#{h block.expect_for}") if block.expect_for

      <<~HTML
        #{pad}<div class="#{classes.join(' ')}" #{attrs}>
        #{pad}<div class="rs-toolbar">#{toolbar(block)}</div>
        #{code_html.chomp}
        #{pad}<div class="rs-result" hidden><div class="rs-panes"><pre class="rs-output" data-role="output"></pre><div class="rs-expected" data-role="expected" hidden><div class="rs-pane-title">expected</div><pre></pre></div></div><div class="rs-exit" data-role="exit"></div></div>
        #{pad}</div>
      HTML
    end

    NOTES = {
      terminal:   "run this in your own terminal, then confirm",
      expect:     "expected output",
      background: "runs until stopped or the run ends"
    }.freeze

    def self.toolbar(block)
      parts = ["<span class=\"rs-badge rs-#{block.kind}\">#{h block.label}</span>"]
      block.warnings.each { parts << "<span class=\"rs-warning\" title=\"authoring warning\">#{h it}</span>" }
      if block.expect_for
        parts << "<span class=\"rs-note\">expected output of <a href=\"#block-#{h block.expect_for}\">#{h block.expect_for}</a></span>"
      elsif NOTES.key?(block.kind)
        parts << "<span class=\"rs-note\">#{h NOTES[block.kind]}</span>"
      end
      parts << '<span class="rs-spacer"></span>'
      parts << '<button type="button" class="rs-btn rs-copy" data-action="copy" title="Copy to clipboard">Copy</button>'
      parts.concat(action_buttons(block))
      parts << '<span class="rs-status" data-role="status" role="status" aria-live="polite"></span>'
      parts.join
    end

    # The buttons that act on a block: Start and Stop, Run, or I ran this,
    # each labelled with the block id for screen readers.
    def self.action_buttons(block)
      id = h(block.id)
      if block.background?
        [%(<button type="button" class="rs-btn rs-run" data-action="execute" aria-label="Start #{id}">Start</button>),
         %(<button type="button" class="rs-btn rs-stop" data-action="stop" hidden>Stop</button>)]
      elsif block.executable?
        label = block.destructive? ? "Run (destructive)" : "Run"
        style = block.destructive? ? "rs-btn rs-run rs-danger" : "rs-btn rs-run"
        [%(<button type="button" class="#{style}" data-action="execute" aria-label="#{label} #{id}">#{label}</button>)]
      elsif block.acknowledgeable?
        [%(<button type="button" class="rs-btn rs-ack" data-action="acknowledge" aria-label="I ran #{id}">I ran this</button>)]
      else
        []
      end
    end

    # The first level-one heading of a markdown document, or nil.
    def self.title_of(markdown) = without_fences(markdown)[/^#[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*\r?$/, 1]

    # Markdown with its fenced code blocks taken out.
    def self.without_fences(markdown) = markdown.to_s.gsub(/^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[`~]*[ \t]*\r?$/m, "")

    # Point relative <img src> and <a href> values at the /files/ route so
    # assets that sit next to a markdown file resolve, and links (not images)
    # to markdown files at the /docs/ route, which renders them. base_dir is the file's
    # directory relative to the runbook root ('' for the root).
    def self.rewrite_relative_urls(html, base_dir, prefix: "/files")
      html.gsub(/(<(img|a)\b[^>]*\b(?:src|href)=")([^"]*)(")/) do
        before, tag, url, after = Regexp.last_match.captures
        if url.match?(%r{\A([a-z][a-z0-9+.-]*:|/|#|\?)}i)
          "#{before}#{url}#{after}"
        else
          joined = join_relative(base_dir, url)
          route  = tag == "a" && markdown_path?(joined.to_s) ? "/docs" : prefix
          "#{before}#{joined ? "#{route}/#{joined}" : url}#{after}"
        end
      end
    end

    def self.markdown_path?(path) = path.match?(/\.md(?:[#?]|\z)/i)

    # Make every /docs/ link in +html+ that leads to a plain document under
    # +root+ open in a new tab; links to a runbook or one of its files stay
    # in the tab, since they navigate the runbooks rather than open
    # reference reading.
    def self.open_documents_in_new_tab(html, root)
      html.gsub(%r{(<a\b[^>]*\bhref="/docs/([^"#?]*)[^"]*")}) do
        link, path = Regexp.last_match.captures
        Runbook.plain_document?(File.join(root, CGI.unescapeURIComponent(path)), root) ? %(#{link} target="_blank" rel="noopener") : link
      end
    end

    # Join a relative href onto a base directory, resolving '.' and '..'.
    # Returns nil if the href climbs above the root.
    def self.join_relative(base_dir, href)
      parts = base_dir.to_s.split("/").reject { it.empty? || it == "." }
      href.to_s.split("/").each do |part|
        case part
        when "", "." then next
        when ".."    then parts.pop.nil? and return nil
        else parts << part
        end
      end
      parts.join("/")
    end

    def self.code_stylesheet = Rouge::Theme.find(ROUGE_THEME).render(scope: ".highlight")
  end
end
