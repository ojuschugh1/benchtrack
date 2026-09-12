# frozen_string_literal: true

require "open3"
require "json"
require "tmpdir"
require "rbconfig"

module BenchTrack
  module SuiteRunner
    SHIM = File.expand_path("ips_capture.rb", __dir__)

    module_function

    def run_suite(suite_path, chdir:, env: {})
      unless File.file?(File.expand_path(suite_path, chdir))
        raise SuiteError, "suite file not found: #{suite_path}"
      end

      Dir.mktmpdir("benchtrack") do |tmp|
        result_path = File.join(tmp, "result.json")
        argv = [RbConfig.ruby]
        argv << "-rbundler/setup" if env.key?("BUNDLE_GEMFILE")
        argv.push("-r", SHIM, suite_path)
        out, status = Open3.capture2e(env.merge("BENCHTRACK_RESULT_PATH" => result_path),
                                      *argv, chdir: chdir)
        unless status.success?
          raise SuiteError, "suite exited with status #{status.exitstatus || status}:\n#{out}"
        end
        unless File.file?(result_path)
          raise SuiteError, "suite produced no result file (no Benchmark.ips call?)\nsuite output:\n#{out}"
        end
        parse_result(File.read(result_path), output: out)
      end
    end

    def bundler_env(dir, bundle_path: nil)
      gemfile = File.expand_path("Gemfile", dir)
      gemfile = ENV["BUNDLE_GEMFILE"] unless File.file?(gemfile)
      return {} if gemfile.nil? || gemfile.empty? || !File.file?(gemfile)

      env = { "BUNDLE_GEMFILE" => File.expand_path(gemfile) }
      env["BUNDLE_PATH"] = bundle_path if bundle_path
      env
    end

    def parse_result(text, output: "")
      suffix = output.empty? ? "" : "\nsuite output:\n#{output}"
      data = begin
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise SuiteError, "invalid benchmark result JSON: #{e.message}#{suffix}"
      end

      unless data.is_a?(Hash) && data["format"] == 1 && data["entries"].is_a?(Array)
        raise SuiteError, "unrecognized benchmark result format#{suffix}"
      end

      seen = {}
      data["entries"].map do |item|
        label = item.is_a?(Hash) ? item["label"] : nil
        ips   = item.is_a?(Hash) ? item["ips"] : nil
        unless label.is_a?(String) && !label.empty?
          raise SuiteError, "benchmark entry has a missing or empty label#{suffix}"
        end
        unless ips.is_a?(Numeric) && ips.to_f.finite? && ips.to_f.positive?
          raise SuiteError, "benchmark entry #{label.inspect} has invalid ips #{ips.inspect}#{suffix}"
        end
        raise SuiteError, "duplicate benchmark label #{label.inspect}#{suffix}" if seen[label]

        seen[label] = true
        Entry.new(label, ips.to_f)
      end
    end
  end
end
