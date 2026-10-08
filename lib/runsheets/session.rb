# frozen_string_literal: true

module Runsheets
  # The operator's state for one runbook: the active run, the inputs it was
  # started with (secrets included, in memory only), and the live executions.
  # Web routes call into this; it knows nothing about HTTP.
  class Session
    attr_reader :runbook, :runs_root, :executor, :run, :token

    def initialize(runbook:, runs_root: Runsheets.runs_dir, executor: Executor.new, token: SecureRandom.hex(16))
      @runbook    = runbook
      @runs_root  = runs_root
      @executor   = executor
      @token      = token
      @run        = nil
      @inputs     = {}
      @executions = {}
      @mutex      = Mutex.new
    end

    def active? = !run.nil? && run.active?

    # Inputs as they will be exported, with runbook defaults and the process
    # environment filled in for anything the operator left blank.
    def resolve_inputs(given = {})
      given = given.to_h.transform_keys(&:to_s)
      runbook.inputs.to_h do |input|
        value = given[input.name]
        value = ENV[input.name] if value.nil? || value.empty?
        value = input.default   if value.nil? || value.empty?
        [input.name, value.to_s]
      end
    end

    def start_run(inputs: {})
      @mutex.synchronize do
        raise RunError, "a run is already active (#{run.id}); finish it first" if active?

        @inputs = resolve_inputs(inputs)
        @executions.clear
        @run = RunRecord.start(runs_root, runbook, inputs: @inputs)
      end
    end

    def finish_run(status: "completed")
      @mutex.synchronize do
        raise RunError, "no active run" unless active?

        run.finish!(status:)
      end
    end

    # Start executing a block. Returns the Execution.
    def execute(block_id)
      @mutex.synchronize do
        raise RunError, "start a run before executing blocks" unless active?

        step, block = runbook.find_block(block_id)
        raise RunError, "unknown block #{block_id}" unless block
        raise RunError, "block #{block_id} is not executable (#{block.kind})" unless block.executable?

        blank = blank_inputs(block)
        raise RunError, "blank input#{'s' if blank.size > 1} referenced by block: #{blank.join(', ')}" if blank.any?

        cmd_path, log_path = run.paths_for(block)
        execution = Execution.new(
          id: SecureRandom.hex(6), block_id: block.id, step_slug: step.slug,
          command: runbook.interpreter_for(block.lang), cmd_path:, log_path:, timeout: step.timeout
        )
        run.record_execution(execution, step:)
        @executions[execution.id] = execution
        executor.start(execution, code: block.code, env: environment_for(execution), cwd: working_directory(step))
        run.write!
        execution
      end
    end

    # A live execution by id. Persists the record the first time a finished
    # execution is observed.
    def execution(id)
      execution = @executions[id]
      return nil unless execution

      if execution.finished? && !@persisted&.include?(id)
        @mutex.synchronize do
          (@persisted ||= Set.new) << id
          run&.write!
        end
      end
      execution
    end

    def executions = @executions.values

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
  end
end
