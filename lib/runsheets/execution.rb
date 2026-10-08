# frozen_string_literal: true

module Runsheets
  # One execution of a block: what ran, where its output went, how it ended.
  # Executor drives the state transitions; everything else only reads.
  class Execution
    STATES = %i[pending running finished timed_out stopped failed].freeze

    attr_reader :id, :block_id, :step_slug, :command, :cmd_path, :log_path, :timeout,
                :state, :pid, :started_at, :finished_at, :exit_status, :signal, :error

    def initialize(id:, block_id:, step_slug:, command:, cmd_path:, log_path:, timeout: nil, background: false)
      @id         = id
      @block_id   = block_id
      @step_slug  = step_slug
      @command    = Array(command).map(&:to_s)
      @cmd_path   = cmd_path
      @log_path   = log_path
      @timeout    = timeout
      @background = background
      @state      = :pending
      @stop       = false
      @mutex      = Mutex.new
      @thread     = nil
    end

    def background? = @background
    def pending?    = state == :pending
    def running?    = state == :running
    def finished?   = %i[finished timed_out stopped failed].include?(state)
    def timed_out?  = state == :timed_out
    def stopped?    = state == :stopped
    def success?    = state == :finished && exit_status == 0
    def failure?    = finished? && !success? && !stopped?

    def stop_requested? = @stop

    def duration = started_at && finished_at ? finished_at - started_at : nil

    # Block until the process has been reaped (or +limit+ seconds pass).
    def wait(limit = nil)
      @thread&.join(limit)
      self
    end

    # Captured stdout+stderr. With +tail+, only the last that many bytes.
    def output(tail: nil)
      return "" unless log_path && File.file?(log_path)

      size = File.size(log_path)
      text = if tail && size > tail
               File.binread(log_path, tail, size - tail)
             else
               File.binread(log_path)
             end
      text.force_encoding("UTF-8").scrub
    end

    def output_size = (log_path && File.size?(log_path)) || 0

    def to_h
      {
        id:, block_id:, step: step_slug, command:, background: background?, state: state.to_s, pid:,
        started_at: started_at&.iso8601(3), finished_at: finished_at&.iso8601(3),
        duration: duration&.round(3), exit_status:, signal:, error:,
        cmd: cmd_path && File.basename(cmd_path), log: log_path && File.basename(log_path)
      }
    end

    # --- transitions, called by Executor -----------------------------------

    def started!(pid, at:)
      @mutex.synchronize do
        @pid        = pid
        @started_at = at
        @state      = :running
      end
      self
    end

    def attach(thread)
      @thread = thread
      self
    end

    # Ask the executor's reaper to end the process group. Returns true if
    # there was something to stop.
    def request_stop!
      @mutex.synchronize do
        return false unless running?

        @stop = true
      end
    end

    def finished!(status, at:, timed_out: false, stopped: false)
      @mutex.synchronize do
        @finished_at = at
        @exit_status = status&.exitstatus || (status&.termsig && 128 + status.termsig)
        @signal      = status&.termsig
        @state       = if timed_out then :timed_out
                       elsif stopped then :stopped
                       else :finished
                       end
      end
      self
    end

    def failed!(message, at:)
      @mutex.synchronize do
        @finished_at = at
        @error       = message
        @state       = :failed
      end
      self
    end
  end
end
