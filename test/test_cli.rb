# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestCLI < Minitest::Test
  include RunsheetsTest

  CLI = Runsheets::CLI

  SANDBOXED_ENV = %w[HOME XDG_CONFIG_HOME].freeze

  # Each test gets an empty home and no RUNSHEETS_* variables; whatever a
  # test sets is removed again, and the original environment comes back.
  def setup
    @home = Dir.mktmpdir("runsheets-home")
    @saved_env = (ENV.keys.grep(/\ARUNSHEETS_/) + SANDBOXED_ENV).to_h { [it, ENV.fetch(it, nil)] }
    @saved_env.each_key { ENV.delete(it) }
    ENV["HOME"] = @home
    Runsheets.reset_config!
  end

  def teardown
    ENV.keys.grep(/\ARUNSHEETS_/).each { ENV.delete(it) }
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    Runsheets.reset_config!
    FileUtils.rm_rf(@home)
  end

  def test_parse_returns_only_what_was_given
    assert_equal({ dir: RunsheetsTest::EXAMPLE_DIR }, CLI.parse([RunsheetsTest::EXAMPLE_DIR]))
    assert_empty CLI.parse([])
  end

  def test_parse_options
    options = CLI.parse(%w[-p 9000 -b 0.0.0.0 --runs-dir /tmp/r --open --check -c /tmp/c.yml x])
    assert_equal 9000, options[:port]
    assert_equal "0.0.0.0", options[:bind]
    assert_equal "/tmp/r", options[:runs_dir]
    assert options[:open]
    assert options[:check]
    assert_equal "/tmp/c.yml", options[:config]
    assert_equal "x", options[:dir]
    assert_equal({ open: false, check: false, init: false, dump: false }, CLI.parse(%w[--no-open --no-check --no-init --no-dump]))
  end

  def test_configure_layers_file_then_environment_then_command_line
    file = write_yaml(File.join(@home, "rs.yml"), port: 4580, bind: "0.0.0.0", open: true, dir: "/tmp/from-file")
    ENV["RUNSHEETS_PORT"] = "4590"
    ENV["RUNSHEETS_OPEN"] = "no"

    from_file_and_env = CLI.configure(CLI.parse(["--config", file]))
    assert_equal 4590, from_file_and_env.port
    assert_equal "0.0.0.0", from_file_and_env.bind
    refute from_file_and_env.open
    assert_equal "/tmp/from-file", from_file_and_env.dir
    assert_same from_file_and_env, Runsheets.config

    from_cli = CLI.configure(CLI.parse(["-c", file, "-p", "9000", "--open", "/tmp/from-argv"]))
    assert_equal 9000, from_cli.port
    assert_equal "0.0.0.0", from_cli.bind, "the file still supplies what nothing overrides"
    assert from_cli.open
    assert_equal "/tmp/from-argv", from_cli.dir
  end

  def test_the_xdg_user_config_is_read_by_default
    assert_equal File.join(@home, ".config/runsheets/runsheets.yml"), Runsheets::Config.xdg_path
    write_yaml(Runsheets::Config.xdg_path, dir: RunsheetsTest::EXAMPLE_DIR, check: true)
    out = StringIO.new
    assert_equal 0, CLI.run([], out:, err: StringIO.new)
    assert_includes out.string, "Hello, runsheets: 6 steps, 0 warnings"
  end

  def test_runsheets_dir_stands_in_for_the_runbook_argument
    ENV["RUNSHEETS_DIR"] = RunsheetsTest::EXAMPLE_DIR
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.runbook_path(CLI.configure(CLI.parse([])))
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.runbook_path(CLI.configure(CLI.parse(%w[--init])))
    assert_equal "/tmp/argv", CLI.runbook_path(CLI.configure(CLI.parse(%w[/tmp/argv])))
  end

  def test_init_without_any_runbook_path_is_an_error
    err = StringIO.new
    assert_equal 1, CLI.run(%w[--init], out: StringIO.new, err:)
    assert_match(/--init needs the path/, err.string)
  end

  def test_config_errors_exit_one_with_a_message
    err = StringIO.new
    assert_equal 1, CLI.run(%w[--config /nope.yml --check], out: StringIO.new, err:)
    assert_includes err.string, "runsheets: config file not found: /nope.yml"
    ENV["RUNSHEETS_PORT"] = "abc"
    err = StringIO.new
    assert_equal 1, CLI.run(%w[--check], out: StringIO.new, err:)
    assert_includes err.string, 'runsheets: port must be a whole number, got "abc"'
  end

  def test_parse_errors
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[a b]) }
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[--bogus a]) }
    assert_raises(OptionParser::MissingArgument) { CLI.parse(%w[--config]) }
  end

  def test_no_runbook_means_the_bundled_example
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI::DEFAULT_RUNBOOK
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.runbook_path(CLI.configure(CLI.parse([])))
    out = StringIO.new
    assert_equal 0, CLI.run(["--check"], out:, err: StringIO.new)
    assert_includes out.string, "Hello, runsheets: 6 steps, 0 warnings"
  end

  def test_help_and_version_return_nil
    out = StringIO.new
    assert_nil CLI.parse(%w[--help], out:)
    assert_includes out.string, "Usage:"
    assert_includes out.string, "--config FILE"
    assert_includes out.string, "[RUNSHEETS_PORT]"
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
      File.write(File.join(dir, "runbook.md"), "---\ntitle: T\n---\nno steps\n")
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

  def test_shutdown_ends_the_session_and_stops_what_runs_left_running
    with_runs_dir do |root|
      s  = open_session(root)
      bg = s.execute("035-keep-a-clock-running-1")
      wait_for { bg.output.include?("still here") }
      CLI.shutdown(s)
      assert s.ended?
      assert bg.stopped?
      assert_equal "partial", JSON.parse(File.read(File.join(s.run.dir, "run.json")))["status"]
      assert_includes File.read(s.log.path), "ended (runsheets stopped)"
      CLI.shutdown(s)
      assert_equal 1, File.read(s.log.path).scan("ended (").size, "ending twice does nothing"
    end
  end

  def test_session_options_follow_the_settings
    with_clean_home do
      out    = StringIO.new
      config = CLI.configure(CLI.parse(%w[--verbose --quiet --engineer Ada --why testing]))
      assert_equal({ runs_root: Runsheets.runs_dir, log_level: "debug", echo: nil }, CLI.session_options(config, out:))
      assert_equal "Ada", CLI.default_engineer(config)
      assert_equal "testing", config.why
      loud = CLI.configure(CLI.parse(%w[--log-level warn]))
      assert_equal({ runs_root: Runsheets.runs_dir, log_level: "warn", echo: out }, CLI.session_options(loud, out:))
      assert_raises(OptionParser::ParseError) { CLI.parse(%w[--log-level chatty]) }
    end
  end

  def test_bind_warning_mentions_the_host_check
    assert_includes CLI.bind_warning("0.0.0.0"), "Host header check is off"
    assert_includes CLI.bind_warning("192.168.1.5"), "Only requests with this address"
  end

  def test_dump_is_a_flag
    assert_equal({ dump: true }, CLI.parse(%w[--dump]))
    assert_equal({ dump: false }, CLI.parse(%w[--no-dump]))
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[--dump x y]) }
  end

  def test_dump_prints_the_settings_as_a_config_file_and_exits
    ENV["RUNSHEETS_PORT"] = "4590"
    out = StringIO.new
    assert_equal 0, CLI.run(%w[--dump -b 127.0.0.2 /tmp/book], out:, err: StringIO.new)
    assert_match(/\A# runsheets settings/, out.string)
    loaded = YAML.safe_load(out.string)
    assert_equal({ "port" => 4590, "bind" => "127.0.0.2", "dir" => "/tmp/book" }, loaded.slice("port", "bind", "dir"))
    refute loaded.key?("dump")
    refute File.exist?(Runsheets::Config.xdg_path), "nothing is written; the runbook is not even loaded"
  end

  def test_dump_can_come_from_the_environment_and_be_switched_off
    ENV["RUNSHEETS_DUMP"] = "1"
    out = StringIO.new
    assert_equal 0, CLI.run([], out:, err: StringIO.new)
    assert_match(/\A# runsheets settings/, out.string)
    out = StringIO.new
    assert_equal 0, CLI.run(%w[--no-dump --check], out:, err: StringIO.new)
    assert_includes out.string, "Hello, runsheets: 6 steps, 0 warnings"
  end

  def test_check_on_a_directory_of_runbooks_checks_each_one
    out = StringIO.new
    err = StringIO.new
    assert_equal 0, CLI.run(["--check", File.expand_path("../examples", __dir__)], out:, err:)
    lines = out.string.lines.map(&:chomp)
    assert_equal 4, lines.size
    assert_includes lines, "Hello, runsheets: 6 steps, 0 warnings"
    assert_includes lines, "Disk space triage: 3 steps, 0 warnings"
    assert_includes lines, "Monthly PostgreSQL maintenance: 5 steps, 0 warnings"
    assert_empty err.string
  end

  def test_check_on_a_directory_with_a_broken_runbook_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "fine.md"), "---\ntitle: Fine\n---\n\n## Step\n<!-- kind: manual -->\n\nDo it.\n")
      FileUtils.mkdir_p(File.join(dir, "bad"))
      File.write(File.join(dir, "bad", "runbook.md"), "no front matter, no steps\n")
      out = StringIO.new
      err = StringIO.new
      assert_equal 1, CLI.run(["--check", dir], out:, err:)
      assert_includes out.string, "Fine: 1 steps, 0 warnings"
      assert_includes err.string, "runsheets: error: bad: runbook.md is not a runbook: it needs YAML front matter with a title"
    end
  end

  def test_an_empty_directory_is_reported
    Dir.mktmpdir do |dir|
      err = StringIO.new
      assert_equal 1, CLI.run(["--check", dir], out: StringIO.new, err:)
      assert_includes err.string, "no runbooks in"
    end
  end
end
