# frozen_string_literal: true

require "test_helper"

class TestConfig < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::CliFixtures

  Config = Runsheets::Config

  def test_bundled_defaults_come_from_defaults_yml
    with_clean_home do |home|
      config = Config.new
      assert_nil config.dir
      assert_equal 4567, config.port
      assert_equal "127.0.0.1", config.bind
      assert_equal File.join(home, ".local/share/runsheets/runs"), config.runs_dir
      refute config.open
      refute config.check
      refute config.init
      refute config.dump
    end
  end

  def test_the_config_files_are_looked_for_in_the_usual_places
    with_clean_home do |home|
      config = Config.new
      assert_equal File.join(home, ".config/runsheets/runsheets.yml"), Config.xdg_path, "the XDG user config, absent is fine"
      assert_equal File.expand_path("config/runsheets.yml"), config.path, "the project config, absent is fine"
      assert_empty config.files
    end
  end

  def test_every_bundled_default_is_an_attribute_with_a_coercion
    schema = YAML.safe_load_file(Config.defaults_path, symbolize_names: true)
    assert_equal %i[dir port bind runs_dir open check init dump engineer why log_level quiet], schema[:defaults].keys
    assert_equal schema[:defaults].keys.sort, Config.config_attributes.sort
    assert_equal schema[:defaults].keys.sort, Config.coercion_mapping.keys.sort
  end

  def test_the_xdg_user_config_is_read_when_present
    with_clean_home do |home|
      write_yaml(Config.xdg_path, port: 4580, runs_dir: "~/runs", open: "yes", dir: "books/hello")
      config = Config.new
      assert_equal 4580, config.port
      assert_equal File.join(home, "runs"), config.runs_dir, "~ is expanded"
      assert config.open
      assert_equal File.expand_path("books/hello"), config.dir
    end
  end

  def test_an_explicit_config_file_layers_over_the_xdg_one
    with_clean_home do |home|
      xdg    = write_yaml(Config.xdg_path, port: 4580, bind: "0.0.0.0")
      other  = write_yaml(File.join(home, "other.yml"), port: 4581)
      config = Config.new(path: other)
      assert_equal 4581, config.port
      assert_equal "0.0.0.0", config.bind, "the XDG file is still underneath"
      assert_equal [xdg, other], config.files
    end
  end

  def test_runsheets_config_names_the_file_and_path_beats_it
    with_clean_home do |home|
      xdg   = write_yaml(Config.xdg_path, port: 4580)
      other = write_yaml(File.join(home, "other.yml"), port: 4581)
      ports = with_env("RUNSHEETS_CONFIG" => other) { [Config.new.port, Config.new(path: xdg).port] }
      assert_equal 4581, ports.first
      assert_equal 4580, ports.last, "path: beats the variable"
    end
  end

  def test_a_named_config_file_must_exist
    with_clean_home do |home|
      missing = File.join(home, "nope.yml")
      error = assert_raises(Runsheets::ConfigError) { Config.new(path: missing) }
      assert_match(/config file not found/, error.message)
    end
  end

  def test_runsheets_config_must_name_a_file_that_exists_unless_blank
    with_clean_home do |home|
      missing = File.join(home, "nope.yml")
      assert_raises(Runsheets::ConfigError) { with_env("RUNSHEETS_CONFIG" => missing) { Config.new } }
      assert_equal 4567, with_env("RUNSHEETS_CONFIG" => "  ") { Config.new.port }, "a blank variable means the project file"
    end
  end

  def test_environment_beats_the_config_file
    with_clean_home do
      write_yaml(Config.xdg_path, port: 4580, bind: "0.0.0.0", open: true, check: true)
      config = with_env("RUNSHEETS_PORT" => "4590", "RUNSHEETS_OPEN" => "off", "RUNSHEETS_DIR" => "/tmp/from-env") { Config.new }
      assert_equal 4590, config.port
      assert_equal "0.0.0.0", config.bind
      refute config.open, "RUNSHEETS_OPEN=off beats open: true in the file"
      assert config.check
      assert_equal "/tmp/from-env", config.dir
    end
  end

  def test_overrides_beat_the_environment
    with_clean_home do
      write_yaml(Config.xdg_path, port: 4580, bind: "0.0.0.0", open: true, check: true)
      overrides = { port: 9000, bind: "127.0.0.1", check: false, dir: "/tmp/from-cli" }
      config = with_env("RUNSHEETS_PORT" => "4590", "RUNSHEETS_OPEN" => "off", "RUNSHEETS_DIR" => "/tmp/from-env") { Config.new(overrides) }
      assert_equal 9000, config.port
      assert_equal "127.0.0.1", config.bind
      refute config.check
      assert_equal "/tmp/from-cli", config.dir
      refute config.open, "untouched layers still apply"
    end
  end

  def test_flags_accept_the_usual_words
    with_clean_home do
      opens = %w[1 true TRUE yes On 0 false no off maybe].map { with_env("RUNSHEETS_OPEN" => it) { Config.new.open } }
      assert_equal [true] * 5, opens.first(5), "1 true TRUE yes On"
      assert_equal [false] * 5, opens.last(5), "0 false no off maybe"
    end
  end

  def test_blank_values_fall_back_to_the_bundled_default
    with_clean_home do
      write_yaml(Config.xdg_path, port: 4580)
      config = with_env("RUNSHEETS_PORT" => "", "RUNSHEETS_RUNS_DIR" => " ") { Config.new }
      assert_equal 4567, config.port
      assert_equal Config.bundled_defaults[:runs_dir], config.runs_dir
    end
  end

  def test_a_bad_port_in_the_environment_is_a_config_error
    with_clean_home do
      error = assert_raises(Runsheets::ConfigError) { with_env("RUNSHEETS_PORT" => "eighty") { Config.new } }
      assert_match(/port must be a whole number, got "eighty"/, error.message)
    end
  end

  def test_a_port_must_be_a_whole_number
    with_clean_home do
      assert_raises(Runsheets::ConfigError) { Config.new({ port: "80x" }) }
      assert_equal 80, Config.new({ port: " 80 " }).port
    end
  end

  def test_runsheets_runs_dir_follows_the_config
    with_clean_home do |home|
      write_yaml(Config.xdg_path, runs_dir: "~/elsewhere")
      assert_equal File.join(home, "elsewhere"), Runsheets.runs_dir
      assert_equal File.join(home, "elsewhere"), Runsheets.config.runs_dir
    end
  end

  def test_an_explicit_runs_dir_beats_the_config
    with_clean_home do |home|
      write_yaml(Config.xdg_path, runs_dir: "~/elsewhere")
      Runsheets.runs_dir = "/explicit"
      assert_equal "/explicit", Runsheets.runs_dir
      assert_equal File.join(home, "elsewhere"), Runsheets.config.runs_dir, "the config itself is unchanged"
    ensure
      Runsheets.runs_dir = nil
    end
  end

  def test_to_config_yaml_round_trips_through_a_config_file
    with_clean_home do |home|
      text = with_env("RUNSHEETS_PORT" => "4590") { Config.new({ bind: "127.0.0.2", open: true, dump: true }).to_config_yaml }
      reloaded = reload_config_yaml(home, text)
      assert_equal 4590, reloaded.port
      assert_equal "127.0.0.2", reloaded.bind
      assert reloaded.open
      refute reloaded.dump, "dump is an action for one run and is never written"
    end
  end

  def test_to_config_yaml_holds_every_setting_but_the_one_shot_actions_and_why
    with_clean_home do
      text   = Config.new({ port: 4590, open: "yes" }).to_config_yaml
      loaded = YAML.safe_load(text)
      assert_match(/\A# runsheets settings, written by `runsheets --dump`/, text)
      assert_equal (Config.config_attributes - %i[dump check init why]).map(&:to_s).sort, loaded.keys.sort
      assert_equal 4590, loaded["port"]
      assert loaded["open"]
    end
  end

  def test_port_must_be_a_real_port
    with_clean_home do
      assert_raises(Runsheets::ConfigError) { Config.new({ port: "0" }) }
      assert_raises(Runsheets::ConfigError) { Config.new({ port: "70000" }) }
      assert_equal 65_535, Config.new({ port: "65535" }).port
    end
  end
end
