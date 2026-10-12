# frozen_string_literal: true

require "io/console"

module Runsheets
  # Questions at the terminal, for `--new` and `--run`: answers are read
  # from +input+ and prompts written to +output+, so a test or a script
  # piping answers in drives it as a person would.
  #
  # Once input runs out (Ctrl-D, a pipe that ends, stdin from /dev/null)
  # every read gives nil and #exhausted? is true, so a caller can stop
  # asking instead of waiting or looping.
  class Prompt
    def initialize(input: $stdin, output: $stdout)
      @input     = input
      @output    = output
      @exhausted = false
    end

    def exhausted? = @exhausted

    # A line of input, stripped, or nil when input has run out.
    def line = finish(@input.gets)&.strip

    # A secret: read without echo at a terminal, and only its newline
    # removed, since spaces can be part of a password. nil when input has
    # run out.
    def secret
      return finish(@input.gets)&.chomp unless @input.tty?

      text = @input.noecho(&:gets)
      @exhausted = true if text.nil?
      @output.puts # the Enter that noecho did not show
      text&.chomp
    end

    # A yes/no question where no is the default: yes only for an answer
    # starting with y.
    def yes?(question) = answered_yes?(question, "y/N", false)

    # A yes/no question where yes is the default: Enter, or no more input,
    # is yes, and so is an answer starting with y.
    def yes_unless_no?(question) = answered_yes?(question, "Y/n", true)

    private

    def answered_yes?(question, hint, default)
      @output.print "#{question} [#{hint}]: "
      answer = line.to_s.downcase
      answer.empty? ? default : answer.start_with?("y")
    end

    # +text+, as read; nil marks input as run out and ends the prompt's line.
    def finish(text)
      return text unless text.nil?

      @exhausted = true
      @output.puts
      nil
    end
  end
end
