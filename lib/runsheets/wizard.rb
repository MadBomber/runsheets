# frozen_string_literal: true

require "fileutils"

module Runsheets
  # `runsheets --new [DIR]`: ask what kind of runbook to make, then write it
  # from a Template into DIR, asking for DIR too when it was not given.
  #
  # Every question has a default, so Enter accepts it. Answers are read
  # from +input+ and prompts written to +output+, so a test (or a script
  # piping answers in) drives it like a person would. When input runs out
  # each remaining question takes its default, and the final "Create?" is
  # answered yes.
  class Wizard
    SHAPES = {
      "directory" => "runbook.md, steps/, verify.md and rollback.md",
      "single-file" => "one .md file; each ## heading is a step"
    }.freeze

    # What Enter gives for the free-text questions.
    DEFAULTS = {
      name: "new-runbook",
      when_to_use: "One or two sentences on the situation this runbook is for.",
      escalation: "Who to call when a step fails"
    }.freeze

    # How a runbook sits in its parent directory: a directory runbook, a
    # single .md file, or a single file in a folder of its own because its
    # template brings support files (see Template#support_files?). Keyed by
    # [shape, whether the template has support files].
    LAYOUTS = {
      ["directory", false] => :directory, ["directory", true] => :directory,
      ["single-file", false] => :file, ["single-file", true] => :folder
    }.freeze

    # Where each layout's runbook itself is, relative to the parent. Its
    # first part is what the layout creates there.
    MAINS = { directory: "%<name>s", file: "%<name>s.md", folder: "%<name>s/%<name>s.md" }.freeze

    Answers = Data.define(:template, :name, :title, :when_to_use, :escalation, :layout) do
      def single_file? = layout != :directory
      def shape        = single_file? ? "single-file" : "directory"
      # What is created in the parent directory: a file or a directory.
      def location     = Wizard.location(name, layout)
      # The runbook itself, relative to the parent: what --check is given.
      def main         = format(MAINS.fetch(layout), name:)

      def context
        Template::Context.new(name:, title:, when_to_use:, escalation:, single_file: single_file?)
      end
    end

    # "DB Refresh!" => "db-refresh": the basename a name becomes. A name
    # with nothing usable in it gives "".
    def self.slug(text) = Slug.of(text.to_s.strip.downcase.delete_suffix(".md"))

    # The layout for a runbook of +shape+ from a template that has, or has
    # not, +support_files+.
    def self.layout(shape, support_files) = LAYOUTS.fetch([shape, support_files])

    # What a runbook called +name+ creates in its parent directory: a
    # directory or a .md file.
    def self.location(name, layout) = format(MAINS.fetch(layout), name:).split("/").first

    # "db-refresh" => "Db refresh": the title a name suggests.
    def self.title_for(name) = Slug.title(name)

    # Why +path+ cannot be created, or nil when it can: an existing file, or
    # a directory with something in it.
    def self.conflict(path)
      return "#{path} already exists" if File.file?(path)

      "#{path} exists and is not empty" if File.directory?(path) && !Dir.empty?(path)
    end

    # Why +name+ cannot be a new runbook of +layout+ in +parent+, or nil
    # when it can.
    def self.name_problem(parent, name, layout)
      return "a name needs a letter or digit" if name.empty?

      conflict(File.join(parent, location(name, layout)))
    end

    # Why +dir+ cannot be the directory to write into, or nil when it can.
    def self.parent_problem(dir)
      return "a directory is needed" if dir.nil?

      "#{dir} is a file, not a directory" if File.file?(Config.expand_path(dir))
    rescue ConfigError => e
      e.message
    end

    # The one of +names+ that +answer+ picks, by its number in the list or
    # by name, or nil.
    def self.pick(names, answer)
      return names.find { it == answer } unless answer.match?(/\A\d+\z/)

      names[answer.to_i - 1] if answer.to_i.between?(1, names.size)
    end

    CANCELLED = "Nothing created."

    attr_reader :parent

    # +parent+ is the directory to write into; nil asks for it, offering
    # +default_parent+ (nil for no default).
    def initialize(parent, input: $stdin, output: $stdout, templates: Template.all, default_parent: nil)
      raise RunbookError, "no runbook templates to offer" if templates.empty?

      @parent         = parent
      @default_parent = default_parent
      @output         = output
      @prompt         = Prompt.new(input:, output:)
      @templates      = templates
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
      layout   = self.class.layout(shape, template_named(template).support_files?)
      name     = ask_name(layout)
      title    = ask("Title", default: self.class.title_for(name))
      Answers.new(template:, name:, title:, layout:,
                  when_to_use: ask("When to use, in a sentence", default: DEFAULTS[:when_to_use], shown: "edit later"),
                  escalation: ask("Who to call when a step fails", default: DEFAULTS[:escalation], shown: "edit later"))
    end

    # One free-text answer: what was typed, else +default+. +shown+ is what
    # the prompt displays in the brackets in place of a long default.
    # +rejected+ says why the last answer was refused: when input runs out
    # while it is being asked again, the default would quietly replace it,
    # so that is an error instead.
    def ask(question, default:, shown: default, rejected: nil)
      @output.print shown ? "#{question} [#{shown}]: " : "#{question}: "
      line = @prompt.line
      raise RunbookError, rejected if line.nil? && rejected

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
      ask_until do |rejected|
        answer = ask("Choose", default: ((names.index(default) || 0) + 1).to_s, rejected:)
        pick   = self.class.pick(names, answer)
        [pick, ("#{answer.inspect} is not one of 1-#{names.size}" unless pick)]
      end
    end

    # The runbook's name, slugged, asked again while it is blank or taken.
    def ask_name(layout)
      ask_until do |rejected|
        name = self.class.slug(ask("Name (the #{layout == :file ? 'file' : 'directory'} name)", default: DEFAULTS[:name], rejected:))
        [name, self.class.name_problem(parent, name, layout)]
      end
    end

    # The directory to write into, expanded so ~ works: what was typed,
    # else +default+. Asked again while it is blank with no default, names
    # a file, or cannot be expanded (~nobody).
    def ask_parent(default)
      dir = ask_until do |rejected|
        answer = ask("Directory to create the runbook in", default:, rejected:)
        [answer, self.class.parent_problem(answer)]
      end
      Config.expand_path(dir)
    end

    # Ask until an answer has no problem. The block is given why the last
    # answer was refused (nil at first) and returns [answer, problem or
    # nil]. Returns the answer.
    def ask_until
      rejected = nil
      loop do
        answer, problem = yield(rejected)
        return answer unless problem

        rejected = retry_or_give_up(problem)
      end
    end

    def summary(answers)
      "Create #{answers.shape} runbook #{File.join(parent, answers.main)} from the #{answers.template} template?"
    end

    # A yes/no question; Enter, or input that has run out, is yes.
    def confirm?(question)
      @output.puts
      @prompt.yes_unless_no?(question)
    end

    # The template called +name+ among those offered.
    def template_named(name) = @templates.find { it.name == name } || raise(RunbookError, "no template named #{name}")

    # The files for +answers+: relative to the parent directory => text. A
    # single file takes the runbook's markdown; support files go beside it.
    def files(answers)
      rendered = template_named(answers.template).render(answers.context)
      return rendered.transform_keys { File.join(answers.location, it) } unless answers.single_file?

      support = Template.support_files(rendered).transform_keys { File.join(answers.location, it) }
      { answers.main => SingleFile.from_directory(rendered), **support }
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

    # Say what was wrong before the question is asked again, and return it
    # for that ask. When input has already run out, asking again would loop
    # forever, so stop instead.
    def retry_or_give_up(problem)
      raise RunbookError, problem if @prompt.exhausted?

      @output.puts "  #{problem}"
      problem
    end

    def cancelled
      @output.puts CANCELLED
      1
    end
  end
end
