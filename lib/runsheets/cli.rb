# frozen_string_literal: true

require "optparse"
require "fileutils"
require "socket"

module Runsheets
  # The `runsheets` command: load a runbook (a directory or a single markdown
  # file) and serve it or check it; or ask some questions and write a new one.
  #
  # Settings come from Config: bundled defaults, then the config file, then
  # RUNSHEETS_* variables, then whatever is given on the command line.
  module CLI
    PROGRAM = "runsheets"

    # The runbook served when none is named: the bundled hello example,
    # found relative to this file so it works from a checkout and from an
    # installed gem alike.
    DEFAULT_RUNBOOK = File.expand_path("../../examples/directory_based_runbooks/hello", __dir__)

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
                 #{PROGRAM} --new [DIR]
                 #{PROGRAM} --run [STEP] --engineer NAME --why TEXT [RUNBOOK]

          RUNBOOK is a directory holding runbook.md and a steps/ directory of
          markdown files, a single all-in-one markdown file whose ## headings
          are the steps, or a directory of such runbooks to choose from in the
          browser. Without one, the bundled example is served:
          #{DEFAULT_RUNBOOK}
          Fenced blocks marked `bash run`, `ruby run`, `bash destructive`
          or `bash background` get buttons. Everything from start to Ctrl-C is
          one session, recorded with its log under #{defaults[:runs_dir]}

          Settings are layered: the user config #{Config.xdg_path},
          then ./config/runsheets.yml (or the file --config names), then the
          environment variable named beside each option, then the command line,
          which wins. RUNBOOK itself can be set as `dir:` in a config file or
          with RUNSHEETS_DIR. Flags take 1, true, yes or on; --no-open and
          --no-check switch a flag off that a lower layer turned on.

          Options:
        BANNER

        server_options(opts, options, defaults)
        session_flags(opts, options, defaults)
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
      raise OptionParser::ParseError, "--new takes the directory to create the runbook in; give no RUNBOOK with it" if options.key?(:new) && rest.any?
      raise OptionParser::ParseError, "--run and --new cannot be used together" if options.key?(:new) && options.key?(:run)

      rest = runbook_taken_by_run(options, rest)
      options[:dir] = rest.first if rest.first
      options
    end

    # --run's step is optional, so in `--run ops/db-refresh` it takes the
    # runbook as the step. A value with a / or ending in .md is no step
    # name: when nothing else was given as RUNBOOK it is moved there, and
    # the step is asked for. Returns the arguments left over.
    def self.runbook_taken_by_run(options, rest)
      value = options[:run]
      return rest unless rest.empty? && value && (value.include?("/") || value.end_with?(".md"))

      options[:run] = nil
      [value]
    end

    # The options about serving: config file, port, bind, records, and the
    # one-shot actions.
    def self.server_options(opts, options, defaults)
      opts.on("-c", "--config FILE", "Config file to read in place of ./config/runsheets.yml [RUNSHEETS_CONFIG]") { options[:config] = it }
      opts.on("-p", "--port PORT", Integer, "Port to listen on (default: #{defaults[:port]}) [RUNSHEETS_PORT]") { options[:port] = it }
      opts.on("-b", "--bind HOST", "Address to bind to (default: #{defaults[:bind]}) [RUNSHEETS_BIND]") { options[:bind] = it }
      opts.on("--runs-dir DIR", "Where run records are written (default: #{defaults[:runs_dir]}) [RUNSHEETS_RUNS_DIR]") { options[:runs_dir] = it }
      opts.on("-o", "--[no-]open", "Open the browser once the server is up [RUNSHEETS_OPEN]") { options[:open] = it }
      opts.on("--[no-]check", "Load the runbook, report authoring warnings, and exit [RUNSHEETS_CHECK]") { options[:check] = it }
      opts.on("--new [DIR]", "Ask what kind of runbook to make, write it from a template into DIR (asked for when left out), and exit") { options[:new] = it }
      opts.on("--run [STEP]", "Run one step of RUNBOOK (number, name or slug; asked when left out) at the terminal; needs -e and -w") do |step|
        options[:run] = step
      end
      opts.on("--[no-]dump", "Print the settings in force as a config file to stdout and exit [RUNSHEETS_DUMP]") { options[:dump] = it }
    end

    # The options about the session: who, why, and its log.
    def self.session_flags(opts, options, defaults)
      opts.on("-e", "--engineer NAME", "Who is starting the session (default: ask) [RUNSHEETS_ENGINEER]") { options[:engineer] = it }
      opts.on("-w", "--why TEXT", "Why: the session's first note; with --engineer, skips the start page [RUNSHEETS_WHY]") { options[:why] = it }
      opts.on("--log-level LEVEL", "Session log level: #{SessionLog::LEVELS.join(', ')} (default: #{defaults[:log_level]}) [RUNSHEETS_LOG_LEVEL]") { options[:log_level] = it }
      opts.on("--verbose", "Log page views, searches and polling too (--log-level debug)") { options[:log_level] = "debug" }
      opts.on("-q", "--[no-]quiet", "Do not echo the session log to the terminal [RUNSHEETS_QUIET]") { options[:quiet] = it }
    end

    # Build the effective settings from parsed options and install them as
    # Runsheets.config. The command line beats the environment, which beats
    # the config file, which beats the bundled defaults.
    def self.configure(options)
      Runsheets.configure(options.except(:config), path: options[:config]).tap { check_bind_source(it) }
    end

    # Refuse a non-loopback bind that only the project config in the
    # current directory asks for: a cloned repository could otherwise open
    # runsheets to the network. --bind, RUNSHEETS_BIND, --config and the
    # user config can still choose one.
    def self.check_bind_source(config)
      bind = config.project_bind
      return if bind.nil? || Web.loopback?(bind)

      raise ConfigError, "#{config.path} sets bind: #{bind}, which is not a loopback address. A project config cannot open " \
                         "runsheets to the network; pass --bind #{bind} (or set RUNSHEETS_BIND) if that is what you want"
    end

    # --dump: print the settings in force as a config file. Redirect it to
    # save them: `runsheets --dump -p 4580 > ~/.config/runsheets/runsheets.yml`.
    def self.dump(config, out: $stdout)
      out.print config.to_config_yaml
      0
    end

    # The RUNBOOK argument as a path. A relative one is found from the
    # current directory, else under +base+: the dir RUNSHEETS_DIR or a
    # config file sets (or the directory of a single-file runbook it
    # names). Raises RunbookError naming both places when neither has it.
    def self.resolve_runbook(arg, base:, cwd: Dir.pwd)
      here = File.expand_path(arg, cwd)
      return here if File.exist?(here) || base.nil? || Pathname.new(arg).absolute? || arg.start_with?("~")

      base  = File.dirname(base) if File.file?(base)
      under = File.expand_path(arg, base)
      return under if File.exist?(under)

      raise RunbookError, "no such runbook: #{here}, nor #{under} under the runbook directory #{base}"
    end

    # The runbook a configuration points at: its dir, else the bundled example.
    def self.runbook_path(config) = config.dir || DEFAULT_RUNBOOK

    # Entry point for the executable. Returns the process exit status.
    # --new reads its answers from +input+.
    def self.run(argv, out: $stdout, err: $stderr, input: $stdin)
      options = parse(argv, out:)
      return 0 unless options
      return new_runbook(options[:new], default: new_parent_default(offline_config(options)), input:, out:) if options.key?(:new)
      options[:dir] = resolve_runbook(options[:dir], base: Config.new(path: options[:config]).dir) if options[:dir]
      return run_step(options[:run], offline_config(options), input:, out:) if options.key?(:run)

      config  = configure(options)
      return dump(config, out:) if config.dump

      path   = runbook_path(config)
      target = Library.library?(path) ? Library.load(path) : Runbook.load(path)
      return check(target, out:, err:) if config.check

      serve(target, config, out:, err:)
      0
    rescue Errno::EADDRINUSE
      err.puts "#{PROGRAM}: port #{config.port} on #{config.bind} is already in use; pick another with --port"
      1
    rescue OptionParser::ParseError, RunbookError, RunError, ConfigError,
           Psych::Exception, SocketError, SystemCallError => e # also a bad config file, an unknown host, an unreadable directory
      err.puts "#{PROGRAM}: #{e.message}"
      1
    end

    # --check: report authoring warnings for a runbook, or for every runbook
    # in a library, one line each. Exit 1 when anything warned or failed.
    def self.check(target, out: $stdout, err: $stderr)
      library  = target.is_a?(Library)
      runbooks = library ? target.entries.map { check_entry(it, err:) } : [target]
      runbooks.compact.each do |runbook|
        runbook.warnings.each { err.puts "#{PROGRAM}: warning: #{"#{runbook.slug}: " if library}#{it}" }
        out.puts "#{runbook.title}#{" [#{runbook.slug}]" if library}: #{runbook.steps.size} steps, #{runbook.warnings.size} warnings"
      end
      clean = runbooks.all? { it && it.warnings.empty? }
      clean ? 0 : 1
    end

    # One library entry's runbook (as the library loaded it, with its slug),
    # or nil and a message when it does not load.
    def self.check_entry(entry, err: $stderr)
      return entry.runbook if entry.ok?

      err.puts "#{PROGRAM}: error: #{entry.slug}: #{entry.error}"
      nil
    end

    # Serve a runbook, or a library of them (the operator chooses in the
    # browser). Everything until the server stops is one session; it starts
    # now when the engineer and why are known, else on the browser's start
    # page.
    def self.serve(target, config, out: $stdout, err: $stderr)
      bind    = config.bind
      port    = config.port
      library = target.is_a?(Library) ? target : nil
      runbook = library ? nil : target
      options = session_options(config, out:)
      session = early_session(config, library:, runbook:, options:)
      Web.configure_for(session, bind:, port:, library:, runbook:).prepare_start(session_options: options, engineer: default_engineer(config))
      url = SessionKey.url(bind, port, Web.settings.rs_token)
      err.puts bind_warning(bind) unless Web.loopback?(bind)
      runbook&.warnings&.each { err.puts "#{PROGRAM}: warning: #{it}" }

      out.puts <<~INFO
        #{PROGRAM} #{VERSION}
        #{target_line(target)}
        Runs:    #{Runsheets.runs_dir}
        Config:  #{config.files.empty? ? 'none (defaults)' : config.files.join(', ')}
        Session: #{session ? "#{session.id}, log #{session.log.path}" : 'starts in the browser (who and why)'}
        Open #{url} in your browser
        Press Ctrl-C to end the session and stop
      INFO

      Web.run! do
        open_browser(url) if config.open
      end
    ensure
      shutdown(Web.session) if Web.session
    end

    # Raise Errno::EADDRINUSE now when +port+ is taken, before a session and
    # its record exist. The server binds the port again a moment later.
    def self.ensure_port_free(bind, port) = TCPServer.new(bind, port).close

    # The session, started now when --engineer and --why say who and why;
    # nil leaves it to the start page. The port is checked first, so a
    # start that cannot serve records no session.
    def self.early_session(config, library:, runbook:, options:)
      ensure_port_free(config.bind, config.port)
      Session.new(engineer: config.engineer, why: config.why, library:, runbook:, **options) if config.engineer && config.why
    end

    # What every session this process starts is built with: where records
    # go, the log level, and the terminal echo (none with --quiet).
    def self.session_options(config, out: $stdout) = { runs_root: Runsheets.runs_dir, log_level: config.log_level, echo: config.quiet ? nil : out }

    # Who the start page suggests: the configured engineer, else git's
    # user.name, else the login name.
    def self.default_engineer(config) = [config.engineer, git_user_name, ENV["USER"]].find { !it.to_s.strip.empty? }

    def self.git_user_name
      IO.popen(%w[git config user.name], err: File::NULL, &:read).strip
    rescue SystemCallError
      nil
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

    # When the server stops (Ctrl-C, End session, or an error), end the
    # session: every run is closed with the status its work earns and
    # nothing it started is left running. Ending twice does nothing.
    def self.shutdown(session) = session.end!("runsheets stopped")

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

    # The settings for --new and --run. Nothing is served, so a project
    # config that binds to the network is no concern.
    def self.offline_config(options) = Runsheets.configure(options.except(:config, :new, :run), path: options[:config])

    # Where --new offers to write when it was given no directory: the dir a
    # config file sets, else $RUNSHEETS_DIR, else nil (no default). A dir
    # naming a single-file runbook offers the directory it is in.
    def self.new_parent_default(config, env: ENV)
      dir = config.file_dir
      dir ||= File.expand_path(env["RUNSHEETS_DIR"].strip) unless Config.blank?(env["RUNSHEETS_DIR"])
      dir && File.file?(dir) ? File.dirname(dir) : dir
    end

    # --new: ask what kind of runbook to make and write it into +dir+; with
    # no dir, ask for that too, offering +default+. Ctrl-C at a question
    # creates nothing. Returns the exit status.
    def self.new_runbook(dir, default: nil, input: $stdin, out: $stdout)
      Wizard.new(dir, input:, output: out, default_parent: default).run
    rescue Interrupt
      out.puts "", "Nothing created."
      130
    end

    # --run: run one step of the configured runbook at the terminal, in a
    # session of its own that ends when the step does. The engineer and why
    # are required, since nobody is at a start page to give them. Ctrl-C
    # stops what is running. Returns the exit status.
    def self.run_step(name, config, input: $stdin, out: $stdout)
      raise ConfigError, "--run needs --engineer and --why: the run is recorded with who ran it and why" unless config.engineer && config.why

      runbook = run_step_runbook(runbook_path(config))
      step    = name ? StepRunner.find_step(runbook, name) : StepRunner.choose_step(runbook, input:, output: out)
      refusal = StepRunner.refusal(step)
      raise RunError, refusal if refusal

      session = Session.new(engineer: config.engineer, why: config.why, runbook:, **session_options(config, out:))
      StepRunner.new(session:, runbook:, step:, input:, output: out).run
    rescue Interrupt
      out.puts "", "Interrupted."
      130
    ensure
      session&.end!("runsheets --run #{step.slug} finished")
    end

    # The runbook at +path+ for --run, which runs a step of one runbook and
    # so cannot be given a library.
    def self.run_step_runbook(path)
      raise RunbookError, "--run needs a runbook, not a library of them: #{path}" if Library.library?(path)

      Runbook.load(path)
    end
  end
end
