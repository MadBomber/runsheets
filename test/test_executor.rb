# frozen_string_literal: true

require "test_helper"

class TestExecutor < Minitest::Test
  include RunsheetsTest

  def execution(dir, timeout: nil, command: %w[bash])
    Runsheets::Execution.new(id: "e1", block_id: "b-1", step_slug: "s", command:,
                             cmd_path: File.join(dir, "b.cmd"), log_path: File.join(dir, "b.out"), timeout:)
  end

  def test_success_captures_output_and_status
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir), code: "echo out; echo err >&2; exit 0\n")
      assert ex.finished?
      assert ex.success?
      assert_equal 0, ex.exit_status
      assert_equal "out\nerr\n", ex.output
      assert_equal "echo out; echo err >&2; exit 0\n", File.read(ex.cmd_path)
      assert ex.duration >= 0
      assert_equal "finished", ex.to_h[:state]
    end
  end

  def test_failure_exit_status
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir), code: "exit 3\n")
      assert ex.failure?
      assert_equal 3, ex.exit_status
    end
  end

  def test_environment_and_cwd
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir), code: "echo $NAME; pwd\n", env: { "NAME" => "zed" }, cwd: dir)
      assert_equal "zed\n#{File.realpath(dir)}\n", ex.output
    end
  end

  def test_timeout_kills_the_process_group
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir, timeout: 0.3), code: "echo start; sleep 20; echo never\n")
      assert ex.timed_out?
      assert ex.failure?
      assert_equal "start\n", ex.output
      assert ex.duration < 5
    end
  end

  def test_ruby_interpreter
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir, command: %w[ruby]), code: "puts 6 * 7\n")
      assert_equal "42\n", ex.output
    end
  end

  def test_missing_interpreter_fails_to_start
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir, command: %w[definitely-not-a-command-xyz]), code: "x\n")
      assert_equal :failed, ex.state
      assert_match(/ENOENT/, ex.error)
    end
  end

  def test_redacts_secrets_in_output_even_across_chunks
    Dir.mktmpdir do |dir|
      redactor = Runsheets::Redactor.new("PW" => "swordfish")
      ex = Runsheets::Executor.new.run(execution(dir), code: "printf 'pw=swor'; sleep 0.2; printf 'dfish ok\\n'; echo swordfish >&2\n",
                                                       env: { "PW" => "swordfish" }, redactor:)
      assert ex.success?
      assert_equal "pw=[redacted PW] ok\n[redacted PW]\n", ex.output
      refute_includes File.binread(ex.log_path), "swordfish"
    end
  end

  def test_stop_ends_the_process_group_and_records_stopped
    Dir.mktmpdir do |dir|
      executor = Runsheets::Executor.new
      ex = executor.start(execution(dir), code: "echo up; sleep 30; echo never\n")
      wait_for { ex.output.include?("up") }
      assert ex.running?
      executor.stop(ex)
      ex.wait(10)
      assert ex.stopped?
      refute ex.failure?
      refute ex.success?
      assert_equal "up\n", ex.output
      assert_equal "stopped", ex.to_h[:state]
      assert_raises(Errno::ESRCH) { Process.kill(0, -ex.pid) }
    end
  end

  def test_stop_on_a_finished_execution_is_a_no_op
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir), code: "true\n")
      refute ex.request_stop!
      assert ex.success?
    end
  end

  def test_background_flag_is_carried
    Dir.mktmpdir do |dir|
      ex = Runsheets::Execution.new(id: "e", block_id: "b", step_slug: "s", command: %w[bash], cmd_path: File.join(dir, "c"), log_path: File.join(dir, "o"), background: true)
      assert ex.background?
      assert ex.to_h[:background]
    end
  end

  def test_output_tail
    Dir.mktmpdir do |dir|
      ex = Runsheets::Executor.new.run(execution(dir), code: "printf 'abcdef'\n")
      assert_equal "def", ex.output(tail: 3)
      assert_equal 6, ex.output_size
    end
  end
end
