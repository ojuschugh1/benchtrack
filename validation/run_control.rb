# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require_relative "build_fixture"

runs = (ARGV[0] || "30").to_i
abort "run count must be >= 1, got #{ARGV[0].inspect}" if runs < 1

benchtrack = File.expand_path("..", __dir__)
results_dir = File.expand_path("results/control", __dir__)
FileUtils.mkdir_p(results_dir)

repo = BuildFixture.build
puts "fixture repo: #{repo}"

width = [2, runs.to_s.size].max
failures = 0

runs.times do |i|
  seed = 1000 + i
  json = File.join(results_dir, format("run-%0*d.json", width, i + 1))
  out, status = Open3.capture2e(
    RbConfig.ruby, "-I", File.join(benchtrack, "lib"),
    File.join(benchtrack, "exe", "benchtrack"),
    "compare", "v-base", "v-base",
    "--suite", "bench/ips.rb",
    "--seed", seed.to_s,
    "--json", json,
    chdir: repo
  )
  case status.exitstatus
  when 0
    verdict = "pass"
  when 1
    verdict = "FAIL"
    failures += 1
  else
    abort "run #{i + 1} errored (exit #{status.exitstatus}):\n#{out}"
  end
  puts format("run %*d/%d  seed %d  %s", width, i + 1, runs, seed, verdict)
end

puts format("false positives: %d/%d (%.1f%%)", failures, runs, 100.0 * failures / runs)
