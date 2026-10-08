# frozen_string_literal: true

require "test_helper"

class TestRunRecord < Minitest::Test
  include RunsheetsTest

  RunRecord = Runsheets::RunRecord

  def test_start_creates_the_directory_and_files_without_secrets
    with_runs_dir do |root|
      rb  = example_runbook
      run = RunRecord.start(root, rb, inputs: { "NAME" => "x", "SECRET_WORD" => "hunter2" }, now: Time.new(2026, 10, 7, 12, 0, 0))
      assert_equal File.join(root, "hello", "20261007T120000"), run.dir
      assert File.directory?(run.blocks_dir)
      assert File.file?(File.join(run.dir, "run.json"))
      assert File.file?(File.join(run.dir, "run.md"))
      assert_equal({ "NAME" => "x" }, run.inputs)
      refute_includes File.read(File.join(run.dir, "run.json")), "hunter2"
      assert run.active?
    end
  end

  def test_same_second_gets_a_unique_directory
    with_runs_dir do |root|
      now = Time.new(2026, 10, 7, 12, 0, 0)
      a = RunRecord.start(root, example_runbook, now:)
      b = RunRecord.start(root, example_runbook, now:)
      assert_equal "#{a.dir}-2", b.dir
    end
  end

  def test_records_executions_steps_and_transcript
    with_runs_dir do |root|
      rb   = example_runbook
      run  = RunRecord.start(root, rb)
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
      assert_equal %w[execute step], data["events"].map { it["type"] }
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
      RunRecord.start(root, rb, now: Time.new(2026, 1, 1, 0, 0, 0)).finish!(status: "abandoned")
      newer = RunRecord.start(root, rb, now: Time.new(2026, 1, 2, 0, 0, 0))
      runs = RunRecord.list(root, "hello")
      assert_equal [newer.id, "20260101T000000"], runs.map(&:id)
      assert_equal "abandoned", runs.last.status
      assert_equal "running", runs.first.status
      assert_equal 0, runs.first.summary[:executions]
    end
  end

  def test_finish_rejects_unknown_status
    with_runs_dir { |root| assert_raises(ArgumentError) { RunRecord.start(root, example_runbook).finish!(status: "weird") } }
  end
end
