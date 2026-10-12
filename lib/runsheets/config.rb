# frozen_string_literal: true

require "yaml"
require "myway_config"

module Runsheets
  class ConfigError < Error; end

  # Settings for the `runsheets` command, layered lowest to highest:
  #
  #   1. lib/runsheets/config/defaults.yml bundled with the gem (the schema; see that file)
  #   2. the XDG user config, ~/.config/runsheets/runsheets.yml (myway_config)
  #   3. the project config, ./config/runsheets.yml, or the file named by
  #      --config FILE or RUNSHEETS_CONFIG in its place
  #   4. RUNSHEETS_<KEY> environment variables
  #   5. the overrides hash, which the CLI fills from the command line
  #
  # Every key in defaults.yml is an attribute here (dir, port, bind, runs_dir,
  # open, check, dump, engineer, why, log_level, quiet). Paths are
  # expanded; flags accept 1/true/yes/on.
  class Config < MywayConfig::Base
    config_name :runsheets
    env_prefix  :runsheets
    defaults_path File.expand_path("config/defaults.yml", __dir__)

    TRUE_WORDS = %w[1 true yes on].freeze

    class << self
      def blank?(value) = value.nil? || value.to_s.strip.empty?

      # File.expand_path, but a ~user that names nobody is a ConfigError
      # rather than an ArgumentError, so the CLI reports it in one line.
      def expand_path(path, base = nil)
        File.expand_path(path, base)
      rescue ArgumentError => e
        raise ConfigError, "cannot expand #{path}: #{e.message}"
      end

      # A coercion that hands the stripped text to the block, or gives nil for
      # a blank so the bundled default fills it (see fill_blanks_from_defaults).
      def unless_blank = ->(v) { blank?(v) ? nil : yield(v.to_s.strip) }

      def whole_number(text)
        port = Integer(text, 10)
        raise ConfigError, "port must be between 1 and 65535, got #{port}" unless (1..65_535).cover?(port)

        port
      rescue ArgumentError
        raise ConfigError, "port must be a whole number, got #{text.inspect}"
      end

      # The XDG user config: the file myway_config found, else where it would be.
      def xdg_path
        MywayConfig::Loaders::XdgConfigLoader.find_config_file(config_name) ||
          File.join(Dir.home, ".config", config_name.to_s, "#{config_name}.yml")
      end

      # The config file named in place of the project config: +given+ (the
      # --config option), else RUNSHEETS_CONFIG, expanded; nil when neither
      # names one. Raises ConfigError when the file named does not exist.
      def explicit_path(given, env: ENV)
        name = [given, env["RUNSHEETS_CONFIG"]].find { !blank?(it) } or return nil
        path = expand_path(name)
        raise ConfigError, "config file not found: #{path}" unless File.file?(path)

        path
      end

      # The project config read when neither --config nor RUNSHEETS_CONFIG names a file.
      def project_path = File.expand_path(Anyway::Settings.default_config_path.call(config_name))

      # The settings one config file holds, as a string-keyed Hash, read as
      # myway_config reads it: the section for +environment+ when one is
      # set and the file has it, else the whole file. {} when it is
      # missing, unreadable or not a mapping.
      def file_settings(path, environment: current_environment)
        data = YAML.safe_load_file(path, aliases: false)
        return {} unless data.is_a?(Hash)

        section = data[environment] if environment
        section.is_a?(Hash) ? section : data
      rescue Psych::Exception, SystemCallError
        {}
      end

      # The environment whose section a config file is read from, or nil
      # (the usual case for a command) to read the whole file.
      def current_environment = Anyway::Settings.current_environment&.to_s

      # The bundled defaults, coerced, keyed by attribute. What the help text shows.
      def bundled_defaults = schema.to_h { |key, value| [key, type_caster.coerce(key, value)] }

      # Any RACK_ENV is fine; the environment sections of defaults.yml are optional.
      def validate_environment! = nil
    end

    # Coercions: the raw YAML/env/CLI value becomes the type the attribute needs.
    TEXT = unless_blank(&:itself)
    PATH = unless_blank { expand_path(it) }
    PORT = unless_blank { whole_number(it) }
    FLAG = ->(v) { v == true || TRUE_WORDS.include?(v.to_s.strip.downcase) }

    attr_config :dir, :port, :bind, :runs_dir, :open, :check, :dump, :engineer, :why, :log_level, :quiet
    coerce_types dir: PATH, runs_dir: PATH, bind: TEXT, port: PORT, open: FLAG, check: FLAG, dump: FLAG,
                 engineer: TEXT, why: TEXT, log_level: unless_blank { SessionLog.level_name(it) }, quiet: FLAG

    on_load :fill_blanks_from_defaults

    # The config file read in place of the project config, set while loading.
    attr_reader :path

    # overrides: a Hash of values that beat every other layer (the CLI's).
    # path: the config file to read instead of RUNSHEETS_CONFIG / ./config/runsheets.yml.
    def initialize(overrides = nil, path: nil)
      @explicit_path = path
      @override_keys = overrides.to_h.keys.map(&:to_s)
      super(overrides&.transform_keys(&:to_s))
    end

    # The config files that exist and were read, lowest layer first.
    def files = [self.class.xdg_path, path].select { File.file?(it) }

    # The dir a config file sets, whatever RUNSHEETS_DIR or the command line
    # say: from the highest file that has one, expanded, else nil.
    def file_dir
      files.reverse_each do |file|
        value = self.class.file_settings(file)["dir"]
        return self.class.expand_path(value.to_s) unless self.class.blank?(value)
      end
      nil
    end

    # The bind address in force when it came from the project config found
    # in the current directory, else nil. That file arrives with whatever
    # repository was cloned, so the CLI will not let it alone open the
    # server to the network (see CLI.check_bind_source).
    def project_bind
      return nil if @explicit_path || !self.class.blank?(ENV["RUNSHEETS_CONFIG"])
      return nil if @override_keys.include?("bind") || !self.class.blank?(ENV["RUNSHEETS_BIND"])
      return nil unless File.file?(path.to_s)

      self.class.file_settings(path).key?("bind") ? bind : nil
    end

    # The settings in force as the flat hash a config file holds. dump is
    # left out: it is an action for this run, and a saved `dump: true` would
    # make every later run print and exit; check likewise. why is
    # left out too: it belongs to one session, and a saved one would start
    # every later session with it.
    def settings = (self.class.config_attributes - %i[dump check why]).to_h { [it.to_s, public_send(it)] }

    # The settings in force as the text of a config file: a comment header,
    # then one key per setting. `runsheets --dump` prints this.
    def to_config_yaml
      <<~YAML + settings.to_yaml.delete_prefix("---\n")
        # runsheets settings, written by `runsheets --dump` on #{Time.now.strftime('%Y-%m-%d %H:%M')}.
        # One key per setting; RUNSHEETS_* variables and command-line options
        # override these. See `runsheets --help` for the layers.
      YAML
    end

    private

    # Where anyway_config's yml loader reads from. A file named explicitly
    # (option or variable) must exist; the project config may be absent.
    def resolve_config_path(_name, _env_prefix)
      @path = self.class.explicit_path(@explicit_path) || self.class.project_path
    end

    # A blank in any layer (RUNSHEETS_PORT="" say) coerces to nil; put the
    # bundled default back so an attribute is never accidentally unset.
    def fill_blanks_from_defaults
      self.class.bundled_defaults.each do |key, value|
        public_send(:"#{key}=", value) if public_send(key).nil?
      end
    end
  end
end
