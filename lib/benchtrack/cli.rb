# frozen_string_literal: true

require "optparse"

module BenchTrack
  class CLI
    EXIT_OK         = 0
    EXIT_REGRESSION = 1
    EXIT_ERROR      = 2

    USAGE = <<~TEXT
      usage: benchtrack <command> [options]

      commands:
        run SUITE_FILE
            run a benchmark-ips suite once and print each entry

        compare BASE HEAD --suite PATH [options]
            measure BASE vs HEAD and fail on supported regressions
              --suite PATH      benchmark-ips suite, relative to the repository root
              --blocks N        measurement blocks (default 10)
              --threshold PCT   practical slowdown threshold in percent (default 5.0)
              --seed N          integer seed for reproducible runs (default: generated)
              --json PATH       JSON report path (default benchtrack-report.json)
    TEXT

    def self.start(argv)
      case argv.first
      when "run"     then run(argv.drop(1))
      when "compare" then compare(argv.drop(1))
      else
        warn USAGE
        EXIT_ERROR
      end
    rescue OptionParser::ParseError => e
      warn "benchtrack: #{e.message}"
      EXIT_ERROR
    rescue Error => e
      warn "benchtrack: #{e.message}"
      EXIT_ERROR
    end

    def self.run(argv)
      suite = OptionParser.new.parse(argv).first
      raise ConfigError, "missing required argument: SUITE_FILE" unless suite

      entries = SuiteRunner.run_suite(suite, chdir: Dir.pwd, env: SuiteRunner.bundler_env(Dir.pwd))
      print Report.run_text(entries)
      EXIT_OK
    end

    def self.compare(argv)
      options = { threshold_pct: 5.0, blocks: 10, json_path: "benchtrack-report.json" }
      base, head = compare_parser(options).parse(argv)
      raise ConfigError, "missing required argument: BASE" unless base
      raise ConfigError, "missing required argument: HEAD" unless head
      raise ConfigError, "missing required option: --suite" unless options[:suite]

      config = Config.new(command: "compare", suite: options[:suite], base: base, head: head,
                          threshold_pct: options[:threshold_pct], blocks: options[:blocks],
                          seed: options[:seed] || Random.new_seed % (2**32),
                          json_path: options[:json_path])

      comparison = Orchestrator.compare(config)
      print Report.terminal(comparison)
      write_report(Report.json(comparison), config.json_path)
      comparison.overall == "fail" ? EXIT_REGRESSION : EXIT_OK
    end

    def self.compare_parser(options)
      OptionParser.new do |o|
        o.on("--suite PATH")    { |v| options[:suite] = v }
        o.on("--blocks N")      { |v| options[:blocks] = parse_blocks(v) }
        o.on("--threshold PCT") { |v| options[:threshold_pct] = parse_threshold(v) }
        o.on("--seed N")        { |v| options[:seed] = parse_seed(v) }
        o.on("--json PATH")     { |v| options[:json_path] = v }
      end
    end

    def self.parse_blocks(value)
      blocks = begin
        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end
      raise ConfigError, "invalid blocks: #{value} (must be an integer >= 1)" if blocks.nil? || blocks < 1

      blocks
    end

    def self.parse_threshold(value)
      threshold = begin
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end
      if threshold.nil? || !threshold.finite? || threshold <= 0
        raise ConfigError, "invalid threshold: #{value} (must be a number greater than zero)"
      end

      threshold
    end

    def self.parse_seed(value)
      Integer(value)
    rescue ArgumentError, TypeError
      raise ConfigError, "invalid seed: #{value} (must be an integer)"
    end

    def self.write_report(json, path)
      File.write(path, json)
    rescue SystemCallError, IOError => e
      raise Error, "cannot write JSON report to #{path}: #{e.message}"
    end
  end
end
