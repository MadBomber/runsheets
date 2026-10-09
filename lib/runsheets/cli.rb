# frozen_string_literal: true

require "optparse"
require "fileutils"

module Runsheets
  # The `runsheets` command: load a runbook (a directory or a single markdown
  # file) and serve it, check it, or scaffold a new one.
  #
  # Settings come from Config: bundled defaults, then the config file, then
  # RUNSHEETS_* variables, then whatever is given on the command line.
  module CLI
    PROGRAM = "runsheets"

    # The runbook served when none is named: the bundled hello example,
    # found relative to this file so it works from a checkout and from an
    # installed gem alike.
    DEFAULT_RUNBOOK = File.expand_path("../../examples/hello", __dir__)

    # Parse argv into a hash holding only what was given: Config attribute
    # names for the options, :config for the config file. Raises
    # OptionParser::ParseError on bad input; returns nil after printing help
    # or the version.
    def self.parse(argv, out: $stdout)
      options  = {}
      defaults = Config.bundled_defaults
      parser   = OptionParser.new do |opts|
        opts.banner = <<~BANNER
          #{PROGRAM} #{VERSION} - executable runbooks in your browser

          Usage: #{PROGRAM} [options] [RUNBOOK]

          RUNBOOK is a directory holding runbook.md and a steps/ directory of
          markdown files, a single all-in-one markdown file whose ## headings
          are the steps, or a directory of such runbooks to choose from in the
          browser. Without one, the bundled example is served:
          #{DEFAULT_RUNBOOK}
          Fenced blocks marked `bash run`, `ruby run`, `bash destructive`
          or `bash background` get buttons; every execution is recorded under
          #{defaults[:runs_dir]}

          Settings are layered: the user config #{Config.xdg_path},
          then ./config/runsheets.yml (or the file --config names), then the
          environment variable named beside each option, then the command line,
          which wins. RUNBOOK itself can be set as `dir:` in a config file or
          with RUNSHEETS_DIR. Flags take 1, true, yes or on; --no-open,
          --no-check and --no-init switch a flag off that a lower layer turned on.

          Options:
        BANNER

        opts.on("-c", "--config FILE", "Config file to read in place of ./config/runsheets.yml [RUNSHEETS_CONFIG]") { options[:config] = it }
        opts.on("-p", "--port PORT", Integer, "Port to listen on (default: #{defaults[:port]}) [RUNSHEETS_PORT]") { options[:port] = it }
        opts.on("-b", "--bind HOST", "Address to bind to (default: #{defaults[:bind]}) [RUNSHEETS_BIND]") { options[:bind] = it }
        opts.on("--runs-dir DIR", "Where run records are written (default: #{defaults[:runs_dir]}) [RUNSHEETS_RUNS_DIR]") { options[:runs_dir] = it }
        opts.on("-o", "--[no-]open", "Open the browser once the server is up [RUNSHEETS_OPEN]") { options[:open] = it }
        opts.on("--[no-]check", "Load the runbook, report authoring warnings, and exit [RUNSHEETS_CHECK]") { options[:check] = it }
        opts.on("--[no-]init", "Create a new runbook skeleton at RUNBOOK (a directory, or a .md file) and exit [RUNSHEETS_INIT]") { options[:init] = it }
        opts.on("--[no-]dump", "Print the settings in force as a config file to stdout and exit [RUNSHEETS_DUMP]") { options[:dump] = it }
        opts.on("-v", "--version", "Print the version and exit") do
          out.puts "#{PROGRAM} #{VERSION}"
          return nil
        end
        opts.on("-h", "--help", "Show this help and exit") do
          out.puts opts
          return nil
        end
      end

      rest = parser.parse(argv)
      raise OptionParser::ParseError, "too many arguments: #{rest.join(' ')}" if rest.size > 1

      options[:dir] = rest.first if rest.first
      options
    end

    # Build the effective settings from parsed options and install them as
    # Runsheets.config. The command line beats the environment, which beats
    # the config file, which beats the bundled defaults.
    def self.configure(options)
      Runsheets.configure(options.except(:config), path: options[:config])
    end

    # --dump: print the settings in force as a config file. Redirect it to
    # save them: `runsheets --dump -p 4580 > ~/.config/runsheets/runsheets.yml`.
    def self.dump(config, out: $stdout)
      out.print config.to_config_yaml
      0
    end

    # The runbook a configuration points at: its dir, else the bundled example.
    # --init insists on an explicit one.
    def self.runbook_path(config)
      if config.init && config.dir.nil?
        raise OptionParser::ParseError, "--init needs the path of the runbook to create (RUNBOOK, dir: in the config file, or RUNSHEETS_DIR)"
      end

      config.dir || DEFAULT_RUNBOOK
    end

    # Entry point for the executable. Returns the process exit status.
    def self.run(argv, out: $stdout, err: $stderr)
      options = parse(argv, out:)
      return 0 unless options

      config  = configure(options)
      return dump(config, out:) if config.dump

      path    = runbook_path(config)
      return init(path, out:) if config.init

      target = Library.library?(path) ? Library.load(path) : Runbook.load(path)
      return check(target, out:, err:) if config.check

      serve(target, config, out:, err:)
      0
    rescue Errno::EADDRINUSE
      err.puts "#{PROGRAM}: port #{config.port} on #{config.bind} is already in use; pick another with --port"
      1
    rescue OptionParser::ParseError, RunbookError, ConfigError => e
      err.puts "#{PROGRAM}: #{e.message}"
      1
    end

    # --check: report authoring warnings for a runbook, or for every runbook
    # in a library, one line each. Exit 1 when anything warned or failed.
    def self.check(target, out: $stdout, err: $stderr)
      runbooks = target.is_a?(Library) ? target.entries.map { check_entry(it, err:) } : [target]
      runbooks.compact.each do |runbook|
        runbook.warnings.each { err.puts "#{PROGRAM}: warning: #{runbook.slug}: #{it}" } if target.is_a?(Library)
        runbook.warnings.each { err.puts "#{PROGRAM}: warning: #{it}" } unless target.is_a?(Library)
        out.puts "#{runbook.title}: #{runbook.steps.size} steps, #{runbook.warnings.size} warnings"
      end
      clean = runbooks.all? { it && it.warnings.empty? }
      clean ? 0 : 1
    end

    # One library entry's runbook, or nil (and a message) when it does not load.
    def self.check_entry(entry, err: $stderr)
      return Runbook.load(entry.path) if entry.ok?

      err.puts "#{PROGRAM}: error: #{entry.slug}: #{entry.error}"
      nil
    end

    # Serve a runbook, or a library of them (the operator chooses in the browser).
    def self.serve(target, config, out: $stdout, err: $stderr)
      bind = config.bind
      port = config.port
      library = target.is_a?(Library) ? target : nil
      session = library ? nil : Session.new(runbook: target)
      Web.configure_for(session, bind:, port:, library:)
      url = "http://#{bind}:#{port}/"
      err.puts bind_warning(bind) unless Web.loopback?(bind)

      out.puts <<~INFO
        #{PROGRAM} #{VERSION}
        #{target_line(target)}
        Runs:    #{Runsheets.runs_dir}
        Config:  #{config.files.empty? ? 'none (defaults)' : config.files.join(', ')}
        Open #{url} in your browser
        Press Ctrl-C to stop
      INFO

      Web.run! do
        open_browser(url) if config.open
      end
    ensure
      shutdown(Web.session, out:) if Web.session
    end

    def self.target_line(target)
      if target.is_a?(Library)
        folders = target.folders.size
        where   = folders.positive? ? " in #{folders} folder#{'s' unless folders == 1}" : ""
        "Library: #{target.size} runbook#{'s' unless target.size == 1}#{where} under #{target.dir}"
      else
        "Runbook: #{target.title} (#{target.single_file? ? target.main_path : target.dir})"
      end
    end

    # When the server stops (Ctrl-C, or an error), end the active run as
    # abandoned so nothing it started is left running and its record does
    # not stay "running" forever.
    def self.shutdown(session, out: $stdout)
      return unless session.active?

      run = session.run
      session.abandon_if_active
      out.puts "#{PROGRAM}: abandoned run #{run.id}; stopped what it left running"
    end

    def self.bind_warning(bind)
      <<~WARN.chomp
        #{PROGRAM}: warning: binding to #{bind}, which is not a loopback address.
        Anyone who can reach this address and guess the session token can run blocks as you.
        #{Web.wildcard?(bind) ? 'The Host header check is off for a wildcard bind.' : 'Only requests with this address in the Host header are accepted.'}
      WARN
    end

    def self.open_browser(url)
      command = case RUBY_PLATFORM
                when /darwin/ then ["open", url]
                when /mswin|mingw/ then ["cmd", "/c", "start", url]
                else ["xdg-open", url]
                end
      Process.spawn(*command, %i[out err] => File::NULL)
    rescue SystemCallError
      nil
    end

    # --- scaffolding -------------------------------------------------------

    # Write a starter runbook. A path ending in .md gets the single-file
    # shape; anything else becomes a directory. Refuses to touch an existing
    # file or a non-empty directory. Returns the exit status.
    def self.init(path, out: $stdout)
      files = scaffold(path)
      raise RunbookError, "#{path} already exists" if File.file?(path)
      raise RunbookError, "#{path} exists and is not empty" if File.directory?(path) && !Dir.empty?(path)

      files.each do |rel, text|
        full = rel.start_with?("/") ? rel : File.join(path, rel)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, text)
        out.puts "created #{full}"
      end
      out.puts "Next: #{PROGRAM} --check #{path}"
      0
    end

    # The files a new runbook starts with, keyed by path. For a single-file
    # runbook the one key is the absolute path itself.
    def self.scaffold(path)
      name  = File.basename(path, ".*")
      title = name.tr("-_", " ").capitalize
      if path.end_with?(".md")
        { path => single_file_template(title) }
      else
        {
          "runbook.md" => runbook_template(title),
          "steps/010-first-step.md" => <<~MD,
            ---
            title: First step
            kind: automated
            timeout: 300
            ---

            Say what this step does and why it is here. Then the command:

            ```bash run
            echo "hello from #{name}"
            ```

            How to tell it worked:

            ```text expect
            hello from #{name}
            ```
          MD
          "steps/020-a-manual-step.md" => <<~MD,
            ---
            title: A manual step
            kind: manual
            ---

            An instruction the operator carries out and then acknowledges.
          MD
          "verify.md" => <<~MD,
            ---
            title: Verify
            kind: verify
            ---

            Whole-procedure checks. These should pass after every run.

            ```bash run
            test -n "$EXAMPLE_INPUT" && echo "EXAMPLE_INPUT is set"
            ```
          MD
          "rollback.md" => <<~MD
            ---
            title: Rollback
            ---

            What to do when it fails partway. This panel sits in the sidebar of
            every step.
          MD
        }
      end
    end

    def self.runbook_template(title)
      <<~MD
        ---
        title: #{title}
        when_to_use: >
          One or two sentences on the situation this runbook is for.
        prerequisites:
          - What must be true or installed before starting
        escalation: Who to call when a step fails
        tags: []
        inputs:
          - name: EXAMPLE_INPUT
            prompt: An example input, exported as $EXAMPLE_INPUT
            default: example
        ---

        # #{title}

        Everything above the first step is the preamble: what this procedure does,
        what it touches, and what the operator should know before starting.
      MD
    end

    def self.single_file_template(title)
      <<~MD
        ---
        title: #{title}
        when_to_use: >
          One or two sentences on the situation this runbook is for.
        prerequisites:
          - What must be true or installed before starting
        escalation: Who to call when a step fails
        inputs:
          - name: EXAMPLE_INPUT
            prompt: An example input, exported as $EXAMPLE_INPUT
            default: example
        ---

        # #{title}

        Everything above the first `##` heading is the preamble. Each `##` heading
        below is a step. Step attributes go in an HTML comment right after the
        heading.

        ## First step
        <!-- kind: automated, timeout: 300 -->

        Say what this step does and why it is here. Then the command:

        ```bash run
        echo "hello from $EXAMPLE_INPUT"
        ```

        ## A manual step
        <!-- kind: manual -->

        An instruction the operator carries out and then acknowledges.

        ## Verify

        Whole-procedure checks. A section headed Verify plays the part of verify.md.

        ```bash run
        test -n "$EXAMPLE_INPUT" && echo "EXAMPLE_INPUT is set"
        ```

        ## Rollback

        What to do when it fails partway. A section headed Rollback sits in the
        sidebar of every step.
      MD
    end
  end
end
