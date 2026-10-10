# frozen_string_literal: true

require "test_helper"

# The engineering session: who and why, notes, the runbooks selected in it,
# and how it ends.
class TestSession < Minitest::Test
  include RunsheetsTest

  def session_json(session) = JSON.parse(File.read(File.join(session.dir, "session.json")))

  def disk_runbook = Runsheets::Runbook.load(File.expand_path("../examples/disk-space-triage.md", __dir__))

  def test_needs_an_engineer_and_a_why
    with_runs_dir do |root|
      assert_raises(Runsheets::RunError) { Runsheets::Session.new(engineer: " ", why: "x", runs_root: root) }
      assert_raises(Runsheets::RunError) { Runsheets::Session.new(engineer: "x", why: "", runs_root: root) }
    end
  end

  def test_starting_writes_the_record_and_the_log_with_why_as_the_first_note
    with_runs_dir do |root|
      s = start_session(root)
      assert_equal File.join(root, "sessions", s.id), s.dir
      assert_equal "testing", s.why
      data = session_json(s)
      assert_equal "Tester", data["engineer"]
      assert_equal "running", data["status"]
      assert_equal Process.pid, data["pid"]
      assert_equal(["testing"], data["notes"].map { it["text"] })
      log = File.read(s.log.path)
      assert_match(/INFO  \[session\] started engineer="Tester"/, log)
      assert_match(/INFO  \[session\] note: testing/, log)
      refute s.ended?
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

  def test_switching_runbooks_keeps_every_run_open_and_returning_finds_the_same_run
    with_runs_dir do |root|
      s     = start_session(root)
      hello = s.open(s.runbook, inputs: { "NAME" => "first" })
      disk  = s.open(disk_runbook)
      assert_equal "disk-space-triage", s.runbook.slug
      assert_same disk, s.current
      assert hello.open?, "switching finishes nothing"
      assert_same hello, s.open(example_runbook, inputs: { "NAME" => "ignored" })
      assert_equal "first", hello.inputs["NAME"], "returning keeps the run's inputs"
      assert_equal %w[hello disk-space-triage], s.runs.map(&:slug)
      assert_equal(%w[hello disk-space-triage], session_json(s)["runs"].map { it["runbook"] })
    end
  end

  def test_inputs_given_earlier_are_offered_to_a_later_runbook
    with_runs_dir do |root|
      shared = "---\ntitle: Shared\ninputs:\n  - name: NAME\n    default: from-default\n---\n\n## Go\n<!-- kind: manual -->\n\nGo.\n"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "shared.md")
        File.write(path, shared)
        with_env("NAME" => nil) do
          s = open_session(root, inputs: { "NAME" => "given-earlier" })
          s.show(Runsheets::Runbook.load(path))
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
      assert_equal [[s.run_for("hello"), bg]], s.running
      assert_same bg, s.execution(bg.id)
      s.stop(bg.id)
      bg.wait(10)
      assert bg.stopped?
    end
  end

  def test_ending_closes_every_run_with_the_status_its_work_earns
    with_runs_dir do |root|
      s = open_session(root)
      s.runbook.steps.each { s.mark_step(it.slug, status: "done") }
      s.open(disk_runbook)
      s.note!("nothing to do on the disk")
      s.end!("test")
      assert s.ended?
      assert_equal({ "hello" => "completed", "disk-space-triage" => "opened" }, s.runs.to_h { [it.slug, it.record.status] })
      data = session_json(s)
      assert_equal "ended", data["status"]
      assert data["ended_at"]
      assert_equal(%w[completed opened], data["runs"].map { it["status"] })
      assert_match(/\[session\] ended \(test\) after \d+s; runs: hello completed, disk-space-triage opened/, File.read(s.log.path))
      assert_same s, s.end!("again"), "ending twice does nothing"
      assert_raises(Runsheets::RunError) { s.open(example_runbook) }
    end
  end

  def test_a_killed_session_is_closed_as_interrupted_by_the_next_start
    with_runs_dir do |root|
      old = open_session(root)
      old.execute("010-say-hello-1").wait
      data = session_json(old).merge("pid" => 999_999_999) # a process that is gone
      File.write(File.join(old.dir, "session.json"), JSON.generate(data))

      fresh = start_session(root)
      assert_equal "interrupted", session_json(old)["status"]
      assert_equal "interrupted", Runsheets::RunRecord.load(old.run.dir).status
      assert_match(/WARN  \[session\] earlier session #{old.id} was left running by a process that is gone/, File.read(fresh.log.path))
    end
  end

  def test_a_session_whose_process_is_alive_is_left_alone
    with_runs_dir do |root|
      live = start_session(root)
      assert_empty Runsheets::Session.close_interrupted(root)
      assert_equal "running", session_json(live)["status"], "this process is alive"
    end
  end

  def test_refresh_runbook_reloads_only_when_files_changed_and_survives_a_broken_edit
    with_runbook("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "---\ntitle: One\n---\n") do |rb|
      with_runs_dir do |root|
        s = start_session(root, runbook: rb)
        s.open(rb)
        assert_same rb, s.refresh_runbook!
        File.write(File.join(rb.dir, "steps", "010-a.md"), "---\ntitle: Two\n---\n")
        FileUtils.touch(File.join(rb.dir, "steps", "010-a.md"), mtime: Time.now + 2) # newer than the load, on any file system
        refute_same rb, s.refresh_runbook!
        assert_equal "Two", s.runbook.steps.first.title
        assert_same s.runbook, s.current.runbook, "the run carries on with the reloaded runbook"
        kept = s.runbook
        File.delete(File.join(rb.dir, "runbook.md"))
        assert_same kept, s.refresh_runbook!, "a runbook that no longer loads is kept"
        assert_match(/ERROR \[session\] \S+ no longer loads/, File.read(s.log.path))
      end
    end
  end

  def test_single_file_runbook_reloads_from_its_own_file
    Dir.mktmpdir("runsheets-single") do |dir|
      path = File.join(dir, "refresh.md")
      File.write(path, "---\ntitle: One\n---\n\n## Check\n<!-- kind: verify -->\n\n```bash run\necho ok\n```\n")
      with_runs_dir do |root|
        s = start_session(root, runbook: Runsheets::Runbook.load(path))
        File.write(path, File.read(path).sub("title: One", "title: Two"))
        FileUtils.touch(path, mtime: Time.now + 2) # newer than the load, on any file system
        assert_equal "Two", s.refresh_runbook!.title, "an edited single file is reloaded"
        assert s.runbook.single_file?
        s.open(s.runbook)
        assert s.execute("010-check-1").wait.success?
      end
    end
  end
end
