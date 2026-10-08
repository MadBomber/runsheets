# frozen_string_literal: true

module Runsheets
  # A runbook directory:
  #
  #   runbook.md        front matter + preamble (required)
  #   steps/*.md        ordered by filename
  #   verify.md         whole-procedure checks (optional)
  #   rollback.md       what to do when it fails partway (optional)
  #   assets/           images referenced by the markdown
  class Runbook
    Input = Data.define(:name, :prompt, :default, :secret) do
      def self.from(hash)
        hash = hash.transform_keys(&:to_s)
        new(name: hash["name"].to_s, prompt: hash["prompt"] || hash["name"].to_s,
            default: hash["default"]&.to_s, secret: hash["secret"] == true)
      end

      def secret? = secret
      def valid?  = name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
    end

    MAIN_FILE = "runbook.md"
    STEPS_DIR = "steps"
    EXTRAS    = %w[verify rollback].freeze

    attr_reader :dir, :slug, :data, :landing, :steps, :extras, :inputs, :warnings

    def self.load(dir) = new(dir)

    def initialize(dir)
      @dir = File.expand_path(dir)
      raise RunbookError, "not a directory: #{@dir}" unless File.directory?(@dir)

      main = File.join(@dir, MAIN_FILE)
      raise RunbookError, "#{MAIN_FILE} not found in #{@dir}" unless File.file?(main)

      @slug    = File.basename(@dir)
      parsed   = FrontMatter.parse(File.read(main, encoding: "UTF-8"))
      @data    = parsed.data
      @landing = Step.new(slug: "runbook", text: parsed.body, path: main, root: @dir)
      @steps   = load_steps
      @extras  = load_extras
      @inputs  = Array(data["inputs"]).map { Input.from(it) }.freeze
      @warnings = validate.freeze
    end

    def title         = (data["title"] || slug).to_s
    def when_to_use   = data["when_to_use"]
    def prerequisites = Array(data["prerequisites"])
    def blast_radius  = data["blast_radius"]
    def escalation    = data["escalation"]
    def last_verified = data["last_verified"]
    def tags          = Array(data["tags"]).map(&:to_s)
    def preamble_html = landing.html

    def verify   = extras["verify"]
    def rollback = extras["rollback"]

    def destructive? = !blast_radius.nil? || steps.any?(&:destructive?)

    # Every document that can be shown as a page, keyed by slug.
    def documents = @documents ||= ([landing, *steps, *extras.values]).to_h { [it.slug, it] }

    def step(slug) = documents[slug]

    # [step, block] for a block id, or nil.
    def find_block(id)
      documents.each_value do |step|
        block = step.block(id)
        return [step, block] if block
      end
      nil
    end

    # Previous and next numbered steps around a document (nil at the ends or
    # for documents that are not numbered steps).
    def neighbors(step)
      index = steps.index(step)
      return [nil, nil] unless index

      [index.positive? ? steps[index - 1] : nil, steps[index + 1]]
    end

    # Language => command that runs a file of that language.
    def interpreters
      @interpreters ||= Block::INTERPRETERS.merge(
        (data["interpreters"] || {}).to_h { |lang, command| [lang.to_s, Shellwords.split(command.to_s)] }
      ).freeze
    end

    def interpreter_for(lang) = interpreters[lang]

    def input(name) = inputs.find { it.name == name }

    def to_h
      { slug:, dir:, title:, when_to_use:, prerequisites:, blast_radius:, escalation:,
        last_verified: last_verified&.to_s, tags:, inputs: inputs.map(&:to_h),
        steps: steps.map(&:to_h), extras: extras.keys, warnings: }
    end

    private

    def load_steps
      steps_dir = File.join(dir, STEPS_DIR)
      return [] unless File.directory?(steps_dir)

      names = Dir.glob("*.md", base: steps_dir).sort_by { [it[/\A\d+/].to_i, it] }
      names.each_with_index.map { |name, i| Step.load(File.join(steps_dir, name), root: dir, position: i + 1) }
    end

    def load_extras
      EXTRAS.filter_map do |name|
        path = File.join(dir, "#{name}.md")
        [name, Step.load(path, root: dir)] if File.file?(path)
      end.to_h
    end

    def validate
      warnings = []
      warnings << "no steps found in #{STEPS_DIR}/" if steps.empty?
      warnings << "title missing from #{MAIN_FILE} front matter" unless data["title"]
      inputs.reject(&:valid?).each { warnings << "input name '#{it.name}' is not a valid environment variable name" }
      dupes = steps.map(&:slug).tally.select { |_, n| n > 1 }.keys
      warnings << "duplicate step slugs: #{dupes.join(', ')}" if dupes.any?
      documents.each_value do |step|
        step.warnings.each { warnings << "#{step.slug}: #{it}" }
      end
      warnings
    end
  end
end
