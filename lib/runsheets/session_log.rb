# frozen_string_literal: true

require "logger"

module Runsheets
  # The session's log: a plain text file appended as things happen, and
  # the same lines echoed to the terminal that started runsheets. Each line
  # is a timestamp, a Rails log level, the tags saying where it happened,
  # and the event:
  #
  #   2026-10-10 14:02:41.200 INFO  [db-maintenance 010-check #1a2b] execute sql via psql -f …
  #   2026-10-10 14:02:41.540 INFO  [#1a2b] >  database | role
  #
  # Two standard Loggers sit behind it, one per destination, each with its
  # own level. Multi-line text becomes one line per source line with the
  # same prefix, so every line stands alone under grep.
  class SessionLog
    LEVELS = %w[debug info warn error fatal].freeze

    # Turns a stream of output chunks into log lines, one per complete line
    # of output, each marked "> ". Whatever is left without a newline is
    # written when the stream closes. Thread-safe enough for one writer (the
    # executor's pump) and one closer.
    class OutputStream
      def initialize(log, tags)
        @log     = log
        @tags    = tags
        @pending = +""
      end

      def write(chunk)
        @pending << chunk.to_s.dup.force_encoding("UTF-8").scrub
        lines    = @pending.split("\n", -1)
        @pending = lines.pop || +""
        lines.each { @log.info("> #{it.chomp("\r")}", tags: @tags) }
        chunk.to_s.bytesize
      end

      def close
        @log.info("> #{@pending}", tags: @tags) unless @pending.empty?
        @pending = +""
      end
    end

    attr_reader :path, :level

    # +path+ is the log file, opened for appending (and created). +echo+ is
    # an IO for the terminal copy, or nil for none. +level+ and
    # +echo_level+ are the floors for each, as level names.
    def initialize(path, level: "info", echo: nil, echo_level: "info")
      @path   = path
      @level  = SessionLog.level_name(level)
      @io     = File.open(path, "a")
      @io.sync = true
      @file   = Logger.new(@io, level: @level, formatter: method(:format))
      @echo   = echo && Logger.new(echo, level: SessionLog.level_name(echo_level), formatter: method(:format))
    end

    # A level name, checked: one of LEVELS. Raises ConfigError otherwise.
    def self.level_name(value)
      name = value.to_s.strip.downcase
      raise ConfigError, "log level must be one of #{LEVELS.join(', ')}, got #{value.inspect}" unless LEVELS.include?(name)

      name
    end

    # The bracketed prefix for a list of tags: [a b #c], or [] dropped.
    def self.tag_text(tags)
      words = Array(tags).compact.map(&:to_s).reject(&:empty?)
      words.empty? ? "" : "[#{words.join(' ')}]"
    end

    # One log line as written: time to the millisecond, level, tags, text.
    def self.line(time, severity, tags, text)
      prefix = [time.strftime("%Y-%m-%d %H:%M:%S.%L"), severity.ljust(5), tag_text(tags)].reject(&:empty?).join(" ")
      "#{prefix} #{text}\n"
    end

    LEVELS.each do |name|
      define_method(name) { |text, tags: []| add(name, text, tags:) }
    end

    # Write +text+ at +severity+, one log line per line of text.
    def add(severity, text, tags: [])
      level = Logger::Severity.const_get(severity.to_s.upcase)
      lines = text.to_s.split("\n")
      lines = [""] if lines.empty?
      lines.each do |line|
        @file.add(level, line, tags)
        @echo&.add(level, line, tags)
      end
      self
    end

    # A sink for one execution's output (see OutputStream).
    def output_stream(tags) = OutputStream.new(self, tags)

    def close
      @io.close unless @io.closed?
      self
    end

    private

    # Logger's formatter: the tags travel as the progname.
    def format(severity, time, tags, text) = SessionLog.line(time, severity, tags, text)
  end
end
