# frozen_string_literal: true

module RunsheetsTest
  # Fixtures for the runbook, run record and search tests.
  module RunbookFixtures
    EXAMPLES_ROOT = File.expand_path("../../examples", __dir__)

    # [slug, runbook] for every example runbook, as Search.run expects.
    def example_entries = Runsheets::Library.load(EXAMPLES_ROOT).entries.map { [it.slug, it.runbook] }

    # The slugs of the example runbooks that match +query+, best first.
    def search_slugs(query) = Runsheets::Search.run(example_entries, query).map(&:slug)

    # A directory holding +files+ (relative path => text), removed afterwards.
    def with_files(files)
      Dir.mktmpdir("runsheets-files") do |dir|
        files.each { |rel, text| write_file(File.join(dir, rel), text) }
        yield dir
      end
    end

    # Write +text+ to +path+, making its directory, and date it +age+
    # seconds from now (nil keeps the write time).
    def write_file(path, text, age: nil)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
      FileUtils.touch(path, mtime: Time.now + age) if age
      path
    end

    # Record an execution of +block+ in +run+ and run +code+ to the end.
    # Stops a background execution straight away instead.
    # +step_slug+ names the execution's step when it differs from +step+.
    def record_and_run(run, block, step:, id:, code:, background: false, confirmed: false, step_slug: step.slug)
      ex = new_execution(run, block, step_slug:, id:, background:)
      run.record_execution(ex, step:, confirmed:)
      background ? start_and_stop(ex, code) : Runsheets::Executor.new.run(ex, code:)
      ex
    end

    def new_execution(run, block, step_slug:, id:, background: false)
      cmd, log = run.paths_for(block)
      Runsheets::Execution.new(id:, block_id: block.id, step_slug:, command: %w[bash],
                               cmd_path: cmd, log_path: log, background:)
    end

    def start_and_stop(ex, code)
      executor = Runsheets::Executor.new
      executor.start(ex, code:)
      executor.stop(ex)
      ex.wait(10)
    end

    # A run whose steps are marked: +marks+ is an array of statuses, one per
    # step from the first.
    def run_with_marks(root, runbook, marks, session_id: "S1")
      run = Runsheets::RunRecord.start(root, runbook, session_id:)
      runbook.steps.zip(marks).each { |step, status| run.mark_step(step, status:) if status }
      run
    end

    # A finished hello run: one execution of its first block, the step marked done.
    def recorded_hello_run(root)
      run  = Runsheets::RunRecord.start(root, example_runbook, session_id: "S1")
      step = example_runbook.step("010-say-hello")
      record_and_run(run, step.blocks.first, step:, id: "abc", code: "echo recorded\n")
      run.mark_step(step, status: "done", note: "looked fine")
      run.finish!(status: "completed")
    end

    # A finished hello run with a terminal block acknowledged and a destructive
    # block run confirmed. Returns the run and the terminal block.
    def acknowledged_and_confirmed_run(root)
      run  = Runsheets::RunRecord.start(root, example_runbook, session_id: "S1")
      term = example_runbook.step("020-inspect-ruby").blocks.find(&:terminal?)
      run.acknowledge(term, step: example_runbook.step("020-inspect-ruby"), note: "pressed enter")
      destructive = example_runbook.step("040-exercise-failure")
      record_and_run(run, destructive.blocks.first, step: destructive, id: "d1", code: "true\n", confirmed: true)
      [run.finish!, term]
    end

    def run_json(run) = JSON.parse(File.read(File.join(run.dir, "run.json")))
    def run_md(run) = File.read(File.join(run.dir, "run.md"))
  end
end
