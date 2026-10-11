# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "runsheets"
require "runsheets/web"

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

# Shared fixtures and assertion helpers, one file per area of the suite.
Dir[File.join(__dir__, "support", "**", "*.rb")].each { require it }

module RunsheetsTest
  # Stands in for the End session stopper: counts the calls.
  StopCounter = Struct.new(:calls) do
    def call = self.calls += 1
  end

  EXAMPLE_DIR = File.expand_path("../examples/hello", __dir__)

  def example_runbook = Runsheets::Runbook.load(EXAMPLE_DIR)

  def with_runs_dir
    Dir.mktmpdir("runsheets-test") { yield it }
  end

  # A session for tests: a fixed engineer and why, no terminal echo, the
  # token "tok", and +runbook+ on screen (the hello example by default).
  def start_session(root, runbook: example_runbook, **)
    Runsheets::Session.new(engineer: "Tester", why: "testing", runs_root: root, runbook:, token: "tok", echo: nil, **)
  end

  # A session with its runbook's run already open, given +inputs+.
  def open_session(root, runbook: example_runbook, inputs: {}, **)
    session = start_session(root, runbook:, **)
    session.open(runbook, inputs:)
    session
  end

  # Run the block with ENV changed (nil removes a variable), then restore it.
  def with_env(changes)
    saved = changes.keys.to_h { [it, ENV.fetch(it, nil)] }
    changes.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # The RUNSHEETS_* variables, cleared, so a developer's shell cannot leak in.
  CLEAR_RUNSHEETS_ENV = ENV.keys.grep(/\ARUNSHEETS_/).to_h { [it, nil] }.freeze

  # A clean home: no user config files, a throwaway default runs dir, no
  # RUNSHEETS_* variables, and Runsheets.config rebuilt afterwards.
  def with_clean_home
    Dir.mktmpdir("runsheets-home") do |home|
      with_env(CLEAR_RUNSHEETS_ENV.merge("HOME" => home, "XDG_CONFIG_HOME" => nil)) do
        Runsheets.reset_config!
        yield home
      end
    end
  ensure
    Runsheets.reset_config!
  end

  def write_yaml(path, hash)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, hash.transform_keys(&:to_s).to_yaml)
    path
  end

  # A minimal runbook directory built from a hash of relative path => text.
  def with_runbook(files)
    Dir.mktmpdir("runsheets-rb") do |dir|
      files.each do |rel, text|
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
      end
      yield Runsheets::Runbook.load(dir)
    end
  end

  def wait_for(limit = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    until yield
      raise "timed out waiting" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end
  end
end
