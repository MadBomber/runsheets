# frozen_string_literal: true

module Runsheets
  # Spawns block code as a child process group, captures stdout and stderr
  # to the execution's log file, and reaps it in a background thread.
  #
  # Every execution is a fresh process: nothing carries over between blocks
  # except the environment the session passes in.
  class Executor
    GRACE = 2.0   # seconds between TERM and KILL on timeout
    POLL  = 0.05

    attr_reader :clock

    def initialize(clock: Time)
      @clock = clock
    end

    # Write +code+ to the execution's cmd file and start it. Returns the
    # execution, now running (or failed if it could not start).
    def start(execution, code:, env: {}, cwd: nil)
      File.write(execution.cmd_path, code)
      log = File.open(execution.log_path, "w")
      pid = Process.spawn(
        env.transform_keys(&:to_s).transform_values(&:to_s),
        *execution.command, execution.cmd_path,
        chdir: cwd || Dir.pwd, pgroup: true,
        in: File::NULL, out: log, err: log
      )
      execution.started!(pid, at: clock.now)
      execution.attach(Thread.new { reap(execution, pid) })
    rescue SystemCallError => e
      execution.failed!("#{e.class}: #{e.message}", at: clock.now)
    ensure
      log&.close
    end

    # Start and wait. Handy for scripts and tests.
    def run(execution, **) = start(execution, **).wait

    private

    def reap(execution, pid)
      deadline = execution.timeout && monotonic + execution.timeout

      loop do
        _, status = Process.wait2(pid, Process::WNOHANG)
        return execution.finished!(status, at: clock.now) if status

        if deadline && monotonic > deadline
          status = kill_group(pid) || Process.wait2(pid).last
          return execution.finished!(status, at: clock.now, timed_out: true)
        end

        sleep POLL
      end
    rescue SystemCallError => e
      execution.failed!("#{e.class}: #{e.message}", at: clock.now)
    end

    # TERM the whole process group, then KILL whatever is still there.
    # Returns the child's status if it was reaped here, else nil.
    def kill_group(pid)
      signal(pid, "TERM")
      stop = monotonic + GRACE
      while monotonic < stop
        reaped = Process.wait2(pid, Process::WNOHANG)
        return reaped.last if reaped

        sleep POLL
      end
      signal(pid, "KILL")
      nil
    end

    def signal(pid, name)
      Process.kill(name, -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
