# frozen_string_literal: true

require "io/console"

module Runsheets
  # `runsheets --run STEP RUNBOOK`: run one step of a runbook at the
  # terminal. It is recorded like a run from the page: a session with an
  # engineer and a why, a run record, and the session log, whose echo shows
  # each block's output as it comes.
  #
  # Each block does at the terminal what it does on the page:
  #
  #   run          runs, and fails the step unless it exits 0
  #   expect       is compared with the output of the block above it
  #   destructive  runs only once its confirmation code is typed
  #   terminal     is shown, and the operator says they ran it
  #   background   cannot run here: nothing would be left to stop it
  #
  # A step with nothing to run or confirm is shown, and the operator says it
  # is done. Answers are read from +input+, so when input runs out (a cron
  # job, stdin from /dev/null) anything that needs a person fails the step
  # rather than waiting.
  class StepRunner
    attr_reader :session, :runbook, :step

    # The document of +runbook+ that +name+ names: its slug ("020-greet"),
    # its number ("020" or "20"), its slug without the number ("greet"), or
    # verify, rollback or runbook. Raises RunbookError saying what can be
    # named when nothing, or more than one step, matches.
    def self.find_step(runbook, name)
      name  = name.to_s.strip
      found = runbook.step(name) and return found

      matches = runbook.steps.select { same_step?(it, name) }
      return matches.first if matches.one?

      what = matches.empty? ? "no step #{name.inspect}" : "#{name.inspect} matches #{matches.map(&:slug).join(', ')}"
      raise RunbookError, "#{what} in #{runbook.title}; steps: #{runbook.documents.keys.join(', ')}"
    end

    # The documents --run offers to choose from: the numbered steps, then
    # verify and rollback, after the landing page when it has blocks to run
    # or confirm.
    def self.choices(runbook)
      landing = runbook.landing if runbook.landing.blocks.any? { it.executable? || it.terminal? }
      [landing, *runbook.steps, *runbook.extras.values].compact
    end

    # Ask which step to run, listing the choices. The answer is a number in
    # the list or anything find_step takes; a wrong one is asked again.
    # Raises RunError when input runs out with nothing chosen.
    def self.choose_step(runbook, input:, output:)
      choices = choices(runbook)
      raise RunbookError, "#{runbook.title} has no steps" if choices.empty?

      output.puts "Steps in #{runbook.title}:", *choice_lines(choices)
      loop do
        output.print "Which step? (its number in the list, or its name): "
        answer = input.gets
        output.puts if answer.nil?
        raise RunError, "no step chosen" if answer.nil?

        pick = pick_step(runbook, choices, answer.strip) and return pick
        output.puts "  #{answer.strip.inspect} is not one of the steps"
      end
    end

    # The list choose_step shows: number, slug and title, with the steps
    # that cannot run at a terminal marked.
    def self.choice_lines(choices)
      width = choices.map { it.slug.size }.max
      choices.map.with_index(1) do |step, i|
        format("  %<i>2d) %<slug>-#{width}s  %<title>s%<note>s", i:, slug: step.slug, title: step.title, note: refusal(step) ? "  (page only)" : "")
      end
    end

    # The choice +answer+ names, or nil. A number without a leading zero is
    # a place in the list; anything else is looked up as find_step does.
    def self.pick_step(runbook, choices, answer)
      return if answer.empty?
      return choices[answer.to_i - 1] if answer.match?(/\A[1-9]\d*\z/) && answer.to_i <= choices.size

      find_step(runbook, answer)
    rescue RunbookError
      nil
    end

    # Whether +name+ is +step+'s number or its slug without the number.
    def self.same_step?(step, name)
      return step.number&.to_i == name.to_i if name.match?(/\A\d+\z/)

      step.slug.sub(/\A\d+[-_]?/, "") == name
    end

    # Why +step+ cannot be run at a terminal, or nil.
    def self.refusal(step)
      background = step.blocks.select(&:background?)
      return if background.empty?

      "#{step.slug} has a background block (#{background.map(&:id).join(', ')}), which nothing would be left to stop; " \
        "start it from the page"
    end

    # Declared inputs that +step+'s blocks refer to and +values+ leaves blank.
    def self.blank_inputs(runbook, step, values)
      referenced = step.blocks.select { it.executable? || it.terminal? }.flat_map(&:referenced_variables)
      runbook.inputs.select { referenced.include?(it.name) && values[it.name].to_s.empty? }
    end

    # What a prompt shows of an input's current value: " [value]", " [set]"
    # for a secret with one, or "" when it has none.
    def self.shown(input, current)
      return "" if current.to_s.empty?

      " [#{input.secret? ? 'set' : current}]"
    end

    # Expected and actual lines that differ, marked - and +, for a failed
    # Expectation comparison.
    def self.mismatch_lines(result)
      result.rows.reject { it.tag == :same }.flat_map do |row|
        [("- #{row.expected.map(&:first).join}" if row.expected), ("+ #{row.actual.map(&:first).join}" if row.actual)].compact
      end
    end

    def initialize(session:, runbook:, step:, input: $stdin, output: $stdout)
      @session = session
      @runbook = runbook
      @step    = step
      @input   = input
      @output  = output
    end

    # Run the step. Returns the exit status: 0 when every block ran, matched
    # and was confirmed, 1 otherwise. A numbered step that succeeds is
    # marked done.
    def run
      refusal = self.class.refusal(step)
      raise RunError, refusal if refusal

      inputs = ask_inputs
      @run   = session.open(runbook, inputs:)
      @output.puts "#{step.title} [#{step.slug}]"
      return 1 unless performed?

      @run.mark_step(step.slug, status: "done") if step.position
      0
    end

    # Do the step: each block in turn, stopping at the first that fails, or
    # for a step with nothing to run, ask whether it is done.
    def performed? = needs_person? ? done? : step.blocks.all? { perform(it) }

    # Whether the step has nothing to run or confirm, so a person says when
    # it is done.
    def needs_person? = step.blocks.none? { it.executable? || it.terminal? }

    # Every input the runbook declares, asked for in order as the page's
    # start form does, each offering the value it has now (from the
    # environment or its default) for Enter to keep. Once input runs out
    # the rest keep theirs unasked. Raises RunError when an input the step
    # uses is still blank.
    def ask_inputs
      values = Run.resolve_inputs(runbook, {})
      values = runbook.inputs.to_h { [it.name, ask_input(it, values[it.name])] }
      blank  = self.class.blank_inputs(runbook, step, values).map(&:name)
      raise RunError, "#{blank.join(', ')} #{blank.size > 1 ? 'have' : 'has'} no value; the step needs #{blank.size > 1 ? 'them' : 'it'}" if blank.any?

      values
    end

    # One input's value: what was typed, else +current+. A secret is read
    # without echo, and its value is never shown.
    def ask_input(input, current)
      return current if @exhausted

      @output.print "#{input.prompt || input.name} (#{input.name})#{self.class.shown(input, current)}: "
      answer = input.secret? ? read_secret : read_line
      answer.to_s.empty? ? current : answer
    end

    # Do what +block+ asks for. Returns whether the step can carry on.
    def perform(block)
      case block.kind
      when :run, :destructive then execute(block)
      when :terminal then confirm_terminal(block)
      else true
      end
    end

    # Run a block, then check its exit status and its expect block.
    def execute(block)
      execution = start(block) or return false
      execution.wait
      return failed(block, Run.ending(execution).last) unless execution.success?

      expected = step.expected_output(block.id)
      expected.nil? || matches?(block, expected, execution.output)
    end

    # Start a block, asking for its confirmation code when it is
    # destructive. Returns the Execution, or nil when it was not confirmed.
    def start(block)
      @run.execute(block.id)
    rescue Run::ConfirmationRequired => e
      @output.print "#{block.id} is destructive. Type #{e.challenge} to run it: "
      begin
        @run.execute(block.id, confirm: read_line.to_s)
      rescue Run::ConfirmationRequired
        failed(block, "not confirmed")
        nil
      end
    end

    # Whether +output+ is what the expect block says; prints the lines that
    # differ when it is not.
    def matches?(block, expected, output)
      result = Expectation.compare(expected, output)
      return true if result.match?

      @output.puts "#{block.id}: the output is not what the expect block says:", *self.class.mismatch_lines(result).map { "  #{it}" }
      failed(block, "output did not match")
    end

    # Show a terminal block and ask whether the operator ran it.
    def confirm_terminal(block)
      @output.puts "Run this yourself:", *block.code.lines(chomp: true).map { "  #{it}" }
      return failed(block, "not confirmed") unless yes?("Did you run it?")

      @output.print "Note (optional): "
      @run.acknowledge(block.id, note: read_line)
      true
    end

    # Show a step with nothing to run and ask whether it is done.
    def done?
      @output.puts "", step.body.strip, ""
      yes?("Done?") || failed(step, "not done")
    end

    private

    # A yes/no question; no unless the answer starts with y.
    def yes?(question)
      @output.print "#{question} [y/N]: "
      read_line.to_s.downcase.start_with?("y")
    end

    def failed(thing, why)
      @output.puts "#{thing.is_a?(Step) ? thing.slug : thing.id}: #{why}"
      false
    end

    # A line of input, stripped, or nil when input has run out.
    def read_line
      line = @input.gets
      @exhausted = true if line.nil?
      @output.puts if line.nil? # end the prompt's line
      line&.strip
    end

    def read_secret
      return read_line unless @input.respond_to?(:tty?) && @input.tty?

      line = @input.noecho(&:gets)
      @exhausted = true if line.nil?
      @output.puts
      line&.strip
    end
  end
end
