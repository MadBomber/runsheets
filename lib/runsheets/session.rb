# frozen_string_literal: true

module Runsheets
  # The operator's state for one runbook: the active run, the inputs it was
  # started with (secrets included, in memory only), and the live executions.
  # Web routes call into this; it knows nothing about HTTP.
  class Session
    # Raised when a destructive block is executed without the typed
    # confirmation. Carries the code the operator has to type.
    class ConfirmationRequired < RunError
      attr_reader :challenge, :block_id

      def initialize(block_id, challenge)
        @block_id  = block_id
        @challenge = challenge
        super("destructive block #{block_id} needs confirmation: type #{challenge}")
      end
    end

    STOP_WAIT = Executor::GRACE + 1.0

    attr_reader :runbook, :runs_root, :executor, :run, :token

    def initialize(runbook:, runs_root: Runsheets.runs_dir, executor: Executor.new, token: SecureRandom.hex(16))
      @runbook    = runbook
      @runs_root  = runs_root
      @executor   = executor
      @token      = token
      @run        = nil
      @inputs     = {}
      @redactor   = Redactor.new({})
      @executions = {}
      @challenges = {}
      @persisted  = Set.new
      @stamp_dismissed = false
      @mutex      = Mutex.new
    end

    def active? = !run.nil? && run.active?

    # Inputs as they will be exported, with runbook defaults and the process
    # environment filled in for anything the operator left blank.
    def resolve_inputs(given = {})
      given = given.to_h.transform_keys(&:to_s)
      runbook.inputs.to_h do |input|
        value = given[input.name]
        value = ENV[input.name]  if value.nil? || value.empty?
        value = input.default   if value.nil? || value.empty?
        [input.name, value.to_s]
      end
    end

    # Start a run. kind: "run" walks the whole procedure; "verify" may only
    # execute the verify documents (verify-kind steps and verify.md).
    def start_run(inputs: {}, kind: "run")
      @mutex.synchronize do
        raise RunError, "a run is already active (#{run.id}); finish it first" if active?
        raise RunError, "this runbook has no verify steps or verify.md to run" if kind == "verify" && runbook.verify_documents.empty?

        @inputs   = resolve_inputs(inputs)
        @redactor = Redactor.for(@inputs, runbook)
        @executions.clear
        @challenges.clear
        @stamp_dismissed = false
        @run = RunRecord.start(runs_root, runbook, inputs: @inputs, kind:)
      end
    end

    def start_verification(inputs: {}) = start_run(inputs:, kind: "verify")

    def verifying? = active? && run.verify?

    # End the run. Anything still running is stopped first.
    def finish_run(status: "completed")
      @mutex.synchronize do
        raise RunError, "no active run" unless active?

        stop_all
        run.finish!(status:)
      end
    end

    # --- last_verified write-back ------------------------------------------

    # The finished run that could stamp runbook.md, or nil: it must have
    # verified the runbook (see RunRecord#verified?), not been stamped or
    # dismissed, and carry a date newer than the one already there.
    def stamp_candidate
      return nil if run.nil? || active? || @stamp_dismissed || run.stamped?
      return nil unless run.verified?(steps: runbook.steps.size)
      return nil if runbook.last_verified && runbook.last_verified.to_s >= stamp_date.to_s

      run
    end

    def stampable? = !stamp_candidate.nil?

    # The date a stamp would write: the day the run started.
    def stamp_date = run&.started_at&.to_date

    # Write last_verified into runbook.md, note it in the run record, and
    # reload the runbook so the pages show the new date. Returns the date.
    def stamp!
      @mutex.synchronize do
        candidate = stamp_candidate or raise RunError, "the last run cannot stamp last_verified"

        date = stamp_date
        runbook.stamp_last_verified(date)
        candidate.stamp!(date)
        reload_runbook!
        date
      end
    end

    def dismiss_stamp!
      @stamp_dismissed = true
      self
    end

    # Re-read the runbook directory. Used after a stamp and whenever the
    # files change on disk (see #refresh_runbook!).
    def reload_runbook!
      @runbook = Runbook.load(runbook.dir)
    end

    # Reload the runbook if any of its markdown files changed since it was
    # loaded, so editing a runbook while the server is up is reflected on
    # the next page. Block ids stay stable unless fences are added or
    # removed, so an active run carries on. A runbook that no longer loads
    # is kept as it was; the next successful load replaces it.
    def refresh_runbook!
      return runbook unless runbook.stale?

      reload_runbook!
    rescue RunbookError
      runbook
    end

    # Names of secret inputs that have a value, for display as "set".
    def secret_inputs_set = runbook.inputs.select(&:secret?).map(&:name).reject { @inputs[it].to_s.empty? }

    # Start executing a block. Returns the Execution.
    #
    # A destructive block needs +confirm+ to equal the challenge issued for
    # it; the first attempt without one raises ConfirmationRequired carrying
    # the challenge.
    def execute(block_id, confirm: nil)
      @mutex.synchronize do
        step, block = executable_block!(block_id)
        check_confirmation!(block, confirm) if block.destructive?

        execution = build_execution(step, block)
        run.record_execution(execution, step:, confirmed: block.destructive?)
        @executions[execution.id] = execution
        executor.start(execution, code: block.code, env: environment_for(execution), cwd: working_directory(step), redactor: @redactor)
        run.write!
        execution
      end
    end

    # The step and block for an id, or a RunError saying why it cannot run
    # right now.
    def executable_block!(block_id)
      raise RunError, "start a run before executing blocks" unless active?

      step, block = runbook.find_block(block_id)
      raise RunError, "unknown block #{block_id}" unless block
      raise RunError, "block #{block_id} is not executable (#{block.kind})" unless block.executable?
      if run.verify? && !runbook.verify_document?(step)
        raise RunError, "a verification run only executes verify steps and verify.md; #{block_id} is in #{step.slug}"
      end

      blank = blank_inputs(block)
      raise RunError, "blank input#{'s' if blank.size > 1} referenced by block: #{blank.join(', ')}" if blank.any?

      [step, block]
    end

    # A pending Execution for a block, with its files allocated in the run.
    def build_execution(step, block)
      cmd_path, log_path = run.paths_for(block)
      Execution.new(
        id: SecureRandom.hex(6), block_id: block.id, step_slug: step.slug,
        command: runbook.interpreter_for(block.lang), cmd_path:, log_path:,
        timeout: block.background? ? nil : step.timeout, background: block.background?
      )
    end

    # The confirmation code currently expected for a destructive block,
    # issuing one if none is outstanding.
    def challenge_for(block_id) = @challenges[block_id] ||= SecureRandom.hex(2)

    # Stop a running execution (a background process, or a run block that
    # is taking too long). Returns the Execution; the state changes to
    # :stopped once the reaper has ended the process group.
    def stop(execution_id)
      execution = @executions[execution_id] or raise RunError, "no execution #{execution_id}"
      executor.stop(execution)
      execution
    end

    # Record that the operator ran a terminal block themselves.
    def acknowledge(block_id, note: nil)
      @mutex.synchronize do
        raise RunError, "start a run before acknowledging blocks" unless active?

        step, block = runbook.find_block(block_id)
        raise RunError, "unknown block #{block_id}" unless block
        raise RunError, "block #{block_id} is not a terminal block (#{block.kind})" unless block.acknowledgeable?

        run.acknowledge(block, step:, note: note.to_s.strip.empty? ? nil : note.strip)
        run.write!
        run.acks[block.id]
      end
    end

    def ack(block_id) = run&.acks&.[](block_id)

    # A live execution by id. Persists the record the first time a finished
    # execution is observed.
    def execution(id)
      execution = @executions[id]
      return nil unless execution

      if execution.finished? && !@persisted.include?(id)
        @mutex.synchronize do
          @persisted << id
          run&.write!
        end
      end
      execution
    end

    def executions         = @executions.values
    def running_executions = executions.select(&:running?)

    def mark_step(slug, status:, note: nil)
      @mutex.synchronize do
        raise RunError, "no active run" unless active?

        step = runbook.step(slug) or raise RunError, "unknown step #{slug}"
        run.mark_step(step, status:, note: note.to_s.strip.empty? ? nil : note.strip)
        run.write!
      end
    end

    def step_status(slug) = run&.step_status&.[](slug)

    def history = RunRecord.list(runs_root, runbook.slug)

    # Declared inputs the block refers to that have no value.
    def blank_inputs(block)
      declared = runbook.inputs.map(&:name)
      (block.referenced_variables & declared).select { @inputs[it].to_s.empty? }
    end

    def environment_for(execution)
      @inputs.merge(
        "RUNSHEETS_RUN_ID"  => run.id,
        "RUNSHEETS_RUN_DIR" => run.dir,
        "RUNSHEETS_RUNBOOK" => runbook.slug,
        "RUNSHEETS_STEP"    => execution.step_slug,
        "RUNSHEETS_BLOCK"   => execution.block_id
      )
    end

    def working_directory(step)
      step.cwd ? File.expand_path(step.cwd, runbook.dir) : runbook.dir
    end

    private

    def check_confirmation!(block, confirm)
      expected = challenge_for(block.id)
      unless confirm.is_a?(String) && confirm.strip == expected
        raise ConfirmationRequired.new(block.id, expected)
      end

      @challenges.delete(block.id)
    end

    # Stop every running execution and wait for the reapers, briefly.
    def stop_all
      running = running_executions
      running.each { executor.stop(it) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STOP_WAIT
      running.each do |execution|
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        execution.wait(left) if left.positive?
      end
      run.write!
    end
  end
end
