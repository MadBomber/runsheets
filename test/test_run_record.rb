# frozen_string_literal: true

require "test_helper"

class TestRunRecord < Minitest::Test
  include RunsheetsTest

  RunRecord = Runsheets::RunRecord

  def test_start_creates_the_directory_and_files_without_secrets
    with_runs_dir do |root|
      rb  = example_runbook
      run = RunRecord.start(root, rb, session_id: "20261007T120000", inputs: { "NAME" => "x", "SECRET_WORD" => "hunter2" })
      assert_equal File.join(root, "hello", "20261007T120000"), run.dir
      assert File.directory?(run.blocks_dir)
      assert File.file?(File.join(run.dir, "run.json"))
      assert File.file?(File.join(run.dir, "run.md"))
      assert_equal({ "NAME" => "x" }, run.inputs)
      refute_includes File.read(File.join(run.dir, "run.json")), "hunter2"
      assert run.active?
      assert_equal "20261007T120000", JSON.parse(File.read(File.join(run.dir, "run.json")))["session"]
      assert_includes run.transcript, "- Session: `20261007T120000`"
    end
  end

  def test_a_reused_session_id_gets_a_unique_directory
    with_runs_dir do |root|
      a = RunRecord.start(root, example_runbook, session_id: "S1")
      b = RunRecord.start(root, example_runbook, session_id: "S1")
      assert_equal "#{a.dir}-2", b.dir
    end
  end

  def test_records_executions_steps_and_transcript
    with_runs_dir do |root|
      rb   = example_runbook
      run  = RunRecord.start(root, rb, session_id: "S1")
      step = rb.step("010-say-hello")
      block = step.blocks.first
      cmd, log = run.paths_for(block)
      assert_equal File.join(run.blocks_dir, "010-say-hello-1.1.cmd"), cmd
      ex = Runsheets::Execution.new(id: "abc", block_id: block.id, step_slug: step.slug, command: %w[bash], cmd_path: cmd, log_path: log)
      run.record_execution(ex, step:)
      Runsheets::Executor.new.run(ex, code: "echo recorded\n")
      run.mark_step(step, status: "done", note: "looked fine")
      assert_equal File.join(run.blocks_dir, "010-say-hello-1.2.cmd"), run.paths_for(block).first
      run.finish!(status: "completed")

      data = JSON.parse(File.read(File.join(run.dir, "run.json")))
      assert_equal "completed", data["status"]
      assert_equal "finished", data["executions"].first["state"]
      assert_equal 0, data["executions"].first["exit_status"]
      assert_equal(%w[execute step], data["events"].map { it["type"] })
      assert_equal({ "010-say-hello" => "done" }, data["steps"])

      md = File.read(File.join(run.dir, "run.md"))
      assert_includes md, "`010-say-hello-1` (010-say-hello) — ok"
      assert_includes md, "echo recorded"
      assert_includes md, "recorded\n"
      assert_includes md, "marked done — looked fine"
      assert_equal 1, run.steps_done
      assert_empty run.failed_executions
    end
  end

  def test_load_and_list
    with_runs_dir do |root|
      rb = example_runbook
      RunRecord.start(root, rb, session_id: "A", now: Time.new(2026, 1, 1, 0, 0, 0)).finish!(status: "abandoned")
      newer = RunRecord.start(root, rb, session_id: "B", now: Time.new(2026, 1, 2, 0, 0, 0))
      runs = RunRecord.list(root, "hello")
      assert_equal [newer.id, "A"], runs.map(&:id), "newest first, by start time"
      assert_equal "abandoned", runs.last.status
      assert_equal "running", runs.first.status
      assert_equal 0, runs.first.summary[:executions]
    end
  end

  def test_acknowledgements_and_confirmations_are_recorded
    with_runs_dir do |root|
      rb    = example_runbook
      run   = RunRecord.start(root, rb, session_id: "S1")
      step  = rb.step("020-inspect-ruby")
      term  = step.blocks.find(&:terminal?)
      run.acknowledge(term, step:, note: "pressed enter")
      assert_equal "pressed enter", run.acks[term.id][:note]

      dstep = rb.step("040-exercise-failure")
      block = dstep.blocks.first
      cmd, log = run.paths_for(block)
      ex = Runsheets::Execution.new(id: "d1", block_id: block.id, step_slug: dstep.slug, command: %w[bash], cmd_path: cmd, log_path: log)
      run.record_execution(ex, step: dstep, confirmed: true)
      Runsheets::Executor.new.run(ex, code: "true\n")
      run.finish!

      data = JSON.parse(File.read(File.join(run.dir, "run.json")))
      assert_equal(%w[ack execute], data["events"].map { it["type"] })
      assert_equal true, data["events"].last["confirmed"]
      assert_equal "pressed enter", data["acks"][term.id]["note"]

      md = File.read(File.join(run.dir, "run.md"))
      assert_includes md, "`#{term.id}` (020-inspect-ruby) confirmed run in the operator's terminal — pressed enter"
      assert_includes md, "— ok in"
      assert_includes md, "[confirmed]"

      reloaded = RunRecord.load(run.dir)
      assert_equal "pressed enter", reloaded.acks[term.id][:note]
    end
  end

  def test_stopped_executions_are_not_failures
    with_runs_dir do |root|
      rb   = example_runbook
      run  = RunRecord.start(root, rb, session_id: "S1")
      step = rb.step("035-keep-a-clock-running")
      block = step.blocks.first
      assert block.background?
      cmd, log = run.paths_for(block)
      ex = Runsheets::Execution.new(id: "bg", block_id: block.id, step_slug: step.slug, command: %w[bash], cmd_path: cmd, log_path: log, background: true)
      run.record_execution(ex, step:)
      executor = Runsheets::Executor.new
      executor.start(ex, code: "sleep 30\n")
      executor.stop(ex)
      ex.wait(10)
      run.finish!
      assert_empty run.failed_executions
      assert_includes File.read(File.join(run.dir, "run.md")), "— stopped in"
      assert_includes File.read(File.join(run.dir, "run.md")), "[background]"
      assert RunRecord.failure?({ state: "finished", exit_status: 1 })
      refute RunRecord.failure?({ state: "stopped", exit_status: 143 })
    end
  end

  def test_an_old_verification_record_still_reads_as_one
    with_runs_dir do |root|
      run  = RunRecord.start(root, example_runbook, session_id: "20261008T090000-verify")
      data = JSON.parse(File.read(File.join(run.dir, "run.json"))).merge("kind" => "verify", "session" => nil)
      File.write(File.join(run.dir, "run.json"), JSON.generate(data))
      old = RunRecord.load(run.dir)
      assert old.verify?
      assert_includes old.transcript, "verification (verify documents only)"
      refute_includes old.transcript, "- Session:"
    end
  end

  def test_closing_status_follows_what_was_done
    with_runs_dir do |root|
      rb    = example_runbook
      slugs = rb.steps.map(&:slug)
      run   = RunRecord.start(root, rb, session_id: "S1")
      assert_equal "opened", run.closing_status(slugs)
      run.mark_step(rb.steps.first, status: "skipped")
      assert_equal "partial", run.closing_status(slugs)
      rb.steps.drop(1).each { run.mark_step(it, status: "done") }
      assert_equal "completed", run.closing_status(slugs), "done or skipped, every step"
      assert_equal "partial", run.closing_status([]), "a runbook without steps is never completed"
    end
  end

  def test_finish_takes_any_final_status
    with_runs_dir do |root|
      %w[completed partial opened interrupted abandoned].each do |status|
        run = RunRecord.start(root, example_runbook, session_id: status).finish!(status:)
        assert_equal status, RunRecord.load(run.dir).status
        refute run.active?
      end
    end
  end

  def test_a_successful_rerun_clears_an_unresolved_failure
    with_runs_dir do |root|
      rb  = example_runbook
      run = RunRecord.start(root, rb, session_id: "S1")
      step  = rb.step("010-say-hello")
      block = step.blocks.first
      run.mark_step(step, status: "done")

      cmd, log = run.paths_for(block)
      first = Runsheets::Execution.new(id: "a", block_id: block.id, step_slug: step.slug, command: %w[bash], cmd_path: cmd, log_path: log)
      run.record_execution(first, step:)
      Runsheets::Executor.new.run(first, code: "exit 1\n")
      cmd, log = run.paths_for(block)
      second = Runsheets::Execution.new(id: "b", block_id: block.id, step_slug: step.slug, command: %w[bash], cmd_path: cmd, log_path: log)
      run.record_execution(second, step:)
      Runsheets::Executor.new.run(second, code: "exit 0\n")
      run.finish!

      assert_equal 1, run.failed_executions.size
      assert_empty run.unresolved_failures, "the re-run cleared the failure"
      assert_equal "010-say-hello", run.last_step
    end
  end

  def test_drift
    with_runs_dir do |root|
      rb    = example_runbook
      run   = RunRecord.start(root, rb, session_id: "S1")
      step  = rb.step("010-say-hello")
      block = step.blocks.first
      cmd, log = run.paths_for(block)
      ex = Runsheets::Execution.new(id: "x", block_id: block.id, step_slug: step.slug, command: %w[bash], cmd_path: cmd, log_path: log)
      run.record_execution(ex, step:)
      Runsheets::Executor.new.run(ex, code: block.code)
      File.write(cmd, "echo something else\n")   # pretend the runbook moved on
      gone_cmd, gone_log = run.paths_for(Struct.new(:id).new("old-step-1"))
      gone = Runsheets::Execution.new(id: "g", block_id: "old-step-1", step_slug: "old-step", command: %w[bash], cmd_path: gone_cmd, log_path: gone_log)
      run.record_execution(gone, step: step)
      Runsheets::Executor.new.run(gone, code: "echo gone\n")
      run.finish!

      drift = run.drift(rb)
      assert_equal([[block.id, :changed], ["old-step-1", :missing]], drift.map { [it[:block_id], it[:status]] })
      assert_includes drift.first[:diff].map(&:to_s), "-echo something else"
      assert_equal "echo gone\n", drift.last[:recorded]
    end
  end

  def test_finish_rejects_unknown_status
    with_runs_dir { |root| assert_raises(ArgumentError) { RunRecord.start(root, example_runbook, session_id: "S1").finish!(status: "weird") } }
  end
end
