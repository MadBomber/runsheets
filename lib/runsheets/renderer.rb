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
        @wrap      = opts.fetch(:wrap, true)
      end

      def stream(tokens, &block)
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
    def self.render(markdown, id_prefix:)
      rewritten, fences = Fences.extract(markdown)
      blocks = fences.each_with_index.map do |fence, i|
        Block.new(id: "#{id_prefix}-#{i + 1}", index: i, info: fence.info, code: fence.code, line: fence.line)
      end

      doc       = Kramdown::Document.new(rewritten, **KRAMDOWN_OPTIONS)
      options   = Kramdown::Options.merge(doc.options.merge(doc.root.options[:options] || {}))
      converter = HtmlConverter.new(doc.root, options)
      converter.blocks = blocks

      Result.new(html: converter.convert(doc.root), blocks:)
    end

    def self.h(value) = CGI.escapeHTML(value.to_s)

    # The <div class="rs-block"> wrapper around a highlighted code block.
    def self.wrap_block(block, code_html, indent = 0)
      pad     = " " * indent
      classes = ["rs-block", "rs-#{block.kind}"]
      classes << "rs-executable" if block.executable?
      classes << "rs-warned" if block.warnings.any?

      <<~HTML
        #{pad}<div class="#{classes.join(' ')}" id="block-#{h block.id}" data-block="#{h block.id}" data-kind="#{block.kind}" data-lang="#{h block.lang}">
        #{pad}<div class="rs-toolbar">#{toolbar(block)}</div>
        #{code_html.chomp}
        #{pad}<div class="rs-result" hidden><pre class="rs-output" data-role="output"></pre><div class="rs-exit" data-role="exit"></div></div>
        #{pad}</div>
      HTML
    end

    NOTES = {
      terminal:   "run this in your own terminal",
      expect:     "expected output",
      background: "background processes are not executable yet"
    }.freeze

    def self.toolbar(block)
      parts = ["<span class=\"rs-badge rs-#{block.kind}\">#{h block.label}</span>"]
      block.warnings.each { parts << "<span class=\"rs-warning\" title=\"authoring warning\">#{h it}</span>" }
      parts << "<span class=\"rs-note\">#{h NOTES[block.kind]}</span>" if NOTES.key?(block.kind)
      parts << '<span class="rs-spacer"></span>'
      parts << '<button type="button" class="rs-btn rs-copy" data-action="copy" title="Copy to clipboard">Copy</button>'
      if block.executable?
        label = block.destructive? ? "Run (destructive)" : "Run"
        parts << "<button type=\"button\" class=\"rs-btn rs-run#{' rs-danger' if block.destructive?}\" data-action=\"execute\">#{label}</button>"
      end
      parts << '<span class="rs-status" data-role="status"></span>'
      parts.join
    end

    # The first level-one heading of a markdown document, or nil.
    def self.title_of(markdown) = markdown[/^\#[ \t]+(.+?)[ \t#]*$/, 1]

    # Point relative <img src> and <a href> values at the /files/ route so
    # assets that sit next to a markdown file resolve. base_dir is the file's
    # directory relative to the runbook root ('' for the root).
    def self.rewrite_relative_urls(html, base_dir, prefix: "/files")
      html.gsub(/(<(?:img|a)\b[^>]*\b(?:src|href)=")([^"]*)(")/) do
        before, url, after = Regexp.last_match.captures
        if url.match?(%r{\A([a-z][a-z0-9+.-]*:|/|#|\?)}i)
          "#{before}#{url}#{after}"
        else
          joined = join_relative(base_dir, url)
          "#{before}#{joined ? "#{prefix}/#{joined}" : url}#{after}"
        end
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
