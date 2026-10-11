# frozen_string_literal: true

require "stringio"

module RunsheetsTest
  # Fixtures for the CLI, Config and SessionLog tests.
  module CliFixtures
    SANDBOXED_ENV = %w[HOME XDG_CONFIG_HOME].freeze

    # What one CLI.run returned and printed.
    CliRun = Data.define(:status, :out, :err)

    # An empty home and no RUNSHEETS_* variables until #restore_home!.
    def sandbox_home!
      @home = Dir.mktmpdir("runsheets-home")
      @saved_env = (ENV.keys.grep(/\ARUNSHEETS_/) + SANDBOXED_ENV).to_h { [it, ENV.fetch(it, nil)] }
      @saved_env.each_key { ENV.delete(it) }
      ENV["HOME"] = @home
      Runsheets.reset_config!
    end

    # Remove whatever a test set and bring the original environment back.
    def restore_home!
      ENV.keys.grep(/\ARUNSHEETS_/).each { ENV.delete(it) }
      @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      Runsheets.reset_config!
      FileUtils.rm_rf(@home)
    end

    # Run the CLI on +argv+ with captured output.
    def run_cli(*argv)
      out = StringIO.new
      err = StringIO.new
      status = Runsheets::CLI.run(argv.flatten, out:, err:)
      CliRun.new(status:, out: out.string, err: err.string)
    end

    # CLI.parse with captured output; returns the options and the text.
    def parse_cli(*argv)
      out = StringIO.new
      [Runsheets::CLI.parse(argv.flatten, out:), out.string]
    end

    # The config the CLI builds from +argv+.
    def cli_config(*argv) = Runsheets::CLI.configure(Runsheets::CLI.parse(argv.flatten))

    # A scratch directory holding +files+ (relative path => text).
    def with_scratch_dir(files = {})
      Dir.mktmpdir("runsheets-cli") do |dir|
        files.each do |rel, text|
          path = File.join(dir, rel)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, text)
        end
        yield dir
      end
    end

    # A one-step manual runbook in a single file, titled +title+.
    def single_manual_runbook(title, step: "Step")
      "---\ntitle: #{title}\n---\n\n## #{step}\n<!-- kind: manual -->\n\nDo it.\n"
    end

    # The status written to a run's run.json.
    def run_json_status(run) = JSON.parse(File.read(File.join(run.dir, "run.json")))["status"]

    # A session whose background clock block is running; yields both.
    def with_running_clock
      with_runs_dir do |root|
        session = open_session(root)
        clock   = session.execute("035-keep-a-clock-running-1")
        wait_for { clock.output.include?("still here") }
        yield session, clock
      end
    end

    # A SessionLog in a scratch dir; yields it and a reader for its file.
    def with_log(**)
      Dir.mktmpdir do |dir|
        log = Runsheets::SessionLog.new(File.join(dir, "session.log"), **)
        yield log, -> { File.read(log.path) }
      ensure
        log&.close
      end
    end

    # The lines of a log file that already held "earlier", after one info.
    def appended_log_lines
      Dir.mktmpdir do |dir|
        path = File.join(dir, "session.log")
        File.write(path, "earlier\n")
        log = Runsheets::SessionLog.new(path)
        log.info("later")
        log.close
        File.read(path).lines
      end
    end

    # A Config.to_config_yaml written to a file in +home+ and read back.
    def reload_config_yaml(home, text)
      file = File.join(home, "saved.yml")
      File.write(file, text)
      Runsheets::Config.new(path: file)
    end
  end
end
