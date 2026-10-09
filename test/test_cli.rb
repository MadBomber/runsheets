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
    assert_equal RunsheetsTest::EXAMPLE_DIR, options[:runbook]
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
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[a b]) }
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[--bogus a]) }
    error = assert_raises(OptionParser::ParseError) { CLI.parse(%w[--init]) }
    assert_match(/--init needs the path/, error.message)
  end

  def test_no_runbook_means_the_bundled_example
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI::DEFAULT_RUNBOOK
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.parse([])[:runbook]
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.parse(%w[--check])[:runbook]
    out = StringIO.new
    assert_equal 0, CLI.run(["--check"], out:, err: StringIO.new)
    assert_includes out.string, "Hello, runsheets: 6 steps, 0 warnings"
  end

  def test_help_and_version_return_nil
    out = StringIO.new
    assert_nil CLI.parse(%w[--help], out:)
    assert_includes out.string, "Usage:"
    out = StringIO.new
    assert_nil CLI.parse(%w[--version], out:)
    assert_includes out.string, Runsheets::VERSION
  end

  def test_init_scaffolds_a_directory_runbook_that_checks_clean
    Dir.mktmpdir("runsheets-init") do |dir|
      target = File.join(dir, "new-runbook")
      out = StringIO.new
      assert_equal 0, CLI.run(["--init", target], out:, err: StringIO.new)
      assert_includes out.string, "created #{File.join(target, 'runbook.md')}"
      assert File.file?(File.join(target, "steps", "010-first-step.md"))
      assert File.file?(File.join(target, "verify.md"))
      assert File.file?(File.join(target, "rollback.md"))
      err = StringIO.new
      assert_equal 0, CLI.run(["--check", target], out: StringIO.new, err:), err.string
      assert_equal "New runbook", Runsheets::Runbook.load(target).title

      err = StringIO.new
      assert_equal 1, CLI.run(["--init", target], out: StringIO.new, err:)
      assert_match(/not empty/, err.string)
    end
  end

  def test_init_scaffolds_a_single_file_runbook_that_checks_clean
    Dir.mktmpdir("runsheets-init") do |dir|
      target = File.join(dir, "db-refresh.md")
      assert_equal 0, CLI.run(["--init", target], out: StringIO.new, err: StringIO.new)
      assert File.file?(target)
      err = StringIO.new
      assert_equal 0, CLI.run(["--check", target], out: StringIO.new, err:), err.string
      rb = Runsheets::Runbook.load(target)
      assert rb.single_file?
      assert_equal "Db refresh", rb.title
      assert_equal 2, rb.steps.size
      assert rb.verify
      assert rb.rollback
      err = StringIO.new
      assert_equal 1, CLI.run(["--init", target], out: StringIO.new, err:)
      assert_match(/already exists/, err.string)
    end
  end

  def test_check_accepts_a_single_file
    out = StringIO.new
    assert_equal 0, CLI.run(["--check", File.expand_path("../examples/db-maintenance.md", __dir__)], out:, err: StringIO.new)
    assert_includes out.string, "0 warnings"
  end

  def test_check_mode
    out = StringIO.new
    err = StringIO.new
    assert_equal 0, CLI.run(["--check", RunsheetsTest::EXAMPLE_DIR], out:, err:)
    assert_includes out.string, "6 steps, 0 warnings"
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
    assert_includes err.string, "no such runbook"
  end

  def test_shutdown_abandons_the_active_run_and_stops_its_processes
    with_runs_dir do |root|
      s = Runsheets::Session.new(runbook: example_runbook, runs_root: root)
      out = StringIO.new
      CLI.shutdown(s, out:)
      assert_empty out.string, "nothing to do without a run"

      s.start_run
      bg = s.execute("035-keep-a-clock-running-1")
      wait_for { bg.output.include?("still here") }
      CLI.shutdown(s, out:)
      refute s.active?
      assert bg.stopped?
      assert_equal "abandoned", JSON.parse(File.read(File.join(s.run.dir, "run.json")))["status"]
      assert_includes out.string, "abandoned run #{s.run.id}"
    end
  end

  def test_bind_warning_mentions_the_host_check
    assert_includes CLI.bind_warning("0.0.0.0"), "Host header check is off"
    assert_includes CLI.bind_warning("192.168.1.5"), "Only requests with this address"
  end
end
