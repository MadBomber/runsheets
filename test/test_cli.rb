# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestCLI < Minitest::Test
  include RunsheetsTest

  CLI = Runsheets::CLI

  def test_parse_defaults_and_dir
    options = CLI.parse([RunsheetsTest::EXAMPLE_DIR])
    assert_equal 4567, options[:port]
    assert_equal "127.0.0.1", options[:bind]
    assert_equal RunsheetsTest::EXAMPLE_DIR, options[:dir]
  end

  def test_parse_options
    options = CLI.parse(%w[-p 9000 -b 0.0.0.0 --runs-dir /tmp/r --open --check x])
    assert_equal 9000, options[:port]
    assert_equal "0.0.0.0", options[:bind]
    assert_equal "/tmp/r", options[:runs_dir]
    assert options[:open]
    assert options[:check]
  end

  def test_parse_errors
    assert_raises(OptionParser::ParseError) { CLI.parse([]) }
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[a b]) }
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[--bogus a]) }
  end

  def test_help_and_version_return_nil
    out = StringIO.new
    assert_nil CLI.parse(%w[--help], out:)
    assert_includes out.string, "Usage:"
    out = StringIO.new
    assert_nil CLI.parse(%w[--version], out:)
    assert_includes out.string, Runsheets::VERSION
  end

  def test_check_mode
    out = StringIO.new
    err = StringIO.new
    assert_equal 0, CLI.run(["--check", RunsheetsTest::EXAMPLE_DIR], out:, err:)
    assert_includes out.string, "5 steps, 0 warnings"
    assert_empty err.string
  end

  def test_check_mode_reports_warnings_and_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "runbook.md"), "no front matter\n")
      out = StringIO.new
      err = StringIO.new
      assert_equal 1, CLI.run(["--check", dir], out:, err:)
      assert_includes err.string, "warning: no steps found"
    end
  end

  def test_missing_runbook_is_an_error
    err = StringIO.new
    assert_equal 1, CLI.run(["--check", "/nonexistent/dir"], out: StringIO.new, err:)
    assert_includes err.string, "not a directory"
  end
end
