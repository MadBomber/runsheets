# frozen_string_literal: true

module Runsheets
  # A runbook. Either a directory:
  #
  #   runbook.md        front matter + preamble (required)
  #   steps/*.md        ordered by filename
  #   verify.md         whole-procedure checks (optional)
  #   rollback.md       what to do when it fails partway (optional)
  #   assets/           images referenced by the markdown
  #
  # or a single markdown file whose `## Headings` are the steps (see
  # SingleFile). Everything downstream sees the same object either way.
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

    attr_reader :dir, :slug, :main_path, :data, :landing, :steps, :extras, :inputs, :warnings, :loaded_at

    # Load a runbook directory or a single-file runbook.
    def self.load(path)
      path = File.expand_path(path)
      if File.directory?(path)
        new(dir: path, main_path: File.join(path, MAIN_FILE), slug: File.basename(path), single_file: false)
      elsif File.file?(path)
        slug = File.basename(path, ".*")
        slug = File.basename(File.dirname(path)) if slug == File.basename(MAIN_FILE, ".*")
        new(dir: File.dirname(path), main_path: path, slug:, single_file: true)
      else
        raise RunbookError, "no such runbook: #{path}"
      end
    end

    def initialize(dir:, main_path:, slug:, single_file:)
      @dir         = dir
      @main_path   = main_path
      @slug        = slug
      @single_file = single_file
      raise RunbookError, "#{MAIN_FILE} not found in #{dir}" unless File.file?(main_path)

      @loaded_at = Time.now
      parsed     = FrontMatter.parse(File.read(main_path, encoding: "UTF-8"))
      @data      = parsed.data
      @section_warnings = []
      if single_file
        load_single_file(parsed.body)
      else
        @landing = Step.new(slug: "runbook", text: parsed.body, path: main_path, root: dir, interpreters:)
        @steps   = load_steps
        @extras  = load_extras
      end
      @inputs       = Array(data["inputs"]).map { Input.from(it) }.freeze
      @warnings     = validate.freeze
      @source_count = source_files.size
    end

    def single_file? = @single_file

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

    # The documents a verification run may execute: verify-kind steps in
    # order, then verify.md.
    def verify_documents = [*steps.select(&:verify?), verify].compact

    def verify_document?(step) = verify_documents.include?(step)

    def verify_blocks = verify_documents.flat_map(&:executable_blocks)

    # Set last_verified in a runbook's main file to +date+ by replacing that
    # one line of the front matter (or adding it before the closing ---).
    # This is the only write the tool ever makes inside a runbook. Returns
    # the new text.
    def self.stamp_last_verified(path, date)
      text  = File.read(path, encoding: "UTF-8")
      value = date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date.to_s
      match = text.match(/\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?$/m)
      raise RunbookError, "#{path} has no front matter to stamp" unless match

      body  = match[1]
      newl  = text.include?("\r\n") ? "\r\n" : "\n"
      line  = "last_verified: #{value}"
      body  = if body.match?(/^last_verified:.*$/)
                body.sub(/^last_verified:[^\r\n]*/, line)
              else
                "#{body}#{line}#{newl}"
              end
      text[match.begin(1)...match.end(1)] = body
      File.write(path, text)
      text
    end

    def stamp_last_verified(date) = Runbook.stamp_last_verified(main_path, date)

    # The markdown files this runbook was built from.
    def source_files
      return [main_path] if single_file?

      [main_path, *Dir.glob(File.join(dir, STEPS_DIR, "*.md")), *EXTRAS.map { File.join(dir, "#{it}.md") }].select { File.file?(it) }
    end

    # True once any source file has been written, added or removed since
    # this runbook was loaded.
    def stale?
      files = source_files
      return true if files.size != @source_count

      files.any? { File.mtime(it) > loaded_at }
    end

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

    # Language => command that runs a file of that language: the defaults
    # plus whatever the front matter adds or overrides.
    def interpreters
      @interpreters ||= Block::INTERPRETERS.merge(
        (data["interpreters"] || {}).to_h { |lang, command| [lang.to_s, Shellwords.split(command.to_s)] }
      ).freeze
    end

    def interpreter_for(lang) = interpreters[lang]

    def input(name) = inputs.find { it.name == name }

    def to_h
      { slug:, dir:, main_path:, single_file: single_file?, title:, when_to_use:, prerequisites:, blast_radius:, escalation:,
        last_verified: last_verified&.to_s, tags:, inputs: inputs.map(&:to_h),
        steps: steps.map(&:to_h), extras: extras.keys, warnings: }
    end

    private

    def load_steps
      steps_dir = File.join(dir, STEPS_DIR)
      return [] unless File.directory?(steps_dir)

      names = Dir.glob("*.md", base: steps_dir).sort_by { [it[/\A\d+/].to_i, it] }
      names.each_with_index.map { |name, i| Step.load(File.join(steps_dir, name), root: dir, position: i + 1, interpreters:) }
    end

    def load_extras
      EXTRAS.filter_map do |name|
        path = File.join(dir, "#{name}.md")
        [name, Step.load(path, root: dir, interpreters:)] if File.file?(path)
      end.to_h
    end

    # Preamble up to the first ## heading; each heading is a step, except
    # the Verify and Rollback sections which become the extras.
    def load_single_file(body)
      preamble, sections = SingleFile.split(body)
      @landing = Step.new(slug: "runbook", text: preamble, path: main_path, root: dir, interpreters:)
      @steps   = []
      @extras  = {}
      sections.each do |section|
        section.warnings.each { @section_warnings << "section '#{section.title}' (line #{section.line}): #{it}" }
        data = { "title" => section.title }.merge(section.data)
        if section.extra?
          role = section.role
          if EXTRAS.include?(role)
            @section_warnings << "section '#{section.title}' (line #{section.line}): a second #{role} section; the first one is used" if @extras.key?(role)
            @extras[role] ||= Step.new(slug: role, text: section.body, path: main_path, root: dir, data:, interpreters:)
          else
            @section_warnings << "section '#{section.title}' (line #{section.line}): unknown role '#{role}'; expected verify or rollback"
          end
        else
          position = @steps.size + 1
          @steps << Step.new(slug: SingleFile.slug_for(section.title, position), text: section.body, path: main_path, root: dir, position:, data:, interpreters:)
        end
      end
      @extras = EXTRAS.filter_map { [it, @extras[it]] if @extras[it] }.to_h
    end

    def validate
      warnings = []
      warnings << (single_file? ? "no steps found: add a ## heading per step" : "no steps found in #{STEPS_DIR}/") if steps.empty?
      warnings << "title missing from #{File.basename(main_path)} front matter" unless data["title"]
      inputs.reject(&:valid?).each { warnings << "input name '#{it.name}' is not a valid environment variable name" }
      dupes = steps.map(&:slug).tally.select { |_, n| n > 1 }.keys
      warnings << "duplicate step slugs: #{dupes.join(', ')}" if dupes.any?
      warnings.concat(@section_warnings)
      documents.each_value do |step|
        step.warnings.each { warnings << "#{step.slug}: #{it}" }
      end
      warnings
    end
  end
end
