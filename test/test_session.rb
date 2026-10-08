# frozen_string_literal: true

require "test_helper"

class TestSession < Minitest::Test
  include RunsheetsTest

  def session(root) = Runsheets::Session.new(runbook: example_runbook, runs_root: root)

  def test_resolve_inputs_uses_given_then_env_then_default
    with_runs_dir do |root|
      s = session(root)
      ENV["SECRET_WORD"] = "from-env"
      resolved = s.resolve_inputs("NAME" => "given")
      assert_equal({ "NAME" => "given", "SECRET_WORD" => "from-env" }, resolved)
      assert_equal "world", s.resolve_inputs("NAME" => "")["NAME"]
    ensure
      ENV.delete("SECRET_WORD")
    end
  end

  def test_execute_requires_an_active_run
    with_runs_dir do |root|
      s = session(root)
      refute s.active?
      assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
    end
  end

  def test_full_flow
    with_runs_dir do |root|
      s = session(root)
      s.start_run(inputs: { "NAME" => "tester" })
      assert s.active?
      assert_raises(Runsheets::RunError) { s.start_run }

      ex = s.execute("010-say-hello-1").wait
      assert ex.success?
      assert_includes ex.output, "Hello, tester!"
      assert_includes ex.output, "Running block 010-say-hello-1 of step 010-say-hello in run #{s.run.id}"
      assert_same ex, s.execution(ex.id)
      assert_equal "ran", Runsheets::Pages.step_mark(s, s.runbook.step("010-say-hello"))

      s.mark_step("010-say-hello", status: "done", note: "  ")
      assert_equal "done", s.step_status("010-say-hello")

      failed = s.execute("040-exercise-failure-1").wait
      assert_equal 3, failed.exit_status
      assert_equal "failed", Runsheets::Pages.step_mark(s, s.runbook.step("040-exercise-failure"))

      s.finish_run(status: "completed")
      refute s.active?
      data = JSON.parse(File.read(File.join(s.run.dir, "run.json")))
      assert_equal 2, data["executions"].size
      assert_equal [0, 3], data["executions"].map { it["exit_status"] }
      assert_equal 1, s.history.size
    end
  end

  def test_refuses_blocks_that_are_not_executable
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      assert_raises(Runsheets::RunError) { s.execute("010-say-hello-2") }
      assert_raises(Runsheets::RunError) { s.execute("nope") }
    end
  end

  def test_refuses_to_run_with_a_blank_referenced_input
    with_runs_dir do |root|
      s = session(root)
      s.start_run(inputs: { "NAME" => "" })
      s.instance_variable_get(:@inputs)["NAME"] = ""
      error = assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
      assert_match(/blank input referenced by block: NAME/, error.message)
    end
  end

  def test_secrets_reach_the_process_but_not_the_record
    with_runs_dir do |root|
      s = session(root)
      s.start_run(inputs: { "SECRET_WORD" => "swordfish" })
      ex = s.execute("verify-1").wait
      assert ex.success?
      assert_equal({ "NAME" => "world" }, s.run.inputs)
      refute_includes File.read(File.join(s.run.dir, "run.json")), "swordfish"
    end
  end

  def test_working_directory_defaults_to_runbook_dir
    with_runs_dir do |root|
      s = session(root)
      assert_equal s.runbook.dir, s.working_directory(s.runbook.step("010-say-hello"))
    end
  end
end
