# frozen_string_literal: true

require_relative "benchtrack/version"

module BenchTrack
  Error       = Class.new(StandardError)
  ConfigError = Class.new(Error)
  SuiteError  = Class.new(Error)
  GitError    = Class.new(Error)
  BundleError = Class.new(Error)

  Entry        = Struct.new(:label, :ips)
  Config       = Struct.new(:command, :suite, :base, :head, :threshold_pct,
                            :blocks, :seed, :json_path, keyword_init: true)
  PairedSeries = Struct.new(:label, :base, :head)
  EntryResult  = Struct.new(:label, :effect, :ci_low, :ci_high, :p_value, :holm_p,
                            :percent_change, :slowdown_pct, :verdict, keyword_init: true)
  Comparison   = Struct.new(:base_ref, :head_ref, :base_sha, :head_sha, :results,
                            :base_only, :head_only, :overall, :fingerprint, :config,
                            keyword_init: true)
end

require_relative "benchtrack/cli"
require_relative "benchtrack/suite_runner"
require_relative "benchtrack/orchestrator"
require_relative "benchtrack/measurement"
require_relative "benchtrack/stats"
require_relative "benchtrack/report"
