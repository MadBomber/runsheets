# frozen_string_literal: true

require "test_helper"

class TestRunRecord < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::RunbookFixtures

  RunRecord = Runsheets::RunRecord

  def test_start_creates_the_directory_and_files_without_secrets
    with_runs_dir do |root|
      run = RunRecord.start(root, example_runbook, session_id: "20261007T120000", inputs: { "NAME" => "x", "SECRET_WORD" => "hunter2" })
      assert_equal File.join(root, "hello", "20261007T120000"), run.dir
      assert File.directory?(run.blocks_dir)
      assert File.file?(File.join(run.dir, "run.json"))
      assert File.file?(File.join(run.dir, "run.md"))
      assert_equal({ "NAME" => "x" }, run.inputs)
      refute_includes File.read(File.join(run.dir, "run.json")), "hunter2"
      assert run.active?
      assert_equal "20261007T120000", run_json(run)["session"]
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

  def test_each_execution_of_a_block_gets_the_next_numbered_paths
    with_runs_dir do |root|
      run   = RunRecord.start(root, example_runbook, session_id: "S1")
      block = example_runbook.step("010-say-hello").blocks.first
      first_cmd = run.paths_for(block).first
      record_and_run(run, block, step: example_runbook.step("010-say-hello"), id: "abc", code: "true\n")
      assert_equal File.join(run.blocks_dir, "010-say-hello-1.1.cmd"), first_cmd
      assert_equal File.join(run.blocks_dir, "010-say-hello-1.2.cmd"), run.paths_for(block).first
    end
  end

  def test_records_executions_and_steps_in_run_json
    with_runs_dir do |root|
      run = recorded_hello_run(root)
      data = run_json(run)
      assert_equal "completed", data["status"]
      assert_equal "finished", data["executions"].first["state"]
      assert_equal 0, data["executions"].first["exit_status"]
      assert_equal(%w[execute step], data["events"].map { it["type"] })
      assert_equal({ "010-say-hello" => "done" }, data["steps"])
      assert_equal 1, run.steps_done
      assert_empty run.failed_executions
    end
  end

  def test_records_executions_and_steps_in_the_transcript
    with_runs_dir do |root|
      md = run_md(recorded_hello_run(root))
      assert_includes md, "`010-say-hello-1` (010-say-hello) — ok"
      assert_includes md, "echo recorded"
      assert_includes md, "recorded\n"
      assert_includes md, "marked done — looked fine"
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

  def test_acknowledgements_and_confirmations_are_recorded_in_run_json
    with_runs_dir do |root|
      run, term = acknowledged_and_confirmed_run(root)
      data = run_json(run)
      assert_equal "pressed enter", run.acks[term.id][:note]
      assert_equal(%w[ack execute], data["events"].map { it["type"] })
      assert_equal true, data["events"].last["confirmed"]
      assert_equal "pressed enter", data["acks"][term.id]["note"]
      assert_equal "pressed enter", RunRecord.load(run.dir).acks[term.id][:note]
    end
  end

  def test_acknowledgements_and_confirmations_are_recorded_in_the_transcript
    with_runs_dir do |root|
      run, term = acknowledged_and_confirmed_run(root)
      md = run_md(run)
      assert_includes md, "`#{term.id}` (020-inspect-ruby) confirmed run in the operator's terminal — pressed enter"
      assert_includes md, "— ok in"
      assert_includes md, "[confirmed]"
    end
  end

  def test_stopped_executions_are_not_failures
    with_runs_dir do |root|
      run  = RunRecord.start(root, example_runbook, session_id: "S1")
      step = example_runbook.step("035-keep-a-clock-running")
      record_and_run(run, step.blocks.first, step:, id: "bg", code: "sleep 30\n", background: true)
      run.finish!
      assert step.blocks.first.background?
      assert_empty run.failed_executions
      assert_includes run_md(run), "— stopped in"
      assert_includes run_md(run), "[background]"
    end
  end

  def test_failure_is_a_finished_nonzero_exit_not_a_stop
    assert RunRecord.failure?({ state: "finished", exit_status: 1 })
    refute RunRecord.failure?({ state: "stopped", exit_status: 143 })
  end

  def test_an_old_verification_record_still_reads_as_one
    with_runs_dir do |root|
      run = RunRecord.start(root, example_runbook, session_id: "20261008T090000-verify")
      write_file(File.join(run.dir, "run.json"), JSON.generate(run_json(run).merge("kind" => "verify", "session" => nil)))
      old = RunRecord.load(run.dir)
      assert old.verify?
      assert_includes old.transcript, "verification (verify documents only)"
      refute_includes old.transcript, "- Session:"
    end
  end

  def test_closing_status_is_opened_until_a_step_is_marked
    with_runs_dir do |root|
      run = RunRecord.start(root, example_runbook, session_id: "S1")
      assert_equal "opened", run.closing_status(example_runbook.steps.map(&:slug))
      refute run.finished_at, "still running"
    end
  end

  def test_closing_status_is_completed_only_when_every_step_is_done_or_skipped
    with_runs_dir do |root|
      slugs   = example_runbook.steps.map(&:slug)
      partial = run_with_marks(root, example_runbook, ["skipped"], session_id: "A")
      every   = run_with_marks(root, example_runbook, ["skipped"] + (["done"] * (slugs.size - 1)), session_id: "B")
      assert_equal "partial", partial.closing_status(slugs)
      assert_equal "completed", every.closing_status(slugs), "done or skipped, every step"
      assert_equal "partial", every.closing_status([]), "a runbook without steps is never completed"
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
      run  = run_with_marks(root, example_runbook, ["done"])
      step = example_runbook.step("010-say-hello")
      record_and_run(run, step.blocks.first, step:, id: "a", code: "exit 1\n")
      record_and_run(run, step.blocks.first, step:, id: "b", code: "exit 0\n")
      run.finish!
      assert_equal 1, run.failed_executions.size
      assert_empty run.unresolved_failures, "the re-run cleared the failure"
      assert_equal "010-say-hello", run.last_step
    end
  end

  def test_drift
    with_runs_dir do |root|
      rb   = example_runbook
      run  = RunRecord.start(root, rb, session_id: "S1")
      step = rb.step("010-say-hello")
      changed = record_and_run(run, step.blocks.first, step:, id: "x", code: step.blocks.first.code)
      write_file(changed.cmd_path, "echo something else\n") # pretend the runbook moved on
      record_and_run(run, Struct.new(:id).new("old-step-1"), step:, step_slug: "old-step", id: "g", code: "echo gone\n")
      run.finish!
      drift = run.drift(rb)
      assert_equal([[step.blocks.first.id, :changed], ["old-step-1", :missing]], drift.map { [it[:block_id], it[:status]] })
      assert_includes drift.first[:diff].map(&:to_s), "-echo something else"
      assert_equal "echo gone\n", drift.last[:recorded]
    end
  end

  def test_finish_rejects_unknown_status
    with_runs_dir { |root| assert_raises(ArgumentError) { RunRecord.start(root, example_runbook, session_id: "S1").finish!(status: "weird") } }
  end
end
