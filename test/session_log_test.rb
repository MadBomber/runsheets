# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestSessionLog < Minitest::Test
  include RunsheetsTest::CliFixtures

  SessionLog = Runsheets::SessionLog

  def test_a_line_is_time_level_tags_and_text
    time = Time.new(2026, 10, 10, 14, 2, 41.2)
    assert_equal "2026-10-10 14:02:41.200 INFO  [hello 010-a #1a2b] execute\n", SessionLog.line(time, "INFO", %w[hello 010-a #1a2b], "execute")
    assert_equal "2026-10-10 14:02:41.200 WARN  odd\n", SessionLog.line(time, "WARN", [], "odd")
    assert_equal "[a b]", SessionLog.tag_text(["a", nil, "", "b"])
  end

  def test_multi_line_text_becomes_one_line_each_with_the_same_prefix
    with_log do |log, text|
      log.info("one\ntwo", tags: ["session"])
      lines = text.call.lines
      assert_equal 2, lines.size
      assert_includes lines.first, "INFO  [session] one"
      assert_includes lines.last, "INFO  [session] two"
    end
  end

  def test_the_file_and_the_echo_have_their_own_levels
    echo = StringIO.new
    with_log(level: "debug", echo:, echo_level: "info") do |log, text|
      log.debug("page view")
      log.warn("exit 1")
      assert_includes text.call, "DEBUG page view"
      refute_includes echo.string, "page view", "debug stays out of the terminal"
      assert_includes echo.string, "WARN  exit 1"
    end
  end

  def test_level_floor_on_the_file
    with_log(level: "warn") do |log, text|
      log.info("routine")
      log.error("broken")
      refute_includes text.call, "routine"
      assert_includes text.call, "ERROR broken"
    end
  end

  def test_level_names_are_checked
    assert_equal "debug", SessionLog.level_name(" DEBUG ")
    assert_raises(Runsheets::ConfigError) { SessionLog.level_name("chatty") }
  end

  def test_output_stream_writes_only_complete_lines_until_closed
    with_log do |log, text|
      stream = log.output_stream(["#ab12"])
      stream.write("first li")
      stream.write("ne\nsecond\r\nlast bit")
      lines = text.call.lines
      assert_equal 2, lines.size, "only complete lines so far"
      assert_includes lines.last, "[#ab12] > second"
    end
  end

  def test_output_stream_writes_the_rest_on_close
    with_log do |log, text|
      stream = log.output_stream(["#ab12"])
      stream.write("first li")
      stream.write("ne\nsecond\r\nlast bit")
      stream.close
      lines = text.call.lines
      assert_equal(["> first line", "> second", "> last bit"], lines.map { it.split("] ", 2).last.chomp })
      assert_includes lines.first, "[#ab12] "
    end
  end

  def test_appends_to_an_existing_file_without_a_header
    lines = appended_log_lines
    assert_equal "earlier\n", lines.first
    assert_equal 2, lines.size
  end
end
