# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "runsheets"
require "runsheets/web"

require "minitest/autorun"
require "tmpdir"

module RunsheetsTest
  EXAMPLE_DIR = File.expand_path("../examples/hello", __dir__)

  def example_runbook = Runsheets::Runbook.load(EXAMPLE_DIR)

  def with_runs_dir
    Dir.mktmpdir("runsheets-test") { yield it }
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
