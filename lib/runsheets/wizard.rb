# frozen_string_literal: true

require "fileutils"

module Runsheets
  # `runsheets --new [DIR]`: ask what kind of runbook to make, then write it
  # from a Template into DIR, asking for DIR too when it was not given.
  #
  # Every question has a default, so Enter accepts it. Answers are read
  # from +input+ and prompts written to +output+, so a test (or a script
  # piping answers in) drives it like a person would. When input runs out
  # each remaining question takes its default.
  class Wizard
    SHAPES = {
      "directory" => "runbook.md, steps/, verify.md and rollback.md",
      "single-file" => "one .md file; each ## heading is a step"
    }.freeze

    DEFAULT_NAME        = "new-runbook"
    DEFAULT_WHEN_TO_USE = "One or two sentences on the situation this runbook is for."
    DEFAULT_ESCALATION  = "Who to call when a step fails"

    # +folder+ is true when a single-file runbook gets a folder of its own
    # because its template brings support files (see Template#support_files?).
    Answers = Data.define(:shape, :template, :name, :title, :when_to_use, :escalation, :folder) do
      def single_file? = shape == "single-file"
      # What is created in the parent directory: a file or a directory.
      def location = Wizard.location(name, single_file: single_file?, folder:)
      # The runbook itself, relative to the parent: what --check is given.
      def main     = single_file? && folder ? File.join(name, "#{name}.md") : location

      def context
        Template::Context.new(name:, title:, when_to_use:, escalation:, single_file: single_file?)
      end
    end

    # "DB Refresh!" => "db-refresh": the basename a name becomes. A name
    # with nothing usable in it gives "".
    def self.slug(text) = text.to_s.strip.delete_suffix(".md").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")

    # What a runbook called +name+ creates in its parent directory: a
    # directory, a .md file, or for a single file with support files a
    # directory holding both.
    def self.location(name, single_file:, folder: false) = single_file && !folder ? "#{name}.md" : name

    # "db-refresh" => "Db refresh": the title a name suggests.
    def self.title_for(name) = name.tr("-_", " ").capitalize

    # Why +path+ cannot be created, or nil when it can: an existing file, or
    # a directory with something in it.
    def self.conflict(path)
      return "#{path} already exists" if File.file?(path)

      "#{path} exists and is not empty" if File.directory?(path) && !Dir.empty?(path)
    end

    attr_reader :parent

    # +parent+ is the directory to write into; nil asks for it, offering
    # +default_parent+ (nil for no default).
    def initialize(parent, input: $stdin, output: $stdout, templates: Template.all, default_parent: nil)
      @parent         = parent
      @default_parent = default_parent
      @input          = input
      @output         = output
      @templates      = templates
      raise RunbookError, "no runbook templates found in #{Template::DIR}" if templates.empty?
    end

    # Ask, confirm, write. Returns the exit status.
    def run
      @parent ||= ask_parent(@default_parent)
      @output.puts "New runbook in #{parent}", ""
      answers = ask_all
      return cancelled unless confirm?(summary(answers))

      write(answers)
    end

    # Every question, in order, as Answers.
    def ask_all
      shape    = choose("Shape", SHAPES)
      template = choose("Template", @templates.to_h { [it.name, it.description] }, default: Template::DEFAULT)
      folder   = shape == "single-file" && template_named(template).support_files?
      name     = ask_name(shape, folder:)
      title    = ask("Title", default: self.class.title_for(name))
      Answers.new(shape:, template:, name:, title:, folder:,
                  when_to_use: ask("When to use, in a sentence", default: DEFAULT_WHEN_TO_USE, shown: "edit later"),
                  escalation: ask("Who to call when a step fails", default: DEFAULT_ESCALATION, shown: "edit later"))
    end

    # One free-text answer: what was typed, else +default+. +shown+ is what
    # the prompt displays in the brackets in place of a long default. When
    # input runs out while a rejected answer is being asked again, the
    # default would quietly replace it, so that is an error instead.
    def ask(question, default:, shown: default)
      @output.print shown ? "#{question} [#{shown}]: " : "#{question}: "
      line = read_line
      raise RunbookError, @rejected if line.nil? && @rejected

      @rejected = nil
      line.nil? || line.empty? ? default : line
    end

    # Pick one of +options+ (name => description) by number or name.
    # Returns the name; +default+ (the first option unless named) is
    # what Enter picks.
    def choose(question, options, default: options.keys.first)
      names = options.keys
      @output.puts "#{question}:"
      width = names.map(&:size).max
      names.each.with_index(1) { |name, i| @output.puts "  #{i}) #{name.ljust(width)}  #{options[name]}" }
      loop do
        answer = ask("Choose", default: ((names.index(default) || 0) + 1).to_s)
        pick   = answer.match?(/\A\d+\z/) ? names[answer.to_i - 1] : names.find { it == answer }
        return pick if pick && answer != "0"

        retry_or_give_up("#{answer.inspect} is not one of 1-#{names.size}")
      end
    end

    # The runbook's name, slugged, asked again while it is blank or taken.
    # +folder+ says a single file will be put in a folder of its own.
    def ask_name(shape, folder: false)
      single = shape == "single-file"
      loop do
        name = self.class.slug(ask("Name (the #{single && !folder ? 'file' : 'directory'} name)", default: DEFAULT_NAME))
        problem = name.empty? ? "a name needs a letter or digit" : self.class.conflict(File.join(parent,
                                                                                                 self.class.location(name, single_file: single, folder:)))
        return name unless problem

        retry_or_give_up(problem)
      end
    end

    # The directory to write into, expanded so ~ works: what was typed,
    # else +default+. Asked again while it is blank with no default, or
    # names a file.
    def ask_parent(default)
      loop do
        dir     = ask("Directory to create the runbook in", default:)
        problem = if dir.nil? then "a directory is needed"
                  elsif File.file?(File.expand_path(dir)) then "#{dir} is a file, not a directory"
                  end
        return File.expand_path(dir) unless problem

        retry_or_give_up(problem)
      end
    end

    def summary(answers)
      "Create #{answers.shape} runbook #{File.join(parent, answers.main)} from the #{answers.template} template?"
    end

    # A yes/no question; yes unless the answer starts with n.
    def confirm?(question)
      @output.print "\n#{question} [Y/n]: "
      !read_line.to_s.downcase.start_with?("n")
    end

    # The template called +name+ among those offered.
    def template_named(name) = @templates.find { it.name == name } || raise(RunbookError, "no template named #{name}")

    # The files for +answers+: relative to the parent directory => text. A
    # single file takes the runbook's markdown; support files go beside it.
    def files(answers)
      rendered = template_named(answers.template).render(answers.context)
      return rendered.transform_keys { File.join(answers.location, it) } unless answers.single_file?

      support = Template.support_files(rendered).transform_keys { File.join(answers.location, it) }
      { answers.main => Template.single_file(rendered), **support }
    end

    # Write the runbook and say what to do next. Returns the exit status.
    def write(answers)
      problem = self.class.conflict(File.join(parent, answers.location))
      raise RunbookError, problem if problem

      files(answers).each do |rel, text|
        full = File.join(parent, rel)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, text)
        @output.puts "created #{full}"
      end
      path = File.join(parent, answers.main)
      @output.puts <<~NEXT

        Next:
          #{CLI::PROGRAM} --check #{path}
          #{CLI::PROGRAM} #{path}
      NEXT
      0
    end

    private

    # A line of input without its newline, or nil when input has run out.
    def read_line
      line = @input.gets
      @exhausted = true if line.nil?
      @output.puts if line.nil? # keep the terminal tidy after Ctrl-D
      line&.strip
    end

    # Say what was wrong before the question is asked again; when input has
    # already run out, asking again would loop forever, so stop instead.
    def retry_or_give_up(problem)
      raise RunbookError, problem if @exhausted

      @output.puts "  #{problem}"
      @rejected = problem
    end

    def cancelled
      @output.puts "Nothing created."
      1
    end
  end
end
