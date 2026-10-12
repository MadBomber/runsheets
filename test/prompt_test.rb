# frozen_string_literal: true

require "test_helper"

# Questions at the terminal, shared by --new and --run.
class TestPrompt < Minitest::Test
  include RunsheetsTest::StepRunnerFixtures

  # A Prompt reading what is +typed+.
  def prompt(typed = "") = prompt_on(StringIO.new(typed))

  # A Prompt reading +input+, an IO.
  def prompt_on(input)
    @output = StringIO.new
    Runsheets::Prompt.new(input:, output: @output)
  end

  def test_line_is_stripped_and_nil_once_input_runs_out
    asker = prompt("  typed  \n")
    assert_equal "typed", asker.line
    refute asker.exhausted?
    assert_nil asker.line
    assert asker.exhausted?
    assert_equal "\n", @output.string, "the prompt's line is ended at the end of input"
  end

  def test_secret_at_a_terminal_is_read_without_echo_and_keeps_its_spaces
    tty = FakeTty.new(" pass word \n")
    assert_equal " pass word ", prompt_on(tty).secret
    assert tty.noecho_used
    assert_equal "\n", @output.string
  end

  def test_secret_from_a_pipe_is_read_as_is
    asker = prompt(" s3cret\n")
    assert_equal " s3cret", asker.secret
    assert_empty @output.string, "no newline is added for input that was echoed"
  end

  def test_secret_at_the_end_of_input_is_nil
    asker = prompt_on(FakeTty.new(""))
    assert_nil asker.secret
    assert asker.exhausted?
  end

  def test_yes_is_no_for_enter_and_yes_for_an_answer_starting_with_y
    asker = prompt("\nYes\n")
    refute asker.yes?("Go?")
    assert asker.yes?("Go?")
    assert_equal "Go? [y/N]: Go? [y/N]: ", @output.string
  end

  def test_yes_unless_no_is_yes_for_enter_or_no_more_input
    asker = prompt("\n")
    assert asker.yes_unless_no?("Go?")
    assert asker.yes_unless_no?("Go?")
    assert_equal "Go? [Y/n]: Go? [Y/n]: \n", @output.string, "the end of input ends the prompt's line"
  end

  def test_yes_unless_no_is_no_for_an_answer_not_starting_with_y
    asker = prompt("no\nmaybe\n")
    refute asker.yes_unless_no?("Go?")
    refute asker.yes_unless_no?("Go?"), "only an answer starting with y is yes"
  end
end
