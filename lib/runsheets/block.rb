# frozen_string_literal: true

module Runsheets
  # A fenced code block and the behaviour its info string asks for.
  #
  #   ```bash              display only
  #   ```bash run          Run button
  #   ```bash destructive  Run button behind a typed confirmation (implies run)
  #   ```bash background   Start and Stop buttons; output streams until stopped
  #   ```bash terminal     operator runs it in their own terminal and confirms
  #   ```text expect       expected output of the preceding executable block
  class Block
    KINDS = %i[display run background destructive terminal expect].freeze

    FLAG_KINDS = {
      "run"         => :run,
      "background"  => :background,
      "destructive" => :destructive,
      "terminal"    => :terminal,
      "expect"      => :expect
    }.freeze

    # Kinds the tool spawns a process for.
    EXECUTABLE_KINDS = %i[run destructive background].freeze

    # Languages that can execute and the command that runs a file of them.
    # A runbook can add or override entries in its front matter.
    INTERPRETERS = {
      "bash" => %w[bash],
      "sh"   => %w[sh],
      "zsh"  => %w[zsh],
      "ruby" => %w[ruby]
    }.freeze

    attr_reader :id, :index, :lang, :flags, :code, :line, :kind, :warnings, :interpreters

    # For an :expect block, the id of the executable block it illustrates
    # (the nearest one above it). Set by Renderer once every block is known.
    attr_accessor :expect_for

    # +interpreters+ is the language => command map in force for the
    # runbook (the defaults plus its front matter); a language outside it
    # cannot execute whatever its flags say.
    def initialize(id:, index:, info:, code:, line: nil, interpreters: INTERPRETERS)
      @id           = id
      @index        = index
      @code         = code
      @line         = line
      @interpreters = interpreters
      @lang, *@flags = info.to_s.split
      @lang = @lang.to_s
      @flags.freeze
      @kind, @warnings = Block.classify(@flags, @lang, interpreters)
    end

    # The kind a set of flags asks for, plus any authoring warnings.
    def self.classify(flags, lang, interpreters = INTERPRETERS)
      warnings = []
      unknown  = flags.reject { FLAG_KINDS.key?(it) }
      warnings << "unknown flag#{'s' if unknown.size > 1}: #{unknown.join(', ')}" if unknown.any?

      kinds = flags.filter_map { FLAG_KINDS[it] }.uniq
      kind  = kind_for(kinds)
      warnings << "conflicting flags: #{kinds.join(', ')}; using #{kind}" if conflicting?(kinds, kind)

      if EXECUTABLE_KINDS.include?(kind) && !interpreters.key?(lang)
        warnings << if lang.empty?
                      "a block without a language cannot execute"
                    else
                      "#{lang} blocks cannot execute; displayed only (map it under interpreters in the runbook front matter)"
                    end
      end

      [kind, warnings.freeze]
    end

    # The kind a list of flag kinds asks for, whatever their order:
    # destructive wins, then the first kind other than run, then run.
    def self.kind_for(kinds)
      others = kinds - [:run]
      if others.include?(:destructive) then :destructive
      elsif others.any?                then others.first
      elsif kinds.any?                 then :run
      else                                  :display
      end
    end

    # True when a flag asks for something +kind+ does not do. run beside
    # destructive or background is redundant (both run); run beside
    # terminal or expect is a contradiction.
    def self.conflicting?(kinds, kind)
      (kinds - [:run, kind]).any? || (kinds.include?(:run) && !EXECUTABLE_KINDS.include?(kind))
    end

    def executable?  = EXECUTABLE_KINDS.include?(kind) && interpreters.key?(lang)
    def destructive? = kind == :destructive
    def background?  = kind == :background
    def terminal?    = kind == :terminal
    def expect?      = kind == :expect
    def display?     = kind == :display
    def label        = flags.empty? ? lang : "#{lang} #{flags.join(' ')}"

    # A short fingerprint of what the block says and does. The page sends
    # it back with Run and I ran this, so an edit made after the page loaded
    # cannot turn a click into a different block.
    def digest = Digest::SHA256.hexdigest("#{label}\0#{code}")[0, 16]

    # Terminal blocks are not executed; the operator confirms they ran them.
    def acknowledgeable? = terminal?

    # Names of $VARIABLES the code refers to.
    def referenced_variables = code.scan(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/).flatten.uniq

    def to_h
      { id:, index:, lang:, flags:, kind:, line:, executable: executable?, expect_for:, warnings:, code: }
    end
  end
end
