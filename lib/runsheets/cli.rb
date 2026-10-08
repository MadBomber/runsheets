# frozen_string_literal: true

require "optparse"

module Runsheets
  # The `runsheet` command: load a runbook directory and serve it.
  module CLI
    PROGRAM  = "runsheet"
    DEFAULTS = { port: 4567, bind: "127.0.0.1", runs_dir: nil, open: false, check: false }.freeze

    # Parse argv into an options hash. Raises OptionParser::ParseError on bad
    # input; returns nil after printing help or the version.
    def self.parse(argv, defaults = DEFAULTS, out: $stdout)
      options = defaults.dup
      parser  = OptionParser.new do |opts|
        opts.banner = <<~BANNER
          #{PROGRAM} #{VERSION} - executable runbooks in your browser

          Usage: #{PROGRAM} [options] RUNBOOK_DIR

          RUNBOOK_DIR holds runbook.md and a steps/ directory of markdown files.
          Fenced blocks marked `bash run` or `ruby run` get a Run button; every
          execution is recorded under #{Runsheets.runs_dir}

          Options:
        BANNER

        opts.on("-p", "--port PORT", Integer, "Port to listen on (default: #{defaults[:port]})") { options[:port] = it }
        opts.on("-b", "--bind HOST", "Address to bind to (default: #{defaults[:bind]})") { options[:bind] = it }
        opts.on("--runs-dir DIR", "Where run records are written (default: #{Runsheets.runs_dir})") { options[:runs_dir] = it }
        opts.on("-o", "--open", "Open the browser once the server is up") { options[:open] = true }
        opts.on("-c", "--check", "Load the runbook, report authoring warnings, and exit") { options[:check] = true }
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
      raise OptionParser::ParseError, "RUNBOOK_DIR is required" if rest.empty?

      options[:dir] = File.expand_path(rest.first)
      options
    end

    # Entry point for the executable. Returns the process exit status.
    def self.run(argv, out: $stdout, err: $stderr)
      options = parse(argv, out:)
      return 0 unless options

      Runsheets.runs_dir = options[:runs_dir] if options[:runs_dir]
      runbook = Runbook.load(options[:dir])
      runbook.warnings.each { err.puts "#{PROGRAM}: warning: #{it}" }

      if options[:check]
        out.puts "#{runbook.title}: #{runbook.steps.size} steps, #{runbook.warnings.size} warnings"
        return runbook.warnings.empty? ? 0 : 1
      end

      serve(runbook, options, out:)
      0
    rescue Errno::EADDRINUSE
      err.puts "#{PROGRAM}: port #{options[:port]} on #{options[:bind]} is already in use; pick another with --port"
      1
    rescue OptionParser::ParseError, RunbookError => e
      err.puts "#{PROGRAM}: #{e.message}"
      1
    end

    def self.serve(runbook, options, out: $stdout)
      session = Session.new(runbook:)
      Web.configure_for(session, bind: options[:bind], port: options[:port])
      url = "http://#{options[:bind]}:#{options[:port]}/"

      out.puts <<~INFO
        #{PROGRAM} #{VERSION}
        Runbook: #{runbook.title} (#{runbook.dir})
        Runs:    #{Runsheets.runs_dir}
        Open #{url} in your browser
        Press Ctrl-C to stop
      INFO

      Web.run! do
        open_browser(url) if options[:open]
      end
    end

    def self.open_browser(url)
      command = case RUBY_PLATFORM
                when /darwin/ then ["open", url]
                when /mswin|mingw/ then ["cmd", "/c", "start", url]
                else ["xdg-open", url]
                end
      Process.spawn(*command, [:out, :err] => File::NULL)
    rescue SystemCallError
      nil
    end
  end
end
