# frozen_string_literal: true

module Runsheets
  # Spawns block code as a child process group, pumps its stdout and stderr
  # through the run's Redactor into the execution's log file, and reaps it
  # in a background thread.
  #
  # Every execution is a fresh process: nothing carries over between blocks
  # except the environment the session passes in.
  class Executor
    GRACE = 2.0   # seconds between TERM and KILL on timeout or stop
    DRAIN = 1.0   # seconds to wait for the output pump after the process exits
    POLL  = 0.05
    CHUNK = 64 * 1024

    attr_reader :clock

    def initialize(clock: Time)
      @clock = clock
    end

    # Write +code+ to the execution's cmd file and start it. Returns the
    # execution, now running (or failed if it could not start). The
    # execution's tee, when it has one, also receives the redacted output as
    # it arrives and is closed at the end of the stream.
    def start(execution, code:, env: {}, cwd: nil, redactor: nil)
      File.write(execution.cmd_path, code)
      log            = File.open(execution.log_path, "wb") # rubocop:disable Style/FileOpen -- closed by the pump thread
      reader, writer = IO.pipe
      pid = Process.spawn(
        env.transform_keys(&:to_s).transform_values(&:to_s),
        *execution.command, execution.cmd_path,
        chdir: cwd || Dir.pwd, pgroup: true,
        in: File::NULL, out: writer, err: writer
      )
      writer.close
      pump = Thread.new { pump(reader, log, redactor || Redactor.new({}), execution.tee) }
      execution.started!(pid, at: clock.now)
      execution.attach(Thread.new { reap(execution, pid, pump) })
    rescue SystemCallError => e
      writer&.close
      reader&.close
      log&.close
      execution.tee&.close
      execution.failed!("#{e.class}: #{e.message}", at: clock.now)
    end

    # Start and wait. Handy for scripts and tests.
    def run(execution, **) = start(execution, **).wait

    # Ask a running execution to end: TERM to its process group, then KILL.
    # The reaper does the signalling; the execution ends up :stopped.
    def stop(execution)
      execution.request_stop!
      execution
    end

    # Copy the child's output into the log, redacting as it goes. Runs until
    # every holder of the pipe's write end has closed it.
    def pump(io, log, redactor, tee = nil)
      while (chunk = io.readpartial(CHUNK))
        safe = redactor.feed(chunk)
        log.write(safe)
        log.flush
        tee&.write(safe)
      end
    rescue IOError
      nil
    ensure
      rest = redactor.flush
      log.write(rest)
      log.close
      io.close
      tee&.write(rest)
      tee&.close
    end

    private

    def reap(execution, pid, pump)
      deadline = execution.timeout && (monotonic + execution.timeout)

      loop do
        _, status = Process.wait2(pid, Process::WNOHANG)
        return finish(execution, pump, status) if status
        return finish(execution, pump, end_group(pid), stopped: true) if execution.stop_requested?
        return finish(execution, pump, end_group(pid), timed_out: true) if deadline && monotonic > deadline

        sleep POLL
      end
    rescue SystemCallError => e
      execution.failed!("#{e.class}: #{e.message}", at: clock.now)
    end

    # Let the pump drain, then record how the process ended.
    def finish(execution, pump, status, **how)
      pump.join(DRAIN)
      execution.finished!(status, at: clock.now, **how)
    end

    # Kill the group and return the child's status however it was reaped.
    def end_group(pid) = kill_group(pid) || Process.wait2(pid).last

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
