# frozen_string_literal: true

require "test_helper"

# One runbook's run inside a session: executing, confirming, marking,
# stopping, and how it closes.
class TestRun < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::SessionFixtures

  def test_resolve_inputs_uses_given_then_earlier_in_the_session_then_env_then_default
    rb = example_runbook
    with_env("SECRET_WORD" => "from-env", "NAME" => nil) do
      assert_equal({ "NAME" => "given", "SECRET_WORD" => "from-env" }, Runsheets::Run.resolve_inputs(rb, { "NAME" => "given" }))
      assert_equal "world", Runsheets::Run.resolve_inputs(rb, { "NAME" => "" })["NAME"]
      carried = { "NAME" => "earlier", "SECRET_WORD" => "never carried" }
      resolved = Runsheets::Run.resolve_inputs(rb, {}, carried:)
      assert_equal "earlier", resolved["NAME"]
      assert_equal "from-env", resolved["SECRET_WORD"], "a secret is never carried between runs"
    end
  end

  def test_execute_needs_the_run_of_the_runbook_on_screen
    with_runs_dir do |root|
      s = start_session(root)
      refute s.active?
      error = assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
      assert_match(/start the run for Hello, runsheets/, error.message)
    end
  end

  def test_opening_a_run_makes_the_session_active
    with_runs_dir do |root|
      s = open_session(root, inputs: { "NAME" => "tester" })
      assert s.active?
      assert_equal s.id, s.run.id, "the run directory is named by the session"
    end
  end

  def test_executing_a_block_captures_its_output_and_marks_the_step_ran
    with_runs_dir do |root|
      s    = open_session(root, inputs: { "NAME" => "tester" })
      ex   = s.execute("010-say-hello-1").wait
      mark = Runsheets::Pages.step_mark(s, s.runbook.step("010-say-hello"))
      s.mark_step("010-say-hello", status: "done", note: "  ")
      assert ex.success?
      assert_includes ex.output, "Hello, tester!"
      assert_includes ex.output, "Running block 010-say-hello-1 of step 010-say-hello in run #{s.run.id}"
      assert_same ex, s.execution(ex.id)
      assert_equal "ran", mark
      assert_equal "done", s.step_status("010-say-hello")
    end
  end

  def test_a_destructive_block_refuses_to_run_without_its_challenge
    with_runs_dir do |root|
      s = open_session(root)
      assert_raises(Runsheets::Session::ConfirmationRequired) { s.execute("040-exercise-failure-1") }
      assert_raises(Runsheets::Session::ConfirmationRequired) { s.execute("040-exercise-failure-1", confirm: "wrong") }
    end
  end

  def test_a_destructive_block_runs_with_the_challenge_it_asked_for
    with_runs_dir do |root|
      s      = open_session(root)
      failed = s.execute("040-exercise-failure-1", confirm: challenge_from(s, "040-exercise-failure-1")).wait
      assert_equal 3, failed.exit_status
      assert_equal "failed", Runsheets::Pages.step_mark(s, s.runbook.step("040-exercise-failure"))
    end
  end

  def test_the_reaper_saves_the_record_when_an_execution_ends
    with_runs_dir do |root|
      s = open_session(root, inputs: { "NAME" => "tester" })
      s.execute("010-say-hello-1").wait
      s.execute("040-exercise-failure-1", confirm: challenge_from(s, "040-exercise-failure-1")).wait
      wait_until_recorded(s)
      data = run_json(s)
      assert_equal 2, data["executions"].size
      assert_equal([0, 3], data["executions"].map { it["exit_status"] }, "the reaper saves the record when an execution ends")
      assert_equal s.id, data["session"]
      assert_equal 1, s.history.size
    end
  end

  def test_refuses_blocks_that_are_not_executable
    with_runs_dir do |root|
      s = open_session(root)
      assert_raises(Runsheets::RunError) { s.execute("010-say-hello-2") }
      assert_raises(Runsheets::RunError) { s.execute("nope") }
    end
  end

  def test_refuses_to_run_with_a_blank_referenced_input
    with_runs_dir do |root|
      s = open_session(root, inputs: { "NAME" => "" })
      s.current.inputs["NAME"] = ""
      error = assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
      assert_match(/blank input referenced by block: NAME/, error.message)
    end
  end

  def test_secrets_reach_the_process_but_not_the_record_or_the_log
    with_runs_dir do |root|
      s = open_session(root, inputs: { "SECRET_WORD" => "swordfish" })
      ex = s.execute("verify-1").wait
      assert ex.success?
      assert_equal({ "NAME" => "world" }, s.run.inputs)
      refute_includes File.read(File.join(s.run.dir, "run.json")), "swordfish"
      refute_includes session_log(s), "swordfish"
      assert_includes session_log(s), "SECRET_WORD=[secret]"
    end
  end

  def test_destructive_challenge_is_stable_until_used
    with_runs_dir do |root|
      run = open_session(root).current
      a = run.challenge_for("040-exercise-failure-1")
      assert_match(/\A[0-9a-f]{4}\z/, a)
      assert_equal a, run.challenge_for("040-exercise-failure-1")
    end
  end

  def test_a_used_destructive_challenge_is_retired_and_the_confirmation_recorded
    with_runs_dir do |root|
      s   = open_session(root)
      a   = s.current.challenge_for("040-exercise-failure-1")
      ex  = s.execute("040-exercise-failure-1", confirm: " #{a} ").wait
      assert_equal 3, ex.exit_status
      refute_equal a, s.current.challenge_for("040-exercise-failure-1"), "a used challenge is retired"
      assert_equal true, s.run.events.find { it[:type] == "execute" }[:confirmed]
    end
  end

  def test_a_background_block_runs_without_a_timeout
    with_runs_dir do |root|
      s  = open_session(root)
      ex = s.execute("035-keep-a-clock-running-1")
      running = s.running_executions
      wait_for { ex.output.include?("still here") }
      s.stop(ex.id)
      ex.wait(10)
      assert ex.background?
      assert_nil ex.timeout
      assert_equal [ex], running
    end
  end

  def test_a_background_block_runs_until_stopped
    with_runs_dir do |root|
      s  = open_session(root)
      ex = s.execute("035-keep-a-clock-running-1")
      wait_for { ex.output.include?("still here") }
      s.stop(ex.id)
      ex.wait(10)
      assert ex.stopped?
      assert_empty s.running_executions
      assert_equal "ran", Runsheets::Pages.step_mark(s, s.runbook.step("035-keep-a-clock-running"))
      assert_raises(Runsheets::RunError) { s.stop("nope") }
    end
  end

  def test_acknowledge_needs_an_open_run
    with_runs_dir do |root|
      s = start_session(root)
      assert_raises(Runsheets::RunError) { s.acknowledge("020-inspect-ruby-3") }
      refute s.active?
    end
  end

  def test_acknowledge_records_terminal_blocks
    with_runs_dir do |root|
      s   = open_session(root)
      ack = s.acknowledge("020-inspect-ruby-3", note: "  pressed enter ")
      assert_equal "pressed enter", ack[:note]
      assert_equal "pressed enter", s.ack("020-inspect-ruby-3")[:note]
      assert_equal "ran", Runsheets::Pages.step_mark(s, s.runbook.step("020-inspect-ruby"))
      assert_includes run_md(s), "confirmed run in the operator's terminal — pressed enter"
    end
  end

  def test_acknowledge_refuses_blocks_that_are_not_terminal_blocks
    with_runs_dir do |root|
      s = open_session(root)
      assert_raises(Runsheets::RunError) { s.acknowledge("020-inspect-ruby-1") }
      assert_raises(Runsheets::RunError) { s.acknowledge("nope") }
    end
  end

  def test_secrets_are_redacted_from_captured_output
    with_runs_dir do |root|
      s = open_session(root, inputs: { "SECRET_WORD" => "swordfish" })
      ex = s.execute("verify-2").wait
      assert ex.success?
      assert_includes ex.output, "the secret is [redacted SECRET_WORD]"
      refute_includes File.binread(ex.log_path), "swordfish"
      refute_includes run_md(s), "swordfish"
      assert_equal %w[SECRET_WORD], s.secret_inputs_set
    end
  end

  def test_checks_run_inside_the_run
    with_runs_dir do |root|
      s = open_session(root, inputs: { "NAME" => "v" })
      ex = s.execute("045-check-the-greeting-1").wait
      assert ex.success?
      assert_includes ex.output, "greeting looks right"
      assert s.execute("verify-1").wait.success?
      assert s.execute("010-say-hello-1").wait.success?, "a run executes any step, checks or not"
    end
  end

  def test_working_directory_defaults_to_runbook_dir
    with_runs_dir do |root|
      s = open_session(root)
      assert_equal s.runbook.dir, s.current.working_directory(s.runbook.step("010-say-hello"))
      assert_equal s.runbook.dir, s.current.working_directory(s.runbook.step("020-inspect-ruby"))
    end
  end

  def test_only_numbered_steps_can_be_marked
    with_runs_dir do |root|
      s = open_session(root)
      assert_raises(Runsheets::RunError) { s.mark_step("runbook", status: "done") }
      assert_raises(Runsheets::RunError) { s.mark_step("verify", status: "done") }
      assert_raises(Runsheets::RunError) { s.mark_step("rollback", status: "done") }
      assert_equal 0, s.run.steps_done
    end
  end

  def test_changing_inputs_is_used_from_then_on_and_recorded
    with_runs_dir do |root|
      s = open_session(root, inputs: { "NAME" => "first", "SECRET_WORD" => "one" })
      s.change_inputs("NAME" => "second", "SECRET_WORD" => "two")
      output = s.execute("010-say-hello-1").wait.output
      assert_includes output, "Hello, second!"
      assert_equal({ "NAME" => "second" }, s.run.events.find { it[:type] == "inputs" }[:inputs])
      assert_includes session_log(s), "inputs changed NAME=second SECRET_WORD=[secret]"
      assert_includes run_md(s), "inputs changed: `NAME` = `second`"
    end
  end

  def test_a_blank_secret_keeps_its_value_when_inputs_change
    with_runs_dir do |root|
      s = open_session(root, inputs: { "NAME" => "first", "SECRET_WORD" => "two" })
      s.change_inputs("NAME" => "third", "SECRET_WORD" => "")
      assert_equal "two", s.current.inputs["SECRET_WORD"], "a blank secret keeps its value"
      assert_equal "third", s.current.inputs["NAME"]
    end
  end

  def test_closing_stops_what_is_running_and_derives_the_status
    with_runs_dir do |root|
      s  = open_session(root)
      bg = s.execute("035-keep-a-clock-running-1")
      wait_for { bg.output.include?("still here") }
      status = s.current.close!
      data   = run_json(s)
      assert_equal "partial", status
      assert bg.stopped?
      refute s.active?
      assert_equal "stopped", data["executions"].first["state"]
      assert_equal "partial", data["status"]
      assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
    end
  end

  def test_ending_lines_say_how_an_execution_ended
    ex = Struct.new(:state, :exit_status, :duration, :timeout, :error)
    assert_equal ["info", "finished exit 0 in 0.25s"], Runsheets::Run.ending(ex.new(:finished, 0, 0.25, nil, nil))
    assert_equal ["warn", "finished exit 3 in 1.00s"], Runsheets::Run.ending(ex.new(:finished, 3, 1.0, nil, nil))
    assert_equal ["warn", "timed out after 30s"], Runsheets::Run.ending(ex.new(:timed_out, nil, 30.1, 30, nil))
    assert_equal ["info", "stopped in 2.00s"], Runsheets::Run.ending(ex.new(:stopped, nil, 2.0, nil, nil))
    assert_equal ["error", "failed to start: ENOENT"], Runsheets::Run.ending(ex.new(:failed, nil, nil, nil, "ENOENT"))
  end

  def test_a_library_slug_names_the_run_directory
    with_runs_dir do |root|
      rb = Runsheets::Runbook.load(RunsheetsTest::EXAMPLE_DIR, slug: "ops/hello")
      s  = open_session(root, runbook: rb)
      assert_equal File.join(root, "ops/hello"), File.dirname(s.run.dir)
      assert_equal 1, s.history.size
    end
  end
end
