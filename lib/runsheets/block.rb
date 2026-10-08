# frozen_string_literal: true

module Runsheets
  # A fenced code block and the behaviour its info string asks for.
  #
  #   ```bash              display only
  #   ```bash run          Run button
  #   ```bash destructive  Run button behind a confirmation (implies run)
  #   ```bash background   start/stop (not executable yet)
  #   ```bash terminal     operator runs it in their own terminal
  #   ```text expect       expected output, never executed
  class Block
    KINDS = %i[display run background destructive terminal expect].freeze

    FLAG_KINDS = {
      "run"         => :run,
      "background"  => :background,
      "destructive" => :destructive,
      "terminal"    => :terminal,
      "expect"      => :expect
    }.freeze

    # Kinds the tool executes today. :background joins once streaming
    # processes land.
    EXECUTABLE_KINDS = %i[run destructive].freeze

    # Languages that can execute and the command that runs a file of them.
    # A runbook can add or override entries in its front matter.
    INTERPRETERS = {
      "bash" => %w[bash],
      "sh"   => %w[sh],
      "zsh"  => %w[zsh],
      "ruby" => %w[ruby]
    }.freeze

    attr_reader :id, :index, :lang, :flags, :code, :line, :kind, :warnings

    def initialize(id:, index:, info:, code:, line: nil)
      @id    = id
      @index = index
      @code  = code
      @line  = line
      @lang, *@flags = info.to_s.split
      @lang = @lang.to_s
      @flags.freeze
      @kind, @warnings = Block.classify(@flags, @lang)
    end

    # The kind a set of flags asks for, plus any authoring warnings.
    def self.classify(flags, lang)
      warnings = []
      unknown  = flags.reject { FLAG_KINDS.key?(it) }
      warnings << "unknown flag#{'s' if unknown.size > 1}: #{unknown.join(', ')}" if unknown.any?

      kinds = flags.filter_map { FLAG_KINDS[it] }.uniq
      kind  = if kinds.include?(:destructive) then :destructive
              elsif kinds.empty?              then :display
              else                                 kinds.first
              end

      extra = kinds - [:run, kind]
      warnings << "conflicting flags: #{kinds.join(', ')}; using #{kind}" if extra.any?

      if %i[run destructive background].include?(kind) && !INTERPRETERS.key?(lang)
        warnings << (lang.empty? ? "a block without a language cannot execute" : "#{lang} blocks cannot execute; displayed only")
      end

      [kind, warnings.freeze]
    end

    def executable?  = EXECUTABLE_KINDS.include?(kind) && INTERPRETERS.key?(lang)
    def destructive? = kind == :destructive
    def display?     = kind == :display
    def label        = flags.empty? ? lang : "#{lang} #{flags.join(' ')}"

    # Names of $VARIABLES the code refers to.
    def referenced_variables = code.scan(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/).flatten.uniq

    def to_h
      { id:, index:, lang:, flags:, kind:, line:, executable: executable?, warnings:, code: }
    end
  end
end
