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

      error = assert_raises(Runsheets::Session::ConfirmationRequired) { s.execute("040-exercise-failure-1") }
      assert_raises(Runsheets::Session::ConfirmationRequired) { s.execute("040-exercise-failure-1", confirm: "wrong") }
      failed = s.execute("040-exercise-failure-1", confirm: error.challenge).wait
      assert_equal 3, failed.exit_status
      assert_equal "failed", Runsheets::Pages.step_mark(s, s.runbook.step("040-exercise-failure"))

      s.finish_run(status: "completed")
      refute s.active?
      data = JSON.parse(File.read(File.join(s.run.dir, "run.json")))
      assert_equal 2, data["executions"].size
      assert_equal([0, 3], data["executions"].map { it["exit_status"] })
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

  def test_destructive_confirmation_is_a_per_block_challenge
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      a = s.challenge_for("040-exercise-failure-1")
      assert_match(/\A[0-9a-f]{4}\z/, a)
      assert_equal a, s.challenge_for("040-exercise-failure-1")
      ex = s.execute("040-exercise-failure-1", confirm: " #{a} ").wait
      assert_equal 3, ex.exit_status
      refute_equal a, s.challenge_for("040-exercise-failure-1"), "a used challenge is retired"
      assert_equal true, s.run.events.find { it[:type] == "execute" }[:confirmed]
    end
  end

  def test_background_block_runs_without_timeout_until_stopped
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      ex = s.execute("035-keep-a-clock-running-1")
      assert ex.background?
      assert_nil ex.timeout
      assert_equal [ex], s.running_executions
      wait_for { ex.output.include?("still here") }
      s.stop(ex.id)
      ex.wait(10)
      assert ex.stopped?
      assert_empty s.running_executions
      assert_equal "ran", Runsheets::Pages.step_mark(s, s.runbook.step("035-keep-a-clock-running"))
      assert_raises(Runsheets::RunError) { s.stop("nope") }
    end
  end

  def test_finishing_the_run_stops_whatever_is_still_running
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      bg = s.execute("035-keep-a-clock-running-1")
      wait_for { bg.output.include?("still here") }
      s.finish_run(status: "abandoned")
      assert bg.stopped?
      refute s.active?
      data = JSON.parse(File.read(File.join(s.run.dir, "run.json")))
      assert_equal "stopped", data["executions"].first["state"]
    end
  end

  def test_acknowledge_records_terminal_blocks_only
    with_runs_dir do |root|
      s = session(root)
      assert_raises(Runsheets::RunError) { s.acknowledge("020-inspect-ruby-3") }
      s.start_run
      ack = s.acknowledge("020-inspect-ruby-3", note: "  pressed enter ")
      assert_equal "pressed enter", ack[:note]
      assert_equal "pressed enter", s.ack("020-inspect-ruby-3")[:note]
      assert_equal "ran", Runsheets::Pages.step_mark(s, s.runbook.step("020-inspect-ruby"))
      assert_raises(Runsheets::RunError) { s.acknowledge("020-inspect-ruby-1") }
      assert_raises(Runsheets::RunError) { s.acknowledge("nope") }
      assert_includes File.read(File.join(s.run.dir, "run.md")), "confirmed run in the operator's terminal — pressed enter"
    end
  end

  def test_secrets_are_redacted_from_captured_output
    with_runs_dir do |root|
      s = session(root)
      s.start_run(inputs: { "SECRET_WORD" => "swordfish" })
      ex = s.execute("verify-2").wait
      assert ex.success?
      assert_includes ex.output, "the secret is [redacted SECRET_WORD]"
      refute_includes File.binread(ex.log_path), "swordfish"
      refute_includes File.read(File.join(s.run.dir, "run.md")), "swordfish"
      assert_equal %w[SECRET_WORD], s.secret_inputs_set
    end
  end

  def test_verification_run_executes_only_verify_documents
    with_runs_dir do |root|
      s = session(root)
      s.start_verification(inputs: { "NAME" => "v" })
      assert s.verifying?
      assert s.run.verify?
      error = assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
      assert_match(/verification run only executes/, error.message)
      ex = s.execute("045-check-the-greeting-1").wait
      assert ex.success?
      assert_includes ex.output, "greeting looks right"
      assert s.execute("verify-1").wait.success?
      s.finish_run
      refute s.verifying?
      assert s.run.verified?(steps: s.runbook.steps.size)
    end
  end

  def test_verification_needs_verify_documents
    with_runbook("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "```bash run\ntrue\n```\n") do |rb|
      with_runs_dir do |root|
        s = Runsheets::Session.new(runbook: rb, runs_root: root)
        assert_raises(Runsheets::RunError) { s.start_verification }
        refute s.active?
      end
    end
  end

  def test_stamp_offer_after_a_clean_verification_and_write_back
    files = {
      "runbook.md" => "---\ntitle: T\nlast_verified: 2020-01-01\n---\n",
      "steps/010-a.md" => "---\nkind: verify\n---\n```bash run\necho ok\n```\n"
    }
    with_runbook(files) do |rb|
      with_runs_dir do |root|
        s = Runsheets::Session.new(runbook: rb, runs_root: root)
        refute s.stampable?
        s.start_verification
        refute s.stampable?, "not while active"
        s.execute("010-a-1").wait
        s.finish_run
        assert s.stampable?
        assert_equal Date.today, s.stamp_date

        date = s.stamp!
        assert_equal Date.today, date
        assert_equal "last_verified: #{Date.today}", File.read(File.join(rb.dir, "runbook.md"))[/^last_verified:.*$/]
        assert_equal Date.today.to_s, s.runbook.last_verified.to_s, "runbook reloaded"
        assert s.run.stamped?
        refute s.stampable?, "already stamped"
        assert_raises(Runsheets::RunError) { s.stamp! }
      end
    end
  end

  def test_stamp_offer_after_a_full_run_needs_every_step_done
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      s.runbook.steps.each { s.mark_step(it.slug, status: "done") }
      s.finish_run
      assert s.stampable?, "example last_verified 2026-10-07 is older than today"
      s.dismiss_stamp!
      refute s.stampable?

      s.start_run
      s.runbook.steps.each { s.mark_step(it.slug, status: "done") }
      s.finish_run(status: "abandoned")
      refute s.stampable?

      s.start_run
      s.runbook.steps[0..-2].each { s.mark_step(it.slug, status: "done") }
      s.finish_run
      refute s.stampable?, "one step not done"
    end
  end

  def test_stamp_is_not_offered_when_last_verified_is_not_older
    files = { "runbook.md" => "---\ntitle: T\nlast_verified: #{Date.today}\n---\n", "steps/010-a.md" => "---\nkind: manual\n---\ndo it\n" }
    with_runbook(files) do |rb|
      with_runs_dir do |root|
        s = Runsheets::Session.new(runbook: rb, runs_root: root)
        s.start_run
        s.mark_step("010-a", status: "done")
        s.finish_run
        refute s.stampable?
      end
    end
  end

  def test_refresh_runbook_reloads_only_when_files_changed_and_survives_a_broken_edit
    with_runbook("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "---\ntitle: One\n---\n") do |rb|
      with_runs_dir do |root|
        s = Runsheets::Session.new(runbook: rb, runs_root: root)
        assert_same rb, s.refresh_runbook!
        sleep 0.01
        File.write(File.join(rb.dir, "steps", "010-a.md"), "---\ntitle: Two\n---\n")
        refute_same rb, s.refresh_runbook!
        assert_equal "Two", s.runbook.steps.first.title
        kept = s.runbook
        sleep 0.01
        File.delete(File.join(rb.dir, "runbook.md"))
        assert_same kept, s.refresh_runbook!, "a runbook that no longer loads is kept"
      end
    end
  end

  def test_working_directory_defaults_to_runbook_dir
    with_runs_dir do |root|
      s = session(root)
      assert_equal s.runbook.dir, s.working_directory(s.runbook.step("010-say-hello"))
    end
  end

  def test_single_file_runbook_reloads_and_stamps_from_its_own_file
    Dir.mktmpdir("runsheets-single") do |dir|
      path = File.join(dir, "refresh.md")
      File.write(path, "---\ntitle: One\nlast_verified: 2020-01-01\n---\n\n## Check\n<!-- kind: verify -->\n\n```bash run\necho ok\n```\n")
      with_runs_dir do |root|
        s = Runsheets::Session.new(runbook: Runsheets::Runbook.load(path), runs_root: root)
        assert s.runbook.single_file?

        sleep 0.01
        File.write(path, File.read(path).sub("title: One", "title: Two"))
        assert_equal "Two", s.refresh_runbook!.title, "an edited single file is reloaded"
        assert s.runbook.single_file?

        s.start_verification
        s.execute("010-check-1").wait
        s.finish_run
        assert_equal Date.today, s.stamp!
        assert_equal Date.today.to_s, s.runbook.last_verified.to_s, "reloaded after the stamp"
        assert_includes File.read(path), "last_verified: #{Date.today}"
      end
    end
  end

  def test_finish_run_with_a_bad_status_changes_nothing
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      bg = s.execute("035-keep-a-clock-running-1")
      wait_for { bg.output.include?("still here") }
      assert_raises(Runsheets::RunError) { s.finish_run(status: "bogus") }
      assert s.active?
      assert bg.running?, "a refused finish stops nothing"
      s.finish_run(status: "abandoned")
    end
  end

  def test_only_numbered_steps_can_be_marked
    with_runs_dir do |root|
      s = session(root)
      s.start_run
      assert_raises(Runsheets::RunError) { s.mark_step("runbook", status: "done") }
      assert_raises(Runsheets::RunError) { s.mark_step("verify", status: "done") }
      assert_raises(Runsheets::RunError) { s.mark_step("rollback", status: "done") }
      assert_equal 0, s.run.steps_done
    end
  end

  def test_abandon_if_active_stops_what_is_running_and_is_a_no_op_otherwise
    with_runs_dir do |root|
      s = session(root)
      assert_same s, s.abandon_if_active
      s.start_run
      bg = s.execute("035-keep-a-clock-running-1")
      wait_for { bg.output.include?("still here") }
      s.abandon_if_active
      refute s.active?
      assert bg.stopped?
      assert_equal "abandoned", s.run.status
    end
  end
end

class TestSessionSlug < Minitest::Test
  include RunsheetsTest

  def test_reloading_keeps_a_library_slug
    with_runs_dir do |root|
      rb = Runsheets::Runbook.load(RunsheetsTest::EXAMPLE_DIR, slug: "ops/hello")
      s  = Runsheets::Session.new(runbook: rb, runs_root: root)
      assert_equal "ops/hello", s.reload_runbook!.slug
      s.start_run
      assert_equal File.join(root, "ops/hello"), File.dirname(s.run.dir)
      s.finish_run
      assert_equal 1, s.history.size
    end
  end
end
