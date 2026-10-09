# frozen_string_literal: true

require "optparse"
require "fileutils"

module Runsheets
  # The `runsheet` command: load a runbook (a directory or a single markdown
  # file) and serve it, check it, or scaffold a new one.
  module CLI
    PROGRAM  = "runsheet"
    DEFAULTS = { port: 4567, bind: "127.0.0.1", runs_dir: nil, open: false, check: false, init: false }.freeze

    # Parse argv into an options hash. Raises OptionParser::ParseError on bad
    # input; returns nil after printing help or the version.
    def self.parse(argv, defaults = DEFAULTS, out: $stdout)
      options = defaults.dup
      parser  = OptionParser.new do |opts|
        opts.banner = <<~BANNER
          #{PROGRAM} #{VERSION} - executable runbooks in your browser

          Usage: #{PROGRAM} [options] RUNBOOK

          RUNBOOK is a directory holding runbook.md and a steps/ directory of
          markdown files, or a single markdown file whose ## headings are the
          steps. Fenced blocks marked `bash run`, `ruby run`, `bash destructive`
          or `bash background` get buttons; every execution is recorded under
          #{Runsheets.runs_dir}

          Options:
        BANNER

        opts.on("-p", "--port PORT", Integer, "Port to listen on (default: #{defaults[:port]})") { options[:port] = it }
        opts.on("-b", "--bind HOST", "Address to bind to (default: #{defaults[:bind]})") { options[:bind] = it }
        opts.on("--runs-dir DIR", "Where run records are written (default: #{Runsheets.runs_dir})") { options[:runs_dir] = it }
        opts.on("-o", "--open", "Open the browser once the server is up") { options[:open] = true }
        opts.on("-c", "--check", "Load the runbook, report authoring warnings, and exit") { options[:check] = true }
        opts.on("--init", "Create a new runbook skeleton at RUNBOOK (a directory, or a .md file) and exit") { options[:init] = true }
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
      raise OptionParser::ParseError, "RUNBOOK is required" if rest.empty?

      options[:runbook] = File.expand_path(rest.first)
      options
    end

    # Entry point for the executable. Returns the process exit status.
    def self.run(argv, out: $stdout, err: $stderr)
      options = parse(argv, out:)
      return 0 unless options

      Runsheets.runs_dir = options[:runs_dir] if options[:runs_dir]
      return init(options[:runbook], out:) if options[:init]

      runbook = Runbook.load(options[:runbook])
      runbook.warnings.each { err.puts "#{PROGRAM}: warning: #{it}" }

      if options[:check]
        out.puts "#{runbook.title}: #{runbook.steps.size} steps, #{runbook.warnings.size} warnings"
        return runbook.warnings.empty? ? 0 : 1
      end

      serve(runbook, options, out:, err:)
      0
    rescue Errno::EADDRINUSE
      err.puts "#{PROGRAM}: port #{options[:port]} on #{options[:bind]} is already in use; pick another with --port"
      1
    rescue OptionParser::ParseError, RunbookError => e
      err.puts "#{PROGRAM}: #{e.message}"
      1
    end

    def self.serve(runbook, options, out: $stdout, err: $stderr)
      bind, port = options.values_at(:bind, :port)
      session = Session.new(runbook:)
      Web.configure_for(session, bind:, port:)
      url = "http://#{bind}:#{port}/"
      err.puts bind_warning(bind) unless Web.loopback?(bind)

      out.puts <<~INFO
        #{PROGRAM} #{VERSION}
        Runbook: #{runbook.title} (#{runbook.single_file? ? runbook.main_path : runbook.dir})
        Runs:    #{Runsheets.runs_dir}
        Open #{url} in your browser
        Press Ctrl-C to stop
      INFO

      Web.run! do
        open_browser(url) if options[:open]
      end
    ensure
      shutdown(session, out:) if session
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
