# frozen_string_literal: true

require "test_helper"

# The engineering session: who and why, notes, the runbooks selected in it,
# and how it ends.
class TestSession < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::SessionFixtures

  SHARED = "---\ntitle: Shared\ninputs:\n  - name: NAME\n    default: from-default\n---\n\n## Go\n<!-- kind: manual -->\n\nGo.\n"
  ONE_STEP = { "runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "---\ntitle: One\n---\n" }.freeze
  CHECK = "---\ntitle: One\n---\n\n## Check\n<!-- kind: verify -->\n\n```bash run\necho ok\n```\n"

  def test_needs_an_engineer_and_a_why
    with_runs_dir do |root|
      assert_raises(Runsheets::RunError) { Runsheets::Session.new(engineer: " ", why: "x", runs_root: root) }
      assert_raises(Runsheets::RunError) { Runsheets::Session.new(engineer: "x", why: "", runs_root: root) }
    end
  end

  def test_starting_places_the_session_under_the_runs_root
    with_runs_dir do |root|
      s = start_session(root)
      assert_equal File.join(root, "sessions", s.id), s.dir
      assert_equal "testing", s.why
      refute s.ended?
    end
  end

  def test_starting_writes_the_record_with_why_as_the_first_note
    with_runs_dir do |root|
      data = session_json(start_session(root))
      assert_equal "Tester", data["engineer"]
      assert_equal "running", data["status"]
      assert_equal Process.pid, data["pid"]
      assert_equal(["testing"], data["notes"].map { it["text"] })
    end
  end

  def test_starting_logs_the_engineer_and_why_as_the_first_note
    with_runs_dir do |root|
      log = session_log(start_session(root))
      assert_match(/INFO  \[session\] started engineer="Tester"/, log)
      assert_match(/INFO  \[session\] note: testing/, log)
    end
  end

  def test_notes_are_timestamped_and_need_text
    with_runs_dir do |root|
      s = start_session(root)
      s.note!("  the maintenance turned into an incident ")
      assert_equal "the maintenance turned into an incident", s.notes.last[:text]
      assert_kind_of Time, s.notes.last[:at]
      assert_raises(Runsheets::RunError) { s.note!("   ") }
      assert_equal 2, session_json(s)["notes"].size
    end
  end

  def test_showing_a_runbook_does_not_open_a_run
    with_runs_dir do |root|
      s = start_session(root)
      assert_equal "hello", s.runbook.slug
      assert_nil s.current
      refute s.active?
      assert_empty s.runs
    end
  end

  def test_switching_runbooks_keeps_every_run_open
    with_runs_dir do |root|
      s     = start_session(root)
      hello = s.open(s.runbook, inputs: { "NAME" => "first" })
      disk  = s.open(disk_runbook)
      assert_equal "disk-space-triage", s.runbook.slug
      assert_same disk, s.current
      assert hello.open?, "switching finishes nothing"
      assert_equal %w[hello disk-space-triage], s.runs.map(&:slug)
    end
  end

  def test_returning_to_a_runbook_finds_the_same_run
    with_runs_dir do |root|
      s     = start_session(root)
      hello = s.open(s.runbook, inputs: { "NAME" => "first" })
      s.open(disk_runbook)
      again = s.open(example_runbook, inputs: { "NAME" => "ignored" })
      assert_same hello, again
      assert_equal "first", hello.inputs["NAME"], "returning keeps the run's inputs"
      assert_equal(%w[hello disk-space-triage], session_json(s)["runs"].map { it["runbook"] })
    end
  end

  def test_inputs_given_earlier_are_offered_to_a_later_runbook
    with_env("NAME" => nil) do
      with_runs_dir do |root|
        with_single_file(SHARED, name: "shared.md") do |shared, _|
          s = open_session(root, inputs: { "NAME" => "given-earlier" })
          s.show(shared)
          assert_equal "shared", s.runbook.slug
          assert_equal "given-earlier", s.resolve_inputs["NAME"]
        end
      end
    end
  end

  def test_background_executions_are_seen_and_stopped_from_any_runbook
    with_runs_dir do |root|
      s  = open_session(root)
      bg = s.execute("035-keep-a-clock-running-1")
      s.open(disk_runbook)
      running = s.running
      found   = s.execution(bg.id)
      s.stop(bg.id)
      bg.wait(10)
      assert_equal [[s.run_for("hello"), bg]], running
      assert_same bg, found
      assert bg.stopped?
    end
  end

  def test_ending_closes_every_run_with_the_status_its_work_earns
    with_runs_dir do |root|
      s = ended_session(root)
      assert s.ended?
      assert_equal({ "hello" => "completed", "disk-space-triage" => "opened" }, s.runs.to_h { [it.slug, it.record.status] })
    end
  end

  def test_ending_writes_the_record
    with_runs_dir do |root|
      data = session_json(ended_session(root))
      assert_equal "ended", data["status"]
      assert data["ended_at"]
      assert_equal(%w[completed opened], data["runs"].map { it["status"] })
    end
  end

  def test_ending_logs_how_long_the_session_ran_and_how_each_run_closed
    with_runs_dir do |root|
      s = ended_session(root)
      assert s.ended?
      assert_match(/\[session\] ended \(test\) after \d+s; runs: hello completed, disk-space-triage opened/, session_log(s))
    end
  end

  def test_an_ended_session_cannot_end_again_or_open_a_run
    with_runs_dir do |root|
      s = ended_session(root)
      assert_same s, s.end!("again"), "ending twice does nothing"
      assert_raises(Runsheets::RunError) { s.open(example_runbook) }
    end
  end

  def test_a_killed_session_is_closed_as_interrupted_by_the_next_start
    with_runs_dir do |root|
      old = open_session(root)
      old.execute("010-say-hello-1").wait
      orphan(old)
      fresh = start_session(root)
      assert_equal "interrupted", session_json(old)["status"]
      assert_equal "interrupted", Runsheets::RunRecord.load(old.run.dir).status
      assert_match(/WARN  \[session\] earlier session #{old.id} was left running by a process that is gone/, session_log(fresh))
    end
  end

  def test_a_session_whose_process_is_alive_is_left_alone
    with_runs_dir do |root|
      live = start_session(root)
      assert_empty Runsheets::Session.close_interrupted(root)
      assert_equal "running", session_json(live)["status"], "this process is alive"
    end
  end

  def test_refresh_runbook_keeps_a_runbook_whose_files_did_not_change
    with_runbook(ONE_STEP) do |rb|
      with_runs_dir do |root|
        s = start_session(root, runbook: rb)
        s.open(rb)
        assert_same rb, s.refresh_runbook!
        assert_same rb, s.current.runbook
      end
    end
  end

  def test_refresh_runbook_reloads_an_edited_runbook_and_the_run_carries_on
    with_runbook(ONE_STEP) do |rb|
      with_runs_dir do |root|
        s = start_session(root, runbook: rb)
        s.open(rb)
        write_newer(File.join(rb.dir, "steps", "010-a.md"), "---\ntitle: Two\n---\n")
        reloaded = s.refresh_runbook!
        refute_same rb, reloaded
        assert_equal "Two", s.runbook.steps.first.title
        assert_same s.runbook, s.current.runbook, "the run carries on with the reloaded runbook"
      end
    end
  end

  def test_refresh_runbook_survives_a_broken_edit
    with_runbook(ONE_STEP) do |rb|
      with_runs_dir do |root|
        s = start_session(root, runbook: rb)
        s.open(rb)
        File.delete(File.join(rb.dir, "runbook.md"))
        assert_same rb, s.refresh_runbook!, "a runbook that no longer loads is kept"
        assert_match(/ERROR \[session\] \S+ no longer loads/, session_log(s))
      end
    end
  end

  def test_single_file_runbook_reloads_from_its_own_file
    with_single_file(CHECK, name: "refresh.md") do |rb, path|
      with_runs_dir do |root|
        s = start_session(root, runbook: rb)
        write_newer(path, CHECK.sub("title: One", "title: Two"))
        reloaded = s.refresh_runbook!
        s.open(s.runbook)
        ex = s.execute("010-check-1").wait
        assert_equal "Two", reloaded.title, "an edited single file is reloaded"
        assert s.runbook.single_file?
        assert ex.success?
      end
    end
  end
end
