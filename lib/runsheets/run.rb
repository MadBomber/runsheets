# frozen_string_literal: true

module Runsheets
  # One runbook's part of a session: the run the engineer established by
  # selecting the runbook, its inputs (secrets included, in memory only),
  # its record, and the executions it started. A run stays open until the
  # session ends; there is no finishing it by hand.
  #
  # Everything it does is written to the run's record and the session log.
  # It knows nothing about HTTP.
  class Run
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

    attr_reader :session, :runbook, :record, :inputs

    # Establish the run: resolve +given+ inputs, write the record's first
    # version under the session's id, and log it.
    def initialize(session:, runbook:, inputs: {})
      @session    = session
      @runbook    = runbook
      @executions = {}
      @challenges = {}
      @mutex      = Mutex.new
      @inputs     = Run.resolve_inputs(runbook, inputs, carried: session.carried_inputs)
      @redactor   = Redactor.for(@inputs, runbook)
      @record     = RunRecord.start(session.runs_root, runbook, session_id: session.id, inputs: @inputs)
      log_opened
    end

    # Inputs as they will be exported. For each declared input: the value
    # given, else one given for the same name earlier in the session
    # (+carried+, never a secret), else the environment, else the default.
    def self.resolve_inputs(runbook, given = {}, carried: {})
      given = given.to_h.transform_keys(&:to_s)
      runbook.inputs.to_h do |input|
        name   = input.name
        values = [given[name], (carried[name] unless input.secret?), ENV[name], input.default]
        [name, values.find { !it.to_s.empty? }.to_s]
      end
    end

    # +given+ with every blank secret filled from +current+.
    def self.keep_blank_secrets(runbook, given, current)
      runbook.inputs.select(&:secret?).each_with_object(given.dup) do |input, out|
        out[input.name] = current[input.name] if out[input.name].to_s.empty?
      end
    end

    def slug = runbook.slug
    def open? = record.active?

    # Raise unless the run is still open.
    def ensure_open!
      raise RunError, "the run for #{slug} has ended" unless open?
    end

    # The runbook reloaded from disk (see Session#refresh_runbook!).
    def runbook=(runbook)
      @mutex.synchronize { @runbook = runbook }
    end

    # Change the inputs partway. Recorded and logged; secrets as "[secret]".
    # A secret left blank keeps its current value.
    def change_inputs(given)
      given = Run.keep_blank_secrets(runbook, given.to_h.transform_keys(&:to_s), @inputs)
      @mutex.synchronize do
        @inputs   = Run.resolve_inputs(runbook, given, carried: {})
        @redactor = Redactor.for(@inputs, runbook)
        record.change_inputs(@inputs, runbook)
        record.write!
      end
      log.info("inputs changed #{inputs_text}", tags: [slug])
      self
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
        if block.destructive? && !confirmed?(block_id, confirm)
          log.warn("destructive block #{block_id} refused: #{confirm.nil? ? 'needs' : 'wrong'} confirmation code", tags: [slug, step.slug])
          raise ConfirmationRequired.new(block_id, challenge_for(block_id))
        end

        execution = build_execution(step, block)
        record.record_execution(execution, step:, confirmed: block.destructive?)
        @executions[execution.id] = execution
        log_execute(execution, step, block)
        execution.on_end { ended(it) }
        session.executor.start(execution, code: block.code, env: environment_for(execution), cwd: working_directory(step), redactor: @redactor)
        record.write!
        execution
      end
    end

    # The step and block for an id, or a RunError saying why it cannot run.
    def executable_block!(block_id)
      ensure_open!

      step, block = runbook.find_block(block_id)
      raise RunError, "unknown block #{block_id}" unless block
      raise RunError, "block #{block_id} is not executable (#{block.kind})" unless block.executable?

      blank = blank_inputs(block)
      raise RunError, "blank input#{'s' if blank.size > 1} referenced by block: #{blank.join(', ')}" if blank.any?

      [step, block]
    end

    # A pending Execution for a block, with its files allocated in the run.
    def build_execution(step, block)
      cmd_path, log_path = record.paths_for(block)
      id = SecureRandom.hex(6)
      Execution.new(
        id:, block_id: block.id, step_slug: step.slug,
        command: runbook.interpreter_for(block.lang), cmd_path:, log_path:,
        timeout: block.background? ? nil : step.timeout, background: block.background?,
        tee: log.output_stream(["##{id}"])
      )
    end

    # The confirmation code currently expected for a destructive block,
    # issuing one if none is outstanding.
    def challenge_for(block_id) = @challenges[block_id] ||= SecureRandom.hex(2)

    # Stop a running execution. Returns the Execution; the state changes to
    # :stopped once the reaper has ended the process group.
    def stop(execution_id)
      execution = @executions[execution_id] or raise RunError, "no execution #{execution_id}"
      log.info("stop requested", tags: [slug, execution.step_slug, "##{execution.id}"])
      session.executor.stop(execution)
      execution
    end

    # Record that the operator ran a terminal block themselves.
    def acknowledge(block_id, note: nil)
      note = Run.note(note)
      ack = @mutex.synchronize do
        ensure_open!

        step, block = runbook.find_block(block_id)
        raise RunError, "unknown block #{block_id}" unless block
        raise RunError, "block #{block_id} is not a terminal block (#{block.kind})" unless block.acknowledgeable?

        record.acknowledge(block, step:, note:)
        record.write!
        record.acks[block.id]
      end
      log.info("confirmed terminal block #{block_id} run by hand#{": #{note}" if note}", tags: [slug, ack[:step]])
      ack
    end

    def ack(block_id) = record.acks[block_id]

    # A live execution of this run by id, or nil.
    def execution(id) = @executions[id]

    def executions         = @executions.values
    def running_executions = executions.select(&:running?)

    # Only numbered steps can be marked: the landing page and the extra
    # documents are not part of the procedure's progress.
    def mark_step(step_slug, status:, note: nil)
      note = Run.note(note)
      @mutex.synchronize do
        ensure_open!

        step = runbook.step(step_slug) or raise RunError, "unknown step #{step_slug}"
        raise RunError, "#{step_slug} is not a numbered step" unless step.position

        record.mark_step(step, status:, note:)
        record.write!
      end
      log.info("marked #{status}#{": #{note}" if note}", tags: [slug, step_slug])
    end

    def step_status(step_slug) = record.step_status[step_slug]

    # End the run with the session: stop whatever it left running, and
    # close the record with the status worked out from what was done.
    # Returns that status.
    def close!
      stop_all
      status = record.closing_status(runbook.steps.map(&:slug))
      record.finish!(status:)
      status
    end

    # Declared inputs the block refers to that have no value.
    def blank_inputs(block)
      declared = runbook.inputs.map(&:name)
      (block.referenced_variables & declared).select { @inputs[it].to_s.empty? }
    end

    def environment_for(execution)
      @inputs.merge(
        "RUNSHEETS_SESSION_ID" => session.id,
        "RUNSHEETS_RUN_ID"     => record.id,
        "RUNSHEETS_RUN_DIR"    => record.dir,
        "RUNSHEETS_RUNBOOK"    => slug,
        "RUNSHEETS_STEP"       => execution.step_slug,
        "RUNSHEETS_BLOCK"      => execution.block_id
      )
    end

    def working_directory(step)
      step.cwd ? File.expand_path(step.cwd, runbook.dir) : runbook.dir
    end

    # A note as recorded: stripped, nil when blank.
    def self.note(text)
      text = text.to_s.strip
      text.empty? ? nil : text
    end

    # The inputs as the log shows them: NAME=value, secrets as [secret].
    def inputs_text
      runbook.inputs.map { "#{it.name}=#{it.secret? ? '[secret]' : @inputs[it.name]}" }.join(" ")
    end

    # How an ended execution reads in the log, and at what level.
    def self.ending(execution)
      took = execution.duration ? format(" in %.2fs", execution.duration) : ""
      case execution.state
      when :finished
        execution.exit_status.zero? ? ["info", "finished exit 0#{took}"] : ["warn", "finished exit #{execution.exit_status}#{took}"]
      when :timed_out then ["warn", "timed out after #{execution.timeout}s"]
      when :stopped   then ["info", "stopped#{took}"]
      else ["error", "failed to start: #{execution.error}"]
      end
    end

    private

    def log = session.log

    def log_opened
      log.info("run opened #{inputs_text}".strip, tags: [slug])
      runbook.warnings.each { log.warn("authoring warning: #{it}", tags: [slug]) }
    end

    def log_execute(execution, step, block)
      tags = [slug, step.slug, "##{execution.id}"]
      log.info("execute #{block.lang} via #{execution.command.join(' ')}#{' (confirmed)' if block.destructive?}#{' (background)' if block.background?}", tags:)
      log.info(block.code.chomp.lines.map { "$ #{it.chomp}" }.join("\n"), tags: ["##{execution.id}"])
      log.debug("environment #{environment_text(execution)}", tags:)
    end

    def environment_text(execution)
      secrets = runbook.inputs.select(&:secret?).map(&:name)
      environment_for(execution).map { |k, v| "#{k}=#{secrets.include?(k) ? '[secret]' : v}" }.join(" ")
    end

    # Runs on the reaper thread once an execution has ended: log how it
    # ended and save the record.
    def ended(execution)
      level, text = Run.ending(execution)
      log.add(level, text, tags: ["##{execution.id}"])
      record.write!
    end

    # Does +confirm+ match the code issued for this block? A match retires
    # the code.
    def confirmed?(block_id, confirm)
      return false unless confirm.is_a?(String) && confirm.strip == challenge_for(block_id)

      @challenges.delete(block_id)
      true
    end

    # Stop every running execution and wait for the reapers, briefly.
    def stop_all
      running = running_executions
      running.each { session.executor.stop(it) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STOP_WAIT
      running.each do |execution|
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        execution.wait(left) if left.positive?
      end
      record.write!
    end
  end
end
