# frozen_string_literal: true

module RunsheetsTest
  # Fixtures for the session, run and single-file tests: reading back what a
  # session wrote, and building the files and states those tests start from.
  module SessionFixtures
    DISK_RUNBOOK = File.expand_path("../../examples/disk-space-triage.md", __dir__)

    def disk_runbook = Runsheets::Runbook.load(DISK_RUNBOOK)

    def session_json(session) = JSON.parse(File.read(File.join(session.dir, "session.json")))
    def run_json(session)     = JSON.parse(File.read(File.join(session.run.dir, "run.json")))
    def run_md(session)       = File.read(File.join(session.run.dir, "run.md"))
    def session_log(session)  = File.read(session.log.path)

    # +text+ written to a markdown file in a throwaway directory, loaded as a
    # runbook; yields the runbook and the file's path.
    def with_single_file(text, name: "one-file.md")
      Dir.mktmpdir("runsheets-single") do |dir|
        path = File.join(dir, name)
        File.write(path, text)
        yield Runsheets::Runbook.load(path), path
      end
    end

    # Rewrite +path+ with +text+ and date it after any load, on any file system.
    def write_newer(path, text)
      File.write(path, text)
      FileUtils.touch(path, mtime: Time.now + 2)
    end

    # The challenge a destructive block asks for, taken from its refusal.
    def challenge_from(session, block_id)
      session.execute(block_id)
      nil
    rescue Runsheets::Session::ConfirmationRequired => e
      e.challenge
    end

    # Wait until the run record shows no execution still running.
    def wait_until_recorded(session)
      wait_for { run_json(session)["executions"].none? { it["state"] == "running" } }
    end

    # A session that worked hello to the end, opened the disk runbook without
    # doing anything in it, left a note and ended.
    def ended_session(root)
      session = open_session(root)
      session.runbook.steps.each { session.mark_step(it.slug, status: "done") }
      session.open(disk_runbook)
      session.note!("nothing to do on the disk")
      session.end!("test")
    end

    # Make +session+'s record name a process that is gone, as if it was killed.
    def orphan(session)
      data = session_json(session).merge("pid" => 999_999_999)
      File.write(File.join(session.dir, "session.json"), JSON.generate(data))
    end
  end
end
