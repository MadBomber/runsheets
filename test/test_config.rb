# frozen_string_literal: true

require "test_helper"

class TestConfig < Minitest::Test
  include RunsheetsTest

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
      assert_equal File.join(home, ".config/runsheets/runsheets.yml"), Config.xdg_path, "the XDG user config, absent is fine"
      assert_equal File.expand_path("config/runsheets.yml"), config.path, "the project config, absent is fine"
      assert_empty config.files
    end
  end

  def test_every_bundled_default_is_an_attribute_with_a_coercion
    schema = YAML.safe_load_file(Config.defaults_path, symbolize_names: true)
    assert_equal %i[dir port bind runs_dir open check init dump], schema[:defaults].keys
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
      xdg   = write_yaml(Config.xdg_path, port: 4580, bind: "0.0.0.0")
      other = write_yaml(File.join(home, "other.yml"), port: 4581)
      config = Config.new(path: other)
      assert_equal 4581, config.port
      assert_equal "0.0.0.0", config.bind, "the XDG file is still underneath"
      assert_equal [xdg, other], config.files
      with_env("RUNSHEETS_CONFIG" => other) { assert_equal 4581, Config.new.port }
      with_env("RUNSHEETS_CONFIG" => other) { assert_equal 4580, Config.new(path: xdg).port, "path: beats the variable" }
    end
  end

  def test_a_named_config_file_must_exist
    with_clean_home do |home|
      missing = File.join(home, "nope.yml")
      error = assert_raises(Runsheets::ConfigError) { Config.new(path: missing) }
      assert_match(/config file not found/, error.message)
      with_env("RUNSHEETS_CONFIG" => missing) { assert_raises(Runsheets::ConfigError) { Config.new } }
      with_env("RUNSHEETS_CONFIG" => "  ") { assert_equal 4567, Config.new.port, "a blank variable means the project file" }
    end
  end

  def test_environment_beats_the_config_file_and_overrides_beat_the_environment
    with_clean_home do
      write_yaml(Config.xdg_path, port: 4580, bind: "0.0.0.0", open: true, check: true)
      with_env("RUNSHEETS_PORT" => "4590", "RUNSHEETS_OPEN" => "off", "RUNSHEETS_DIR" => "/tmp/from-env") do
        from_env = Config.new
        assert_equal 4590, from_env.port
        assert_equal "0.0.0.0", from_env.bind
        refute from_env.open, "RUNSHEETS_OPEN=off beats open: true in the file"
        assert from_env.check
        assert_equal "/tmp/from-env", from_env.dir

        from_cli = Config.new({ port: 9000, bind: "127.0.0.1", check: false, dir: "/tmp/from-cli" })
        assert_equal 9000, from_cli.port
        assert_equal "127.0.0.1", from_cli.bind
        refute from_cli.check
        assert_equal "/tmp/from-cli", from_cli.dir
        refute from_cli.open, "untouched layers still apply"
      end
    end
  end

  def test_flags_accept_the_usual_words
    with_clean_home do
      %w[1 true TRUE yes On].each { with_env("RUNSHEETS_OPEN" => it) { assert Config.new.open, it } }
      %w[0 false no off maybe].each { with_env("RUNSHEETS_OPEN" => it) { refute Config.new.open, it } }
    end
  end

  def test_blank_values_fall_back_to_the_bundled_default
    with_clean_home do
      write_yaml(Config.xdg_path, port: 4580)
      with_env("RUNSHEETS_PORT" => "", "RUNSHEETS_RUNS_DIR" => " ") do
        config = Config.new
        assert_equal 4567, config.port
        assert_equal Config.bundled_defaults[:runs_dir], config.runs_dir
      end
    end
  end

  def test_a_bad_port_is_a_config_error
    with_clean_home do
      with_env("RUNSHEETS_PORT" => "eighty") do
        error = assert_raises(Runsheets::ConfigError) { Config.new }
        assert_match(/port must be a whole number, got "eighty"/, error.message)
      end
      assert_raises(Runsheets::ConfigError) { Config.new({ port: "80x" }) }
      assert_equal 80, Config.new({ port: " 80 " }).port
    end
  end

  def test_runsheets_runs_dir_follows_the_config
    with_clean_home do |home|
      write_yaml(Config.xdg_path, runs_dir: "~/elsewhere")
      assert_equal File.join(home, "elsewhere"), Runsheets.runs_dir
      Runsheets.runs_dir = "/explicit"
      assert_equal "/explicit", Runsheets.runs_dir
    ensure
      Runsheets.runs_dir = nil
    end
  end

  def test_to_config_yaml_round_trips_through_a_config_file
    with_clean_home do |home|
      text = with_env("RUNSHEETS_PORT" => "4590") { Config.new({ bind: "127.0.0.2", open: true, dump: true }).to_config_yaml }
      file = File.join(home, "saved.yml")
      File.write(file, text)
      reloaded = Config.new(path: file)
      assert_equal 4590, reloaded.port
      assert_equal "127.0.0.2", reloaded.bind
      assert reloaded.open
      refute reloaded.dump, "dump is an action for one run and is never written"
    end
  end

  def test_to_config_yaml_holds_every_setting_but_dump
    with_clean_home do
      text = Config.new({ port: 4590, open: "yes" }).to_config_yaml
      assert_match(/\A# runsheets settings, written by `runsheets --dump`/, text)
      loaded = YAML.safe_load(text)
      assert_equal (Config.config_attributes - [:dump]).map(&:to_s).sort, loaded.keys.sort
      assert_equal 4590, loaded["port"]
      assert loaded["open"]
    end
  end
end
