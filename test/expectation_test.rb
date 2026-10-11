# frozen_string_literal: true

require "test_helper"

class TestExpectation < Minitest::Test
  include RunsheetsTest

  Expectation = Runsheets::Expectation

  def test_identical_output_matches_with_trailing_whitespace_ignored
    result = Expectation.compare("one\ntwo\n", "one  \ntwo\n\n")
    assert result.match?
    assert_equal(%w[same same], result.rows.map { it.tag.to_s })
  end

  def test_any_matches_anything_within_one_line
    result = Expectation.compare("in run {{any}}\n{{any}} done", "in run 20261010T221025\nall done")
    assert result.match?
    assert_equal [["in run ", nil], ["{{any}}", "any"]], result.rows.first.expected
    assert_equal [["in run 20261010T221025", nil]], result.rows.first.actual
  end

  def test_any_matches_nothing_but_not_a_second_line
    assert Expectation.compare("a{{any}}b", "ab").match?
    refute Expectation.compare("{{any}}", "one\ntwo").match?
  end

  def test_a_changed_line_marks_the_characters_that_differ
    row = Expectation.compare("in run 20261007T120000", "in run 20261010T221025").rows.first
    assert_equal :changed, row.tag
    assert_equal [["in run 202610", nil], ["07T120000", "diff"]], row.expected
    assert_equal [["in run 202610", nil], ["10T221025", "diff"]], row.actual
  end

  def test_a_changed_line_keeps_its_common_ending
    row = Expectation.compare("Hello, world!", "Hello, web!").rows.first
    assert_equal [["Hello, w", nil], ["orld", "diff"], ["!", nil]], row.expected
    assert_equal [["Hello, w", nil], ["eb", "diff"], ["!", nil]], row.actual
  end

  def test_a_changed_line_with_a_wildcard_is_marked_whole
    row = Expectation.compare("pid {{any}} up", "pid 42 down").rows.first
    assert_equal [["pid ", "diff"], ["{{any}}", "any"], [" up", "diff"]], row.expected
    assert_equal [["pid 42 down", "diff"]], row.actual
  end

  def test_lines_only_one_side_has_get_a_row_with_a_gap
    result = Expectation.compare("a\nb\nc", "a\nc\nd")
    assert_equal(%w[same expected same actual], result.rows.map { it.tag.to_s })
    assert_equal [nil, [%w[b diff]]], [result.rows[1].actual, result.rows[1].expected]
    assert_equal [nil, [%w[d diff]]], [result.rows[3].expected, result.rows[3].actual]
  end

  def test_runs_of_changed_lines_are_paired_off_in_order
    result = Expectation.compare("a\nx\ny\nz", "a\n1\n2")
    assert_equal(%w[same changed changed expected], result.rows.map { it.tag.to_s })
    refute result.match?
  end

  def test_to_h_is_what_the_page_reads
    hash = Expectation.compare("same\nold", "same\nnew").to_h
    refute hash[:match]
    assert_equal({ tag: "same", expected: [["same", nil]], actual: [["same", nil]] }, hash[:rows].first)
  end

  def test_empty_lines_have_no_segments
    row = Expectation.compare("a\n\nb", "a\n\nb").rows[1]
    assert_equal :same, row.tag
    assert_equal [[], []], [row.expected, row.actual]
  end

  def test_for_page_skips_what_has_nothing_to_compare
    assert_nil Expectation.for_page(nil, "out", :finished)
    assert_nil Expectation.for_page("out", "", :running)
    assert_nil Expectation.for_page("out", "", "failed")
    assert Expectation.for_page("out", "out\n", "finished")[:match]
  end

  def test_a_step_finds_the_expect_block_of_an_executable_block
    step = example_runbook.step("010-say-hello")
    assert_includes step.expected_output("010-say-hello-1"), "in run {{any}}"
    assert_nil step.expected_output("010-say-hello-3")
  end
end
