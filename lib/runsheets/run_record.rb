# frozen_string_literal: true

require "fileutils"

module Runsheets
  # The runsheet: everything that happened during one run of a runbook.
  #
  #   <runs_root>/<runbook-slug>/<yyyymmddThhmmss>/
  #     run.json        machine-readable record
  #     run.md          human-readable transcript
  #     blocks/
  #       <block-id>.<n>.cmd   the exact code that ran
  #       <block-id>.<n>.out   its stdout + stderr, secrets redacted
  #
  # Runs live outside the runbook so captured output never lands next to the
  # docs in a repository.
  class RunRecord
    TIMESTAMP       = "%Y%m%dT%H%M%S"
    STATUSES        = %w[running completed abandoned].freeze
    FINAL_STATUSES  = %w[completed abandoned].freeze
    KINDS           = %w[run verify].freeze
    TRANSCRIPT_TAIL = 64 * 1024

    attr_reader :dir, :runbook_slug, :runbook_title, :kind, :started_at, :finished_at, :status,
                :inputs, :events, :executions, :step_status, :acks

    # Create the run directory and write the initial record. Secret inputs are
    # never stored. +kind+ is "run" (the whole procedure) or "verify" (only
    # the verify documents).
    def self.start(runs_root, runbook, inputs: {}, kind: "run", now: Time.now)
      raise ArgumentError, "unknown run kind #{kind}" unless KINDS.include?(kind)

      name = now.strftime(TIMESTAMP)
      name += "-verify" if kind == "verify"
      dir = unique_dir(File.join(runs_root, runbook.slug, name))
      FileUtils.mkdir_p(File.join(dir, "blocks"))
      visible = inputs.reject { |name, _| runbook.input(name)&.secret? }.transform_keys(&:to_s)
      new(dir:, runbook_slug: runbook.slug, runbook_title: runbook.title, kind:, started_at: now, inputs: visible).write!
    end

    # Read a record back from its run.json.
    def self.load(dir)
      data = JSON.parse(File.read(File.join(dir, "run.json")))
      new(
        dir:, runbook_slug: data["runbook"], runbook_title: data["title"], kind: data["kind"] || "run",
        started_at: Time.iso8601(data["started_at"]),
        finished_at: data["finished_at"] && Time.iso8601(data["finished_at"]),
        status: data["status"], inputs: data["inputs"] || {},
        events: (data["events"] || []).map { it.transform_keys(&:to_sym) },
        executions: (data["executions"] || []).map { it.transform_keys(&:to_sym) },
        step_status: data["steps"] || {},
        acks: (data["acks"] || {}).transform_values { it.transform_keys(&:to_sym) }
      )
    end

    # Previous runs of a runbook, newest first.
    def self.list(runs_root, slug)
      Dir.glob(File.join(runs_root, slug, "*", "run.json")).filter_map do |path|
        load(File.dirname(path))
      rescue JSON::ParserError, ArgumentError, KeyError
        nil
      end.sort_by(&:started_at).reverse
    end

    def self.unique_dir(dir)
      return dir unless File.exist?(dir)

      n = 2
      n += 1 while File.exist?("#{dir}-#{n}")
      "#{dir}-#{n}"
    end

    # Whether an execution hash (as stored in the record) counts as a
    # failure. A background process the operator stopped is not one.
    def self.failure?(hash)
      case hash[:state]
      when "timed_out", "failed" then true
      when "finished"            then hash[:exit_status] != 0
      else false
      end
    end

    def initialize(dir:, runbook_slug:, runbook_title:, started_at:, kind: "run", inputs: {}, status: "running",
                   finished_at: nil, events: [], executions: [], step_status: {}, acks: {})
      @dir           = dir
      @runbook_slug  = runbook_slug
      @runbook_title = runbook_title
      @kind          = kind
      @started_at    = started_at
      @finished_at   = finished_at
      @status        = status
      @inputs        = inputs
      @events        = events
      @executions    = executions
      @step_status   = step_status
      @acks          = acks
      @live          = {}
    end

    def id         = File.basename(dir)
    def active?    = status == "running"
    def completed? = status == "completed"
    def verify?    = kind == "verify"
    def blocks_dir = File.join(dir, "blocks")
    def duration   = (finished_at || Time.now) - started_at

    # [cmd path, log path] for the next execution of a block.
    def paths_for(block)
      n    = executions.count { it[:block_id] == block.id } + 1
      base = File.join(blocks_dir, "#{block.id}.#{n}")
      ["#{base}.cmd", "#{base}.out"]
    end

    # +confirmed+ records that the operator typed the destructive
    # confirmation before this execution.
    def record_execution(execution, step:, confirmed: false, at: Time.now)
      event = { type: "execute", at: at.iso8601(3), step: step.slug, block: execution.block_id, execution: execution.id }
      event[:confirmed] = true if confirmed
      events << event
      @live[execution.id] = execution
      executions << execution.to_h.merge(step: step.slug)
      self
    end

    def mark_step(step, status:, note: nil, at: Time.now)
      events << { type: "step", at: at.iso8601(3), step: step.slug, status:, note: }.compact
      step_status[step.slug] = status
      self
    end

    # The operator confirms they ran a terminal block themselves.
    def acknowledge(block, step:, note: nil, at: Time.now)
      ack = { at: at.iso8601(3), step: step.slug, note: }.compact
      events << { type: "ack", block: block.id, **ack }
      acks[block.id] = ack
      self
    end

    def finish!(status: "completed", at: Time.now)
      raise ArgumentError, "unknown status #{status}" unless FINAL_STATUSES.include?(status)

      @status      = status
      @finished_at = at
      write!
    end

    def failed_executions = executions.select { RunRecord.failure?(it) }
    def steps_done        = step_status.count { |_, s| s == "done" }

    # The most recent execution of each block, keyed by block id.
    def latest_executions = executions.to_h { [it[:block_id], it] }

    # Blocks whose most recent execution failed. A failure that was re-run
    # successfully does not count.
    def unresolved_failures = latest_executions.values.select { RunRecord.failure?(it) }

    # The step the run was last working on: the step of the latest event.
    def last_step = events.reverse_each.find { it[:step] }&.[](:step)

    # How the runbook has drifted since this run: for the latest execution
    # of each block, whether the block's code is still what ran. Returns
    # entries only for blocks that changed or disappeared.
    def drift(runbook)
      latest_executions.filter_map do |block_id, hash|
        recorded = read_block_file(hash[:cmd])
        _, block = runbook.find_block(block_id)
        if block.nil?
          { block_id:, status: :missing, recorded: }
        elsif Diff.changed?(recorded, block.code)
          { block_id:, status: :changed, recorded:, current: block.code, diff: Diff.lines(recorded, block.code) }
        end
      end
    end

    def execution(id) = @live[id] || executions.find { it[:id] == id }

    # Pull the latest state from live executions into their hashes.
    def refresh!
      executions.each do |hash|
        live = @live[hash[:id]]
        hash.merge!(live.to_h) if live
      end
      self
    end

    def write!
      refresh!
      File.write(File.join(dir, "run.json"), JSON.pretty_generate(to_h))
      File.write(File.join(dir, "run.md"), transcript)
      self
    end

    def to_h
      {
        runbook: runbook_slug, title: runbook_title, id:, kind:, status:,
        started_at: started_at.iso8601(3), finished_at: finished_at&.iso8601(3),
        duration: duration.round(3), inputs:, steps: step_status, acks:, events:, executions:
      }
    end

    def summary
      { id:, kind:, started_at:, finished_at:, status:, duration:, executions: executions.size,
        failures: failed_executions.size, unresolved: unresolved_failures.size, steps_done:,
        last_step: }
    end

    # The human-readable run.md.
    def transcript
      lines = transcript_header
      lines << "" << "## Timeline" << ""
      events.each { lines.concat(event_lines(it)) }
      "#{lines.join("\n")}\n"
    end

    private

    def transcript_header
      lines = ["# #{runbook_title} — #{verify? ? 'verification' : 'run'} #{id}", "",
               "- Runbook: `#{runbook_slug}`",
               "- Kind: #{verify? ? 'verification (verify documents only)' : 'full run'}",
               "- Started: #{started_at.iso8601}",
               "- Finished: #{finished_at&.iso8601 || 'in progress'}",
               "- Status: #{status}"]
      return lines if inputs.empty?

      lines << "- Inputs:"
      inputs.each { |k, v| lines << "  - `#{k}` = `#{v}`" }
      lines
    end

    # The transcript lines for one event, ending with a blank line.
    def event_lines(event)
      case event[:type]
      when "execute" then execution_transcript(event)
      when "step"    then ["- #{event[:at]} step **#{event[:step]}** marked #{event[:status]}#{note_suffix(event)}", ""]
      when "ack"     then ["- #{event[:at]} `#{event[:block]}` (#{event[:step]}) confirmed run in the operator's terminal#{note_suffix(event)}", ""]
      else []
      end
    end

    def note_suffix(event) = event[:note] ? " — #{event[:note]}" : ""

    def execution_transcript(event)
      hash  = executions.find { it[:id] == event[:execution] } || {}
      lines = [execution_title(event, hash), ""]
      lines << "```#{command_lang(hash)}" << read_block_file(hash[:cmd]).chomp << "```" << ""
      output = read_block_file(hash[:log], tail: TRANSCRIPT_TAIL)
      lines << "Output:" << "" << "```text" << output.chomp << "```" << "" unless output.empty?
      lines
    end

    def execution_title(event, hash)
      title = "### #{event[:at]} `#{event[:block]}` (#{event[:step]}) — #{verdict_for(hash)}"
      title += " in #{hash[:duration]}s" if hash[:duration]
      tags = execution_tags(event, hash)
      tags.empty? ? title : "#{title} [#{tags.join(', ')}]"
    end

    def verdict_for(hash)
      case hash[:state]
      when "finished"  then hash[:exit_status] == 0 ? "ok" : "exit #{hash[:exit_status]}"
      when "timed_out" then "timed out"
      when "stopped"   then "stopped"
      when "failed"    then "failed to start: #{hash[:error]}"
      else hash[:state].to_s
      end
    end

    def execution_tags(event, hash)
      tags = []
      tags << "background" if hash[:background]
      tags << "confirmed" if event[:confirmed]
      tags
    end

    def command_lang(hash) = File.basename(Array(hash[:command]).first.to_s)

    def read_block_file(name, tail: nil)
      return "" unless name

      path = File.join(blocks_dir, name)
      return "" unless File.file?(path)

      size = File.size(path)
      text = tail && size > tail ? "[… #{size - tail} earlier bytes omitted]\n#{File.binread(path, tail, size - tail)}" : File.binread(path)
      text.force_encoding("UTF-8").scrub
    end
  end
end
