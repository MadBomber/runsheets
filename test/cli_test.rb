# frozen_string_literal: true

require "test_helper"

class TestCLI < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::CliFixtures

  CLI = Runsheets::CLI
  EXAMPLES = File.expand_path("../examples", __dir__)
  HELLO_CLEAN = "Hello, runsheets: 6 steps, 0 warnings"

  # Each test gets an empty home and no RUNSHEETS_* variables; whatever a
  # test sets is removed again, and the original environment comes back.
  def setup = sandbox_home!

  def teardown = restore_home!

  def test_parse_returns_only_what_was_given
    assert_equal({ dir: RunsheetsTest::EXAMPLE_DIR }, CLI.parse([RunsheetsTest::EXAMPLE_DIR]))
    assert_empty CLI.parse([])
  end

  def test_parse_options
    options = CLI.parse("-p 9000 -b 0.0.0.0 --runs-dir /tmp/r --open --check -c /tmp/c.yml x".split)
    assert_equal 9000, options[:port]
    assert_equal "0.0.0.0", options[:bind]
    assert_equal "/tmp/r", options[:runs_dir]
    assert options[:open]
    assert options[:check]
    assert_equal "/tmp/c.yml", options[:config]
    assert_equal "x", options[:dir]
  end

  def test_parse_negated_flags
    assert_equal({ open: false, check: false, init: false, dump: false }, CLI.parse(%w[--no-open --no-check --no-init --no-dump]))
    assert_equal({ dump: true }, CLI.parse(%w[--dump]))
  end

  def test_configure_layers_the_environment_over_the_config_file
    file = write_yaml(File.join(@home, "rs.yml"), port: 4580, bind: "0.0.0.0", open: true, dir: "/tmp/from-file")
    ENV["RUNSHEETS_PORT"] = "4590"
    ENV["RUNSHEETS_OPEN"] = "no"
    config = cli_config("--config", file)
    assert_equal 4590, config.port
    assert_equal "0.0.0.0", config.bind
    refute config.open
    assert_equal "/tmp/from-file", config.dir
    assert_same config, Runsheets.config
  end

  def test_configure_layers_the_command_line_over_the_environment
    file = write_yaml(File.join(@home, "rs.yml"), port: 4580, bind: "0.0.0.0", open: true, dir: "/tmp/from-file")
    ENV["RUNSHEETS_PORT"] = "4590"
    ENV["RUNSHEETS_OPEN"] = "no"
    config = cli_config("-c", file, "-p", "9000", "--open", "/tmp/from-argv")
    assert_equal 9000, config.port
    assert_equal "0.0.0.0", config.bind, "the file still supplies what nothing overrides"
    assert config.open
    assert_equal "/tmp/from-argv", config.dir
  end

  def test_the_xdg_user_config_is_in_the_home
    assert_equal File.join(@home, ".config/runsheets/runsheets.yml"), Runsheets::Config.xdg_path
    refute File.exist?(Runsheets::Config.xdg_path)
  end

  def test_the_xdg_user_config_is_read_by_default
    write_yaml(Runsheets::Config.xdg_path, dir: RunsheetsTest::EXAMPLE_DIR, check: true)
    run = run_cli
    assert_equal 0, run.status
    assert_includes run.out, HELLO_CLEAN
  end

  def test_runsheets_dir_stands_in_for_the_runbook_argument
    ENV["RUNSHEETS_DIR"] = RunsheetsTest::EXAMPLE_DIR
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.runbook_path(cli_config)
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.runbook_path(cli_config("--init"))
    assert_equal "/tmp/argv", CLI.runbook_path(cli_config("/tmp/argv"))
  end

  def test_init_without_any_runbook_path_is_an_error
    run = run_cli("--init")
    assert_equal 1, run.status
    assert_match(/--init needs the path/, run.err)
  end

  def test_a_missing_config_file_exits_one_with_a_message
    run = run_cli(%w[--config /nope.yml --check])
    assert_equal 1, run.status
    assert_includes run.err, "runsheets: config file not found: /nope.yml"
  end

  def test_a_bad_setting_exits_one_with_a_message
    ENV["RUNSHEETS_PORT"] = "abc"
    run = run_cli("--check")
    assert_equal 1, run.status
    assert_includes run.err, 'runsheets: port must be a whole number, got "abc"'
  end

  def test_parse_errors
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[a b]) }
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[--bogus a]) }
    assert_raises(OptionParser::MissingArgument) { CLI.parse(%w[--config]) }
    assert_raises(OptionParser::ParseError) { CLI.parse(%w[--dump x y]) }
  end

  def test_no_runbook_means_the_bundled_example
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI::DEFAULT_RUNBOOK
    assert_equal RunsheetsTest::EXAMPLE_DIR, CLI.runbook_path(cli_config)
  end

  def test_check_with_no_runbook_checks_the_bundled_example
    run = run_cli("--check")
    assert_equal 0, run.status
    assert_includes run.out, HELLO_CLEAN
  end

  def test_help_returns_nil_and_prints_the_usage
    options, text = parse_cli("--help")
    assert_nil options
    assert_includes text, "Usage:"
    assert_includes text, "--config FILE"
    assert_includes text, "[RUNSHEETS_PORT]"
  end

  def test_version_returns_nil_and_prints_the_version
    options, text = parse_cli("--version")
    assert_nil options
    assert_includes text, Runsheets::VERSION
  end

  def test_init_scaffolds_a_directory_runbook
    with_scratch_dir do |dir|
      target = File.join(dir, "new-runbook")
      run = run_cli("--init", target)
      assert_equal 0, run.status
      assert_includes run.out, "created #{File.join(target, 'runbook.md')}"
      assert File.file?(File.join(target, "steps", "010-first-step.md"))
      assert File.file?(File.join(target, "verify.md"))
      assert File.file?(File.join(target, "rollback.md"))
    end
  end

  def test_a_scaffolded_directory_runbook_checks_clean_and_is_not_overwritten
    with_scratch_dir do |dir|
      target = File.join(dir, "new-runbook")
      run_cli("--init", target)
      check = run_cli("--check", target)
      again = run_cli("--init", target)
      assert_equal 0, check.status, check.err
      assert_equal "New runbook", Runsheets::Runbook.load(target).title
      assert_equal 1, again.status
      assert_match(/not empty/, again.err)
    end
  end

  def test_init_scaffolds_a_single_file_runbook
    with_scratch_dir do |dir|
      target = File.join(dir, "db-refresh.md")
      run = run_cli("--init", target)
      rb  = Runsheets::Runbook.load(target)
      assert_equal 0, run.status
      assert File.file?(target)
      assert rb.single_file?
      assert_equal "Db refresh", rb.title
      assert_equal 2, rb.steps.size
      assert rb.verify
      assert rb.rollback
    end
  end

  def test_a_scaffolded_single_file_runbook_checks_clean_and_is_not_overwritten
    with_scratch_dir do |dir|
      target = File.join(dir, "db-refresh.md")
      run_cli("--init", target)
      check = run_cli("--check", target)
      again = run_cli("--init", target)
      assert_equal 0, check.status, check.err
      assert_equal 1, again.status
      assert_match(/already exists/, again.err)
    end
  end

  def test_check_accepts_a_single_file
    run = run_cli("--check", File.join(EXAMPLES, "db-maintenance.md"))
    assert_equal 0, run.status
    assert_includes run.out, "0 warnings"
  end

  def test_check_mode
    run = run_cli("--check", RunsheetsTest::EXAMPLE_DIR)
    assert_equal 0, run.status
    assert_includes run.out, "6 steps, 0 warnings"
    assert_empty run.err
  end

  def test_check_mode_reports_warnings_and_fails
    with_scratch_dir("runbook.md" => "---\ntitle: T\n---\nno steps\n") do |dir|
      run = run_cli("--check", dir)
      assert_equal 1, run.status
      assert_includes run.err, "warning: no steps found"
    end
  end

  def test_missing_runbook_is_an_error
    run = run_cli("--check", "/nonexistent/dir")
    assert_equal 1, run.status
    assert_includes run.err, "no such runbook"
  end

  def test_shutdown_ends_the_session_and_stops_what_runs_left_running
    with_running_clock do |session, clock|
      CLI.shutdown(session)
      assert session.ended?
      assert clock.stopped?
      assert_equal "partial", run_json_status(session.run)
      assert_includes File.read(session.log.path), "ended (runsheets stopped)"
    end
  end

  def test_shutting_down_twice_ends_the_session_once
    with_running_clock do |session, _clock|
      CLI.shutdown(session)
      CLI.shutdown(session)
      assert session.ended?
      assert_equal 1, File.read(session.log.path).scan("ended (").size, "ending twice does nothing"
    end
  end

  def test_quiet_session_options_follow_the_settings
    with_clean_home do
      config = cli_config(%w[--verbose --quiet --engineer Ada --why testing])
      assert_equal({ runs_root: Runsheets.runs_dir, log_level: "debug", echo: nil }, CLI.session_options(config, out: StringIO.new))
      assert_equal "Ada", CLI.default_engineer(config)
      assert_equal "testing", config.why
    end
  end

  def test_the_log_level_is_echoed_and_checked
    with_clean_home do
      out  = StringIO.new
      loud = cli_config(%w[--log-level warn])
      assert_equal({ runs_root: Runsheets.runs_dir, log_level: "warn", echo: out }, CLI.session_options(loud, out:))
      assert_equal "warn", cli_config(%w[--log-level WARN]).log_level, "any case, as RUNSHEETS_LOG_LEVEL"
      assert_raises(Runsheets::ConfigError) { cli_config(%w[--log-level chatty]) }
    end
  end

  def test_dump_never_saves_a_one_shot_action
    with_clean_home do
      run   = run_cli(%w[--dump --check --init x])
      saved = YAML.safe_load(run.out)
      assert_equal 0, run.status
      refute saved.key?("check")
      refute saved.key?("init")
    end
  end

  def test_init_quotes_titles_that_yaml_would_misread
    with_scratch_dir do |dir|
      null = File.join(dir, "null.md")
      yes  = File.join(dir, "yes.md")
      statuses = [run_cli("--init", null).status, run_cli("--init", yes).status]
      assert_equal [0, 0], statuses
      assert_equal "Null", Runsheets::Runbook.load(null).title
      assert_equal "Yes", Runsheets::Runbook.load(yes).title
    end
  end

  def test_check_reports_bad_files_instead_of_crashing
    files = { "good.md" => single_manual_runbook("Good", step: "Go"),
              "tagged.md" => "---\ntitle: !ruby/object:Object {}\n---\n",
              "latin.md" => single_manual_runbook("na\xEFve".b, step: "Go").b }
    with_scratch_dir(files) do |dir|
      run = run_cli("--check", dir)
      assert_equal 1, run.status
      assert_includes run.err, "error: tagged: front matter could not be read"
    end
  end

  def test_bind_warning_mentions_the_host_check
    assert_includes CLI.bind_warning("0.0.0.0"), "Host header check is off"
    assert_includes CLI.bind_warning("192.168.1.5"), "Only requests with this address"
  end

  def test_dump_prints_the_settings_as_a_config_file_and_exits
    ENV["RUNSHEETS_PORT"] = "4590"
    run    = run_cli(%w[--dump -b 127.0.0.2 /tmp/book])
    loaded = YAML.safe_load(run.out)
    assert_equal 0, run.status
    assert_match(/\A# runsheets settings/, run.out)
    assert_equal({ "port" => 4590, "bind" => "127.0.0.2", "dir" => "/tmp/book" }, loaded.slice("port", "bind", "dir"))
    refute loaded.key?("dump")
    refute File.exist?(Runsheets::Config.xdg_path), "nothing is written; the runbook is not even loaded"
  end

  def test_dump_can_come_from_the_environment
    ENV["RUNSHEETS_DUMP"] = "1"
    run = run_cli
    assert_equal 0, run.status
    assert_match(/\A# runsheets settings/, run.out)
  end

  def test_dump_from_the_environment_can_be_switched_off
    ENV["RUNSHEETS_DUMP"] = "1"
    run = run_cli(%w[--no-dump --check])
    assert_equal 0, run.status
    assert_includes run.out, HELLO_CLEAN
  end

  def test_check_on_a_directory_of_runbooks_checks_each_one
    run   = run_cli("--check", EXAMPLES)
    lines = run.out.lines.map(&:chomp)
    assert_equal 0, run.status
    assert_equal 4, lines.size
    assert_includes lines, "Hello, runsheets [hello]: 6 steps, 0 warnings", "a library's lines name the slug"
    assert_includes lines, "Disk space triage [disk-space-triage]: 3 steps, 0 warnings"
    assert_includes lines, "Monthly PostgreSQL maintenance [db-maintenance]: 5 steps, 0 warnings"
    assert_empty run.err
  end

  def test_check_on_a_directory_with_a_broken_runbook_fails
    files = { "fine.md" => single_manual_runbook("Fine"), "bad/runbook.md" => "no front matter, no steps\n" }
    with_scratch_dir(files) do |dir|
      run = run_cli("--check", dir)
      assert_equal 1, run.status
      assert_includes run.out, "Fine [fine]: 1 steps, 0 warnings"
      assert_includes run.err, "runsheets: error: bad: runbook.md is not a runbook: it needs YAML front matter with a title"
    end
  end

  def test_an_empty_directory_is_reported
    with_scratch_dir do |dir|
      run = run_cli("--check", dir)
      assert_equal 1, run.status
      assert_includes run.err, "no runbooks in"
    end
  end
end
