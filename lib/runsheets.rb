# frozen_string_literal: true

require "date"
require "json"
require "securerandom"
require "shellwords"
require "yaml"

require_relative "runsheets/version"

module Runsheets
  class Error < StandardError; end
  class RunbookError < Error; end
  class RunError < Error; end
end

require_relative "runsheets/front_matter"
require_relative "runsheets/fences"
require_relative "runsheets/block"
require_relative "runsheets/renderer"
require_relative "runsheets/step"
require_relative "runsheets/single_file"
require_relative "runsheets/runbook"
require_relative "runsheets/diff"
require_relative "runsheets/redactor"
require_relative "runsheets/execution"
require_relative "runsheets/executor"
require_relative "runsheets/run_record"
require_relative "runsheets/session"

# runsheets: executable runbooks served from a local web page.
#
# A runbook is a directory of markdown files (see Runbook). Fenced code blocks
# that opt in through their info string (see Block) can be executed from the
# browser; everything that happens during a run is captured into a RunRecord.
#
# The web layer (Web, Pages, Assets) and the command line (CLI) are loaded on
# demand so the model can be used without Sinatra.
module Runsheets
  DEFAULT_RUNS_DIR = File.join(Dir.home, ".local", "share", "runsheets", "runs")

  autoload :Assets, File.expand_path("runsheets/assets", __dir__)
  autoload :CLI,    File.expand_path("runsheets/cli", __dir__)
  autoload :Pages,  File.expand_path("runsheets/pages", __dir__)
  autoload :Web,    File.expand_path("runsheets/web", __dir__)

  class << self
    attr_writer :runs_dir

    # Where run records are written. Overridable with RUNSHEETS_RUNS_DIR.
    def runs_dir = @runs_dir || ENV["RUNSHEETS_RUNS_DIR"] || DEFAULT_RUNS_DIR
  end
end
