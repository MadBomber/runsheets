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
    assert_equal({ open: false, check: false, dump: false }, CLI.parse(%w[--no-open --no-check --no-dump]))
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
    assert_equal "/tmp/argv", CLI.runbook_path(cli_config("/tmp/argv"))
  end

  def test_new_takes_no_runbook_beside_its_directory
    run = run_cli("--new", "/tmp/x", "also-this")
    assert_equal 1, run.status
    assert_match(/give no RUNBOOK with it/, run.err)
  end

  def test_new_without_a_directory_asks_for_one
    with_scratch_dir do |dir|
      run = run_cli("--new", input: "#{dir}\n\n\nasked\n")
      assert_equal 0, run.status, run.err
      assert_includes run.out, "Directory to create the runbook in: "
      assert File.file?(File.join(dir, "asked", "runbook.md"))
    end
  end

  def test_new_without_a_directory_or_an_answer_is_an_error
    run = run_cli("--new")
    assert_equal 1, run.status
    assert_match(/a directory is needed/, run.err)
  end

  def test_new_offers_runsheets_dir_as_the_directory
    with_scratch_dir do |dir|
      ENV["RUNSHEETS_DIR"] = dir
      run = run_cli("--new", input: "\n\n\nfrom-env\n")
      assert_equal 0, run.status, run.err
      assert_includes run.out, "Directory to create the runbook in [#{dir}]: "
      assert File.file?(File.join(dir, "from-env", "runbook.md"))
    end
  end

  def test_new_offers_the_config_file_dir_over_runsheets_dir
    with_scratch_dir do |dir|
      from_file = File.join(dir, "from-file")
      config    = write_yaml(File.join(dir, "runsheets.yml"), dir: from_file)
      ENV["RUNSHEETS_DIR"] = File.join(dir, "from-env")
      run = run_cli("--new", "--config", config, input: "\n\n\nchosen\n")
      assert_equal 0, run.status, run.err
      assert File.file?(File.join(from_file, "chosen", "runbook.md"))
    end
  end

  def test_new_parent_default_follows_the_config_file_then_the_environment
    with_scratch_dir("lib/one.md" => "x") do |dir|
      config = Struct.new(:file_dir)
      assert_equal "/from/file", CLI.new_parent_default(config.new("/from/file"), env: { "RUNSHEETS_DIR" => "/from/env" })
      assert_equal "/from/env", CLI.new_parent_default(config.new(nil), env: { "RUNSHEETS_DIR" => " /from/env " })
      assert_nil CLI.new_parent_default(config.new(nil), env: { "RUNSHEETS_DIR" => "" })
      assert_equal File.join(dir, "lib"), CLI.new_parent_default(config.new(File.join(dir, "lib", "one.md")), env: {}),
                   "a single-file runbook offers its directory"
    end
  end

  def test_new_ignores_a_project_config_that_binds_to_the_network
    with_scratch_dir("config/runsheets.yml" => "bind: 0.0.0.0\n") do |dir|
      Dir.chdir(dir) do
        run = run_cli("--new", dir, input: "\n\nok\n")
        assert_equal 0, run.status, run.err
      end
    end
  end

  def test_init_is_gone
    run = run_cli("--init", "/tmp/x")
    assert_equal 1, run.status
    assert_match(/invalid option: --init/, run.err)
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

  def test_new_writes_a_directory_runbook_from_the_answers
    with_scratch_dir do |dir|
      run    = run_cli("--new", dir, input: "1\ntasks\nDB Refresh\n\n\n\ny\n")
      target = File.join(dir, "db-refresh")
      check  = run_cli("--check", target)
      assert_equal 0, run.status, run.err
      assert_includes run.out, "created #{File.join(target, 'runbook.md')}"
      assert_includes run.out, "#{CLI::PROGRAM} --check #{target}"
      assert File.file?(File.join(target, "steps", "010-preflight.md"))
      assert_equal "Db refresh", Runsheets::Runbook.load(target).title
      assert_equal 0, check.status, check.err
    end
  end

  def test_new_writes_a_single_file_runbook_from_the_answers
    with_scratch_dir do |dir|
      run    = run_cli("--new", dir, input: "2\n3\nflaky-api\nFlaky API\nWhen the API times out\n#oncall\n\n")
      target = File.join(dir, "flaky-api.md")
      rb     = Runsheets::Runbook.load(target)
      assert_equal 0, run.status, run.err
      assert rb.single_file?
      assert_equal "Flaky API", rb.title
      assert_equal "When the API times out", rb.data["when_to_use"]
      assert_equal "#oncall", rb.data["escalation"]
      assert_equal 4, rb.steps.size, "the rollback template"
      assert rb.rollback
    end
  end

  def test_new_puts_a_single_file_with_support_files_in_a_folder_of_its_own
    with_scratch_dir do |dir|
      run    = run_cli("--new", dir, input: "2\nasgard\nnightly\n")
      folder = File.join(dir, "nightly")
      main   = File.join(folder, "nightly.md")
      assert_equal 0, run.status, run.err
      assert_equal %w[.loki nightly.md tasks.loki], Dir.children(folder).sort
      assert_includes run.out, "#{CLI::PROGRAM} --check #{main}"
      assert Runsheets::Runbook.load(main).single_file?
    end
  end

  def test_new_with_no_answers_takes_every_default
    with_scratch_dir do |dir|
      run = run_cli("--new", dir)
      assert_equal 0, run.status, run.err
      assert File.file?(File.join(dir, Runsheets::Wizard::DEFAULT_NAME, "runbook.md"))
    end
  end

  def test_new_refuses_a_name_that_is_taken_when_there_is_no_other_answer
    with_scratch_dir("taken/runbook.md" => "x") do |dir|
      run = run_cli("--new", dir, input: "1\n1\ntaken\n")
      assert_equal 1, run.status
      assert_match(/taken exists and is not empty/, run.err)
      assert_equal "x", File.read(File.join(dir, "taken", "runbook.md"))
    end
  end

  def test_answering_no_creates_nothing
    with_scratch_dir do |dir|
      run = run_cli("--new", dir, input: "\n\nnope\n\n\n\nn\n")
      assert_equal 1, run.status
      assert_includes run.out, "Nothing created."
      assert_empty Dir.children(dir)
    end
  end

  def test_check_accepts_a_single_file
    run = run_cli("--check", File.join(EXAMPLES, "single_md_file_runbooks", "db-maintenance.md"))
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
      run   = run_cli(%w[--dump --check x])
      saved = YAML.safe_load(run.out)
      assert_equal 0, run.status
      refute saved.key?("check")
    end
  end

  def test_new_quotes_titles_that_yaml_would_misread
    with_scratch_dir do |dir|
      statuses = %w[null yes].map { run_cli("--new", dir, input: "2\n1\n#{it}\n").status }
      assert_equal [0, 0], statuses
      assert_equal "Null", Runsheets::Runbook.load(File.join(dir, "null.md")).title
      assert_equal "Yes", Runsheets::Runbook.load(File.join(dir, "yes.md")).title
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
    assert_equal 5, lines.size
    assert_includes lines, "Hello, runsheets [directory_based_runbooks/hello]: 6 steps, 0 warnings", "a library's lines name the slug"
    assert_includes lines, "Disk space triage [single_md_file_runbooks/disk-space-triage]: 3 steps, 0 warnings"
    assert_includes lines, "Monthly PostgreSQL maintenance [single_md_file_runbooks/db-maintenance]: 5 steps, 0 warnings"
    assert_includes lines, "Runbook tasks from local .loki files [single_md_file_runbooks/runbooks_with_scripts/asgard-tasks]: 4 steps, 0 warnings"
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

  def test_a_busy_port_fails_before_a_session_is_recorded
    taken = TCPServer.new("127.0.0.1", 0)
    port  = taken.addr[1]
    with_runs_dir do |runs|
      run = run_cli("--port", port.to_s, "--runs-dir", runs, "--engineer", "T", "--why", "w", EXAMPLE_DIR)
      assert_equal 1, run.status
      assert_includes run.err, "port #{port} on 127.0.0.1 is already in use"
      assert_empty Runsheets::Session.past(runs)
    end
  ensure
    taken&.close
  end

  def test_a_project_config_alone_cannot_open_the_server_to_the_network
    with_scratch_dir("config/runsheets.yml" => "bind: 0.0.0.0\n") do |dir|
      Dir.chdir(dir) do
        run = run_cli("--check", RunsheetsTest::EXAMPLE_DIR)
        assert_equal 1, run.status
        assert_match(/sets bind: 0\.0\.0\.0, which is not a loopback address/, run.err)
        assert_equal "0.0.0.0", cli_config("--bind", "0.0.0.0").bind, "the command line can still choose it"
        assert_equal "0.0.0.0", with_env("RUNSHEETS_BIND" => "0.0.0.0") { cli_config.bind }, "so can the environment"
      end
    end
  end

  def test_a_project_config_may_bind_a_loopback_address
    with_scratch_dir("config/runsheets.yml" => "bind: localhost\n") do |dir|
      Dir.chdir(dir) { assert_equal "localhost", cli_config.bind }
    end
  end
end
