# frozen_string_literal: true

module Runsheets
  # One markdown file of a runbook: a numbered step, or one of the extra
  # documents (runbook.md preamble, verify.md, rollback.md).
  class Step
    KINDS           = %w[automated manual verify].freeze
    DEFAULT_TIMEOUT = 600

    attr_reader :slug, :path, :position, :data, :body, :html, :blocks, :warnings

    # Load a markdown file. +root+ is the runbook directory, used to resolve
    # relative links; +position+ is the 1-based order among the steps.
    def self.load(path, root:, position: nil)
      new(slug: File.basename(path, ".*"), text: File.read(path, encoding: "UTF-8"), path:, root:, position:)
    end

    def initialize(slug:, text:, path: nil, root: nil, position: nil)
      @slug     = slug
      @path     = path
      @position = position

      parsed  = FrontMatter.parse(text)
      @data   = parsed.data
      @body   = parsed.body
      result  = Renderer.render(@body, id_prefix: slug)
      @blocks = result.blocks
      @html   = Renderer.rewrite_relative_urls(result.html, relative_dir(path, root))
      @warnings = validate.freeze
    end

    def title
      data["title"] || Renderer.title_of(body) || slug.sub(/\A\d+[-_]?/, "").tr("-_", " ").capitalize
    end

    def kind = (data["kind"] || (blocks.any?(&:executable?) ? "automated" : "manual")).to_s

    def automated? = kind == "automated"
    def manual?    = kind == "manual"
    def verify?    = kind == "verify"

    def destructive? = data["destructive"] == true || blocks.any?(&:destructive?)
    def timeout      = (data["timeout"] || DEFAULT_TIMEOUT).to_i
    def cwd          = data["cwd"]
    def number       = slug[/\A\d+/]

    def block(id)         = blocks.find { it.id == id }
    def executable_blocks = blocks.select(&:executable?)

    def to_h
      { slug:, position:, title:, kind:, destructive: destructive?, timeout:, cwd:, warnings:, blocks: blocks.map(&:to_h) }
    end

    private

    def relative_dir(path, root)
      return "" unless path && root

      dir = File.dirname(File.expand_path(path))
      dir.delete_prefix(File.expand_path(root)).delete_prefix("/")
    end

    def validate
      warnings = blocks.flat_map { |block| block.warnings.map { "block #{block.id}: #{it}" } }
      warnings << "kind '#{kind}' is not one of #{KINDS.join(', ')}" unless KINDS.include?(kind)
      warnings << "automated step has no executable block" if automated? && executable_blocks.empty?
      warnings << "timeout must be a positive number of seconds" unless timeout.positive?
      warnings
    end
  end
end
