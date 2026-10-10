# frozen_string_literal: true

require "fileutils"
require "socket"

module Runsheets
  # The engineering session: everything that happens between `runsheets`
  # starting and stopping. It belongs to one engineer and opens with a note
  # saying why. Selecting a runbook establishes that runbook's Run; the
  # engineer can switch between runbooks freely, and every run stays open
  # until the session ends.
  #
  #   <runs_root>/sessions/<session-id>/
  #     session.json   engineer, host, times, status, notes, the runs
  #     session.log    every action and its output, appended as it happens
  #
  # The runbook on screen is #runbook; the methods the pages and routes call
  # for "this runbook" (execute, mark_step, run, ...) go to its run.
  class Session
    ConfirmationRequired = Run::ConfirmationRequired

    SESSIONS = "sessions"
    STATUSES = %w[running ended interrupted].freeze

    attr_reader :engineer, :started_at, :ended_at, :notes, :runs_root, :library, :token, :executor, :log, :dir, :runbook

    # Start a session: create its directory and log, close any earlier
    # session left running by a killed process, and record +why+ as the
    # first note. +runbook+ is the one runbook served, when there is no
    # library. +echo+ is the IO the log is echoed to (nil for none).
    def initialize(engineer:, why:, runs_root: Runsheets.runs_dir, library: nil, runbook: nil, token: SecureRandom.hex(16),
                   executor: Executor.new, log_level: "info", echo: nil, now: Time.now)
      raise RunError, "who is starting the session? An engineer name is needed" if engineer.to_s.strip.empty?
      raise RunError, "why is the session being started? A note is needed" if why.to_s.strip.empty?

      @engineer   = engineer.to_s.strip
      @runs_root  = runs_root
      @library    = library
      @token      = token
      @executor   = executor
      @started_at = now
      @notes      = []
      @runs       = {}
      @mutex      = Mutex.new
      @ending     = false
      @dir        = RunRecord.create_unique_dir(File.join(Session.root(runs_root), now.strftime(RunRecord::TIMESTAMP)))
      @log = SessionLog.new(File.join(@dir, "session.log"), level: log_level, echo:)
      start(why, Session.close_interrupted(runs_root, except: @dir))
      show(runbook) if runbook
    end

    # Where sessions are kept under a runs directory.
    def self.root(runs_root) = File.join(runs_root, SESSIONS)

    # Close every session (and its runs) still marked running whose process
    # is gone: it was killed, so nothing closed it. A session whose process
    # is still alive on this host is another runsheets, and is left alone,
    # as is the session at +except+ (a directory). Returns the ids closed.
    def self.close_interrupted(runs_root, except: nil)
      paths = Dir.glob(File.join(root(runs_root), "*", "session.json")) - [File.join(except.to_s, "session.json")]
      paths.filter_map do |path|
        data = JSON.parse(File.read(path))
        next unless data.is_a?(Hash) && data["status"] == "running" && !running_here?(data)

        interrupt(File.dirname(path), data, runs_root:)
        data["id"]
      rescue StandardError # unreadable, or not a session record: leave it
        nil
      end
    end

    # Mark a killed session, and the runs it lists, interrupted. The end
    # time is the last write to its log.
    def self.interrupt(dir, data, runs_root:)
      root    = File.expand_path(runs_root)
      log     = File.join(dir, "session.log")
      ended   = File.file?(log) ? File.mtime(log) : Time.now
      runs    = Array(data["runs"]).grep(Hash)
      runs.each do |run|
        next unless File.expand_path(run["dir"].to_s).start_with?("#{root}/")

        record = RunRecord.load(run["dir"])
        record.finish!(status: "interrupted", at: ended) if record.active?
        run["status"] = record.status
      rescue StandardError
        next
      end
      Runsheets.write_atomic(File.join(dir, "session.json"),
                             JSON.pretty_generate(data.merge("status" => "interrupted", "ended_at" => ended.iso8601(3), "runs" => runs)))
    end

    # The records of the sessions kept under +runs_root+, newest first,
    # leaving out the one at +except+; unreadable ones are skipped. The
    # first note (the why) is copied into each as "why".
    def self.past(runs_root, except: nil)
      sessions = Dir.glob(File.join(root(runs_root), "*", "session.json")).filter_map do |path|
        next if File.dirname(path) == except

        data = JSON.parse(File.read(path))
        next unless data.is_a?(Hash)

        data.merge("why" => Array(data["notes"]).grep(Hash).first&.fetch("text", nil))
      rescue StandardError
        nil
      end
      sessions.sort_by { it["started_at"].to_s }.reverse
    end

    # Is the session in +data+ still being written by a live process on
    # this host?
    def self.running_here?(data) = data["host"] == Socket.gethostname && alive?(data["pid"])

    def self.alive?(pid)
      return false unless pid.is_a?(Integer)

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def id     = File.basename(dir)
    def host   = Socket.gethostname
    def status = ended_at ? "ended" : "running"
    def ended? = !ended_at.nil?
    def why    = notes.first&.fetch(:text)
    def elapsed(now = Time.now) = (ended_at || now) - started_at

    # Add a timestamped note to the session.
    def note!(text, at: Time.now)
      text = text.to_s.strip
      raise RunError, "a note needs some text" if text.empty?

      @mutex.synchronize do
        notes << { at:, text: }
        write!
      end
      log.info("note: #{text}", tags: ["session"])
      self
    end

    # --- runbooks and runs ---------------------------------------------

    # The runs of this session, in the order their runbooks were selected.
    def runs = @runs.values

    def run_for(slug) = @runs[slug]

    # The run of the runbook on screen, if it has one.
    def current = runbook && @runs[runbook.slug]

    # Put +runbook+ on screen without establishing a run. The run it may
    # already have takes the fresh copy.
    def show(runbook)
      @mutex.synchronize do
        @runbook = runbook
        @runs[runbook.slug]&.runbook = runbook
      end
      runbook
    end

    # Select a runbook: put it on screen and establish its run with
    # +inputs+, or return to the run it already has. Returns the Run.
    def open(runbook, inputs: {})
      show(runbook)
      @mutex.synchronize do
        raise RunError, "this session is ending" if @ending || ended?

        existing = @runs[runbook.slug]
        return existing if existing

        run = @runs[runbook.slug] = Run.new(session: self, runbook:, inputs:)
        write!
        run
      end
    end

    # Non-secret input values given earlier in the session, by name. A run
    # opened later is offered them as defaults.
    def carried_inputs = runs.map { it.record.inputs }.reduce({}, :merge)

    # Inputs as the start form shows them for the runbook on screen.
    def resolve_inputs(given = {}) = Run.resolve_inputs(runbook, given, carried: carried_inputs)

    # Reload the runbook on screen if any of its markdown files changed,
    # so an edit is reflected on the next page. Block ids stay stable unless
    # fences are added or removed, so its run carries on. A runbook that no
    # longer loads is kept as it was.
    def refresh_runbook!
      return runbook unless runbook&.stale?

      log.debug("reloaded #{runbook.slug}: its files changed", tags: ["session"])
      show(Runbook.load(runbook.single_file? ? runbook.main_path : runbook.dir, slug: runbook.slug, root: runbook.root))
    rescue RunbookError, SystemCallError => e
      log.error("#{runbook.slug} no longer loads: #{e.message}", tags: ["session"])
      runbook.checked!
      runbook
    end

    # --- the runbook on screen ------------------------------------------

    def active? = !current.nil? && current.open?

    # The record of the runbook on screen's run.
    def run = current&.record

    def execute(block_id, confirm: nil)        = current!.execute(block_id, confirm:)
    def acknowledge(block_id, note: nil)       = current!.acknowledge(block_id, note:)
    def mark_step(slug, status:, note: nil)    = current!.mark_step(slug, status:, note:)
    def change_inputs(given)                   = current!.change_inputs(given)
    def step_status(slug)                      = current&.step_status(slug)
    def ack(block_id)                          = current&.ack(block_id)
    def secret_inputs_set                      = current&.secret_inputs_set || []
    def history                                = RunRecord.list(runs_root, runbook.slug)

    # The run of the runbook on screen, or a RunError saying there is none.
    def current!
      current or raise RunError, "start the run for #{runbook&.title || 'a runbook'} before executing blocks"
    end

    # --- executions across every run ------------------------------------

    def executions         = runs.flat_map(&:executions)
    def running_executions = executions.select(&:running?)

    # [run, execution] for each execution still running, in any runbook.
    def running = runs.flat_map { |run| run.running_executions.map { [run, it] } }

    def execution(id) = runs.lazy.filter_map { it.execution(id) }.first

    # Stop an execution, whichever runbook started it.
    def stop(execution_id)
      run = runs.find { it.execution(execution_id) } or raise RunError, "no execution #{execution_id}"
      run.stop(execution_id)
    end

    # --- ending ----------------------------------------------------------

    # End the session: close every run (stopping what it left running) with
    # the status its work earns, and write the record. +how+ says what ended
    # it, for the log. Ending twice does nothing.
    def end!(how, at: Time.now)
      return self unless begin_ending

      runs.each(&:stop_running!)
      closed = runs.map { "#{it.slug} #{close_run(it)}" }
      @mutex.synchronize do
        @ended_at = at
        write!
      end
      log.info("ended (#{how}) after #{format('%.0f', elapsed)}s; runs: #{closed.empty? ? 'none' : closed.join(', ')}", tags: ["session"])
      self
    end

    def to_h
      {
        id:, engineer:, host:, pid: Process.pid, runsheets: VERSION, status:,
        started_at: started_at.iso8601(3), ended_at: ended_at&.iso8601(3),
        library: library&.dir, log: log.path,
        notes: notes.map { { at: it[:at].iso8601(3), text: it[:text] } },
        runs: runs.map { { runbook: it.slug, title: it.runbook.title, dir: it.record.dir, status: it.record.status } }
      }
    end

    def write!
      Runsheets.write_atomic(File.join(dir, "session.json"), JSON.pretty_generate(to_h))
      self
    end

    private

    # Claim the ending: true for the first caller only. From here on no run
    # is opened.
    def begin_ending
      @mutex.synchronize do
        return false if @ending || ended?

        @ending = true
      end
    end

    # Close a run, and say what became of it even when closing fails.
    def close_run(run)
      run.close!
    rescue StandardError => e
      log.error("could not close #{run.slug}: #{e.class}: #{e.message}", tags: ["session"])
      "error"
    end

    def start(why, interrupted)
      where = library ? "library=#{library.dir}" : nil
      log.info(["started engineer=#{engineer.inspect} host=#{host} pid=#{Process.pid} runsheets=#{VERSION}", where, "log=#{log.path}"].compact.join(" "),
               tags: ["session"])
      interrupted.each { log.warn("earlier session #{it} was left running by a process that is gone; closed it as interrupted", tags: ["session"]) }
      note!(why, at: started_at)
    end
  end
end
