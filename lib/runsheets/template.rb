# frozen_string_literal: true

require "erb"

module Runsheets
  # A starter runbook that `runsheets --new` fills in: a directory under
  # templates/ at the gem root holding a directory runbook. Files ending in
  # .erb are rendered (the suffix dropped); any other file is copied as is.
  #
  #   templates/asgard/
  #     template.yml           order: and description: for the --new menu
  #     runbook.md.erb
  #     steps/010-preflight.md.erb
  #     verify.md.erb          (optional)
  #     rollback.md.erb        (optional)
  #     .loki                  support files: anything else, copied beside
  #
  # Each template is written once, in the directory shape. A single-file
  # runbook is made from the rendered files (see .single_file), so the two
  # shapes cannot drift apart. Step bodies must therefore use ### and
  # deeper headings: a ## heading would start a new step in a single file.
  class Template
    DIR     = File.expand_path("../../templates", __dir__)
    DEFAULT = "tasks"
    META    = "template.yml"

    # What the ERB sees. +yaml+ quotes a value for front matter, so a title
    # such as "null" or "yes: no" stays a string.
    Context = Data.define(:name, :title, :when_to_use, :escalation, :single_file) do
      def yaml(value) = value.to_s.to_json
      def binding_for = binding
    end

    # A template without an order in template.yml sorts after those with one.
    UNORDERED = 1_000

    attr_reader :name, :dir, :description, :order

    # Every template under +root+, by the order in its template.yml, then
    # by name.
    def self.all(root: DIR)
      Dir.glob("*/", base: root).map { new(File.join(root, it.chomp("/"))) }.sort_by { [it.order, it.name] }
    end

    # Whether +rel+, a rendered path, is part of the runbook itself rather
    # than a support file: runbook.md, a step, verify.md or rollback.md.
    def self.runbook_file?(rel)
      rel == "runbook.md" || rel.match?(%r{\A#{Runbook::STEPS_DIR}/[^/]+\.md\z}) || Runbook::EXTRAS.any? { rel == "#{it}.md" }
    end

    # The rendered files that are not the runbook's own markdown.
    def self.support_files(files) = files.reject { |rel, _| runbook_file?(rel) }

    def initialize(dir)
      @dir  = dir
      @name = File.basename(dir)
      meta  = File.file?(meta_path) ? YAML.safe_load_file(meta_path, aliases: false) : {}
      meta  = {} unless meta.is_a?(Hash)
      @description = meta["description"].to_s
      @order       = Integer(meta["order"], exception: false) || UNORDERED
    end

    # The rendered directory runbook: relative path => text. An .erb file
    # is rendered with +context+ and loses the suffix; others are copied.
    def render(context)
      sources.to_h do |rel|
        text = File.read(File.join(dir, rel))
        next [rel, text] unless rel.end_with?(".erb")

        [rel.delete_suffix(".erb"), ERB.new(text, trim_mode: "-").result(context.binding_for)]
      end
    end

    # The template's files, relative to its directory, sorted: everything,
    # dotfiles included, but template.yml.
    def sources
      Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).select { File.file?(File.join(dir, it)) }.reject { it == META }.sort
    end

    # Whether the template brings files besides the runbook's markdown, such
    # as asgard's .loki files. A single-file runbook from it gets a folder.
    def support_files? = sources.any? { !self.class.runbook_file?(it.delete_suffix(".erb")) }

    # One single-file runbook made from rendered directory files: runbook.md
    # as the front matter and preamble, then a ## section per step in
    # order, then Verify and Rollback. Each file's front matter, less its
    # title, becomes the attribute comment under its heading.
    def self.single_file(files)
      steps    = files.keys.select { runbook_file?(it) && it.start_with?("#{Runbook::STEPS_DIR}/") }.sort_by { [File.basename(it)[/\A\d+/].to_i, it] }
      extras   = Runbook::EXTRAS.map { "#{it}.md" }.select { files.key?(it) }
      sections = (steps + extras).map { section(files[it], fallback: File.basename(it, ".md")) }
      [files.fetch("runbook.md").rstrip, *sections].join("\n\n") << "\n"
    end

    # A ## section from one step file's text.
    def self.section(text, fallback:)
      parsed  = FrontMatter.parse(text)
      title   = parsed.data["title"] || fallback.sub(/\A\d+[-_]?/, "").tr("-_", " ").capitalize
      attrs   = parsed.data.except("title")
      heading = "## #{title}"
      heading += "\n<!-- #{attributes(attrs)} -->" unless attrs.empty?
      "#{heading}\n\n#{parsed.body.strip}"
    end

    # { "kind" => "automated", "timeout" => 300 } => "kind: automated, timeout: 300".
    # A string YAML would read as something else (yes, 010, a: b) is quoted.
    def self.attributes(data)
      data.map do |key, value|
        plain = value.is_a?(String) && value.match?(%r{\A[A-Za-z][\w./-]*\z}) && YAML.safe_load(value) == value
        "#{key}: #{plain || !value.is_a?(String) ? value : value.to_json}"
      end.join(", ")
    end

    private

    def meta_path = File.join(dir, META)
  end
end
