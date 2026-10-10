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

    attr_reader :dir, :root, :slug, :main_path, :data, :landing, :steps, :extras, :inputs, :warnings, :loaded_at

    # Load a runbook directory or a single-file runbook. The slug names the
    # runbook in run records and URLs: the directory or file name, unless
    # +slug:+ says otherwise (a Library passes the path inside it). +root:+
    # is the directory relative links resolve against and /files/ and /docs/
    # serve from: the library when the runbook is in one, else the runbook's
    # own directory.
    def self.load(path, slug: nil, root: nil)
      path = File.expand_path(path)
      if File.directory?(path)
        new(dir: path, main_path: File.join(path, MAIN_FILE), slug: slug || File.basename(path), single_file: false, **{ root: }.compact)
      elsif File.file?(path)
        slug ||= File.basename(path, ".*")
        slug   = File.basename(File.dirname(path)) if slug == File.basename(MAIN_FILE, ".*")
        new(dir: File.dirname(path), main_path: path, slug:, single_file: true, **{ root: }.compact)
      else
        raise RunbookError, "no such runbook: #{path}"
      end
    end

    # Is the markdown file at +path+ a runbook rather than a plain document?
    # A file that cannot be read is neither, and is left out.
    def self.runbook_file?(path)
      runbook_text?(File.read(path, encoding: "UTF-8"))
    rescue SystemCallError
      false
    end

    # Is +path+ a plain document under +root+: an existing markdown file
    # that is not a runbook and not one of a runbook directory's files
    # (no runbook.md in its directory or any directory above it, up to
    # +root+)?
    def self.plain_document?(path, root)
      path = File.expand_path(path)
      root = File.expand_path(root)
      return false unless File.file?(path) && path.start_with?("#{root}/") && !runbook_file?(path)

      dirs = Pathname(File.dirname(path)).ascend.take_while { it.to_s.start_with?(root) }
      dirs.none? { File.file?(it.join(MAIN_FILE)) }
    end

    # A runbook starts with YAML front matter that has a title; anything
    # else is a plain document. Front matter that does not parse counts as
    # a runbook: it was meant to be one, and loading it reports why not.
    def self.runbook_text?(text)
      !FrontMatter.parse(text).data["title"].to_s.strip.empty?
    rescue RunbookError
      true
    end

    def initialize(dir:, main_path:, slug:, single_file:, root: dir)
      @dir         = dir
      @root        = File.expand_path(root)
      @main_path   = main_path
      @slug        = slug
      @single_file = single_file
      raise RunbookError, "#{MAIN_FILE} not found in #{dir}" unless File.file?(main_path)

      @loaded_at = Time.now
      parsed     = FrontMatter.parse(File.read(main_path, encoding: "UTF-8"))
      @data      = parsed.data
      raise RunbookError, "#{File.basename(main_path)} is not a runbook: it needs YAML front matter with a title" if data["title"].to_s.strip.empty?
      @section_warnings = []
      if single_file
        load_single_file(parsed.body)
      else
        @landing = Step.new(slug: "runbook", text: parsed.body, path: main_path, root: @root, interpreters:)
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
    def tags          = Array(data["tags"]).map(&:to_s)
    def preamble_html = landing.html

    def verify   = extras["verify"]
    def rollback = extras["rollback"]

    def destructive? = !blast_radius.nil? || steps.any?(&:destructive?)

    # The checks the Checks page gathers: verify-kind steps in order, then
    # verify.md.
    def verify_documents = [*steps.select(&:verify?), verify].compact

    def verify_document?(step) = verify_documents.include?(step)

    def verify_blocks = verify_documents.flat_map(&:executable_blocks)

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
    def documents = @documents ||= [landing, *steps, *extras.values].to_h { [it.slug, it] }

    def step(slug) = documents[slug]

    # The document read from the file at +path+, or nil. In a single-file
    # runbook every document shares the file, so this is the landing page.
    def document_at(path)
      real = Runbook.real_path(path)
      documents.each_value.find { it.path && Runbook.real_path(it.path) == real }
    end

    def self.real_path(path)
      File.realpath(path)
    rescue SystemCallError
      File.expand_path(path)
    end

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
        tags:, inputs: inputs.map(&:to_h),
        steps: steps.map(&:to_h), extras: extras.keys, warnings: }
    end

    private

    def load_steps
      steps_dir = File.join(dir, STEPS_DIR)
      return [] unless File.directory?(steps_dir)

      names = Dir.glob("*.md", base: steps_dir).sort_by { [it[/\A\d+/].to_i, it] }
      names.map.with_index(1) { |name, position| Step.load(File.join(steps_dir, name), root:, position:, interpreters:) }
    end

    def load_extras
      EXTRAS.filter_map do |name|
        path = File.join(dir, "#{name}.md")
        [name, Step.load(path, root:, interpreters:)] if File.file?(path)
      end.to_h
    end

    # Preamble up to the first ## heading; each heading is a step, except
    # the Verify and Rollback sections which become the extras.
    def load_single_file(body)
      preamble, sections = SingleFile.split(body)
      @landing = Step.new(slug: "runbook", text: preamble, path: main_path, root:, interpreters:)
      @steps   = []
      @extras  = {}
      sections.each { add_section(it) }
      @extras = EXTRAS.filter_map { [it, @extras[it]] if @extras[it] }.to_h
    end

    def add_section(section)
      section.warnings.each { section_warning(section, it) }
      section.extra? ? add_extra(section) : add_step(section)
    end

    def add_step(section)
      position = @steps.size + 1
      @steps << section_step(section, slug: SingleFile.slug_for(section.title, position), position:)
    end

    def add_extra(section)
      role = section.role
      return section_warning(section, "unknown role '#{role}'; expected verify or rollback") unless EXTRAS.include?(role)
      return section_warning(section, "a second #{role} section; the first one is used") if @extras.key?(role)

      @extras[role] = section_step(section, slug: role)
    end

    def section_step(section, slug:, position: nil)
      data = { "title" => section.title }.merge(section.data)
      Step.new(slug:, text: section.body, path: main_path, root:, position:, data:, interpreters:)
    end

    def section_warning(section, message)
      @section_warnings << "section '#{section.title}' (line #{section.line}): #{message}"
    end

    def validate
      warnings = []
      warnings << (single_file? ? "no steps found: add a ## heading per step" : "no steps found in #{STEPS_DIR}/") if steps.empty?
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
