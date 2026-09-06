# frozen_string_literal: true

require "etc"
require "json"
require "time"
require "rbconfig"

module BenchTrack
  module Report
    ROW_FORMAT = "%-26s%-12s%-21s%-10s%s"

    module_function

    def fingerprint(seed:, blocks:, lockfile_hashes:)
      {
        "cpu_model" => probe { cpu_model },
        "cpu_cores" => probe { Etc.nprocessors },
        "os" => probe { os_description },
        "kernel" => probe { "#{Etc.uname[:sysname]} #{Etc.uname[:release]}" },
        "ruby" => probe { RUBY_DESCRIPTION },
        "ruby_binary" => probe { RbConfig.ruby },
        "jit" => probe { jit_state },
        "lockfile_sha256" => lockfile_hashes,
        "seed" => seed,
        "blocks" => blocks,
        "timestamp" => probe { Time.now.utc.iso8601 },
        "benchtrack_version" => VERSION
      }
    end

    def terminal(comparison)
      config = comparison.config
      lines = [
        "benchtrack compare: #{comparison.base_ref} (#{comparison.base_sha.to_s[0, 7]}) " \
        "vs #{comparison.head_ref} (#{comparison.head_sha.to_s[0, 7]})",
        "blocks: #{config.blocks}   threshold: #{config.threshold_pct}%   " \
        "alpha: #{Stats::ALPHA}   seed: #{config.seed}",
        ""
      ]

      unless comparison.results.empty?
        lines << format(ROW_FORMAT, "label", "change", "95% CI", "holm p", "verdict")
        comparison.results.each { |result| lines << table_row(result) }
        lines << ""
      end

      unless comparison.base_only.empty?
        lines << "unmatched labels: base only: #{comparison.base_only.join(', ')}"
      end
      unless comparison.head_only.empty?
        lines << "unmatched labels: head only: #{comparison.head_only.join(', ')}"
      end
      lines << "no benchmark labels were paired; nothing was compared" if comparison.results.empty?
      lines << "overall: #{display_verdict(comparison.overall)}"
      lines.join("\n") + "\n"
    end

    def json(comparison)
      config = comparison.config
      report = {
        "benchtrack_version" => VERSION,
        "overall_verdict" => comparison.overall,
        "refs" => {
          "base" => comparison.base_ref,
          "head" => comparison.head_ref,
          "base_sha" => comparison.base_sha,
          "head_sha" => comparison.head_sha
        },
        "config" => { "threshold_pct" => config.threshold_pct, "alpha" => Stats::ALPHA },
        "entries" => comparison.results.map { |result| entry_hash(result) },
        "unmatched_labels" => {
          "base_only" => comparison.base_only,
          "head_only" => comparison.head_only
        },
        "environment" => comparison.fingerprint
      }
      JSON.generate(report)
    end

    def run_text(entries)
      width = entries.map { |entry| entry.label.length }.max || 0
      lines = entries.map { |entry| format("%-*s  %.1f i/s", width, entry.label, entry.ips) }
      lines.join("\n") + "\n"
    end

    def entry_hash(result)
      {
        "label" => result.label,
        "effect_log_ratio" => result.effect,
        "percent_change" => result.percent_change,
        "ci_log_ratio" => [result.ci_low, result.ci_high],
        "p_value" => result.p_value,
        "holm_p" => result.holm_p,
        "verdict" => result.verdict
      }
    end

    def table_row(result)
      low_pct = (Math.exp(result.ci_low) - 1) * 100
      high_pct = (Math.exp(result.ci_high) - 1) * 100
      format(ROW_FORMAT,
             result.label,
             format("%+.1f%%", result.percent_change),
             format("[%+.1f%%, %+.1f%%]", low_pct, high_pct),
             format("%.3f", result.holm_p),
             display_verdict(result.verdict))
    end

    def display_verdict(verdict)
      verdict == "fail" ? "FAIL" : verdict
    end

    def probe
      yield
    rescue StandardError
      "unknown"
    end

    def cpu_model
      if darwin?
        command_output("sysctl", "-n", "machdep.cpu.brand_string")
      else
        line = File.foreach("/proc/cpuinfo").find { |l| l.start_with?("model name") }
        line.split(":", 2).last.strip
      end
    end

    def os_description
      if darwin?
        "#{command_output('sw_vers', '-productName')} #{command_output('sw_vers', '-productVersion')}"
      else
        line = File.foreach("/etc/os-release").find { |l| l.start_with?("PRETTY_NAME=") }
        line.split("=", 2).last.strip.delete_prefix('"').delete_suffix('"')
      end
    end

    def jit_state
      return "yjit" if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
      return "rjit" if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
      return "mjit" if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled?
      "none"
    end

    def darwin?
      RUBY_PLATFORM.include?("darwin")
    end

    def command_output(*argv)
      output = IO.popen(argv, err: File::NULL, &:read).strip
      raise Error, "no output from #{argv.first}" if !$?.success? || output.empty?
      output
    end
  end
end
