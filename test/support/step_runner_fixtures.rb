# frozen_string_literal: true

require "stringio"

module RunsheetsTest
  # Fixtures for the StepRunner tests: running one step of a single-file
  # runbook and reading back what it printed and recorded.
  module StepRunnerFixtures
    # What one StepRunner#run returned and printed, the session it ran in,
    # and each execution's output (read before the run directory goes).
    Outcome = Data.define(:status, :out, :session, :outputs) do
      def step_status(slug) = session.run_for(session.runbook.slug).step_status(slug)
      def acks              = session.run_for(session.runbook.slug).record.acks
      def executions        = session.executions
    end

    # Answers the destructive block's confirmation by reading the code the
    # runner printed, as a person at the terminal would.
    class CodeTyper
      def initialize(out) = @out = out
      def gets = "#{@out.string[/Type (\h+) to run it/, 1]}\n"
    end

    # A single-file runbook titled "Fixture" with +steps+ ("Title" => body),
    # +front+ added to its front matter.
    def fixture_runbook(steps, front: "")
      sections = steps.map { |title, body| "## #{title}\n\n#{body}\n" }
      "---\ntitle: Fixture\n#{front}---\n\n#{sections.join("\n")}"
    end

    # Run the step +name+ of a runbook made from +text+, with +input+ typed
    # (a String, or a callable given the output that returns an input IO).
    def run_step(text, name, input: "")
      with_runs_dir do |root|
        with_single_file(text) do |runbook, _path|
          out     = StringIO.new
          session = start_session(root, runbook:)
          step    = Runsheets::StepRunner.find_step(runbook, name)
          io      = input.respond_to?(:call) ? input.call(out) : StringIO.new(input)
          status  = Runsheets::StepRunner.new(session:, runbook:, step:, input: io, output: out).run
          session.end!("test")
          return Outcome.new(status:, out: out.string, session:, outputs: session.executions.map(&:output))
        end
      end
    end
  end
end
