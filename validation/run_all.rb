# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require_relative "build_fixture"

BENCHTRACK = File.expand_path("..", __dir__)
RESULTS    = File.expand_path("results", __dir__)
SEED       = 42

SCENARIOS = [
  { name: "no-change",      base: "v-base", head: "v-base",         expected: 0 },
  { name: "big-regression", base: "v-base", head: "big-regression", expected: 1 },
  { name: "small-slowdown", base: "v-base", head: "small-slowdown", expected: 0 }
].freeze

repo = BuildFixture.build
puts "fixture repo: #{repo}"

FileUtils.mkdir_p(RESULTS)

results = SCENARIOS.map do |scenario|
  json = File.join(repo, "#{scenario[:name]}.json")
  argv = [RbConfig.ruby, "-I", File.join(BENCHTRACK, "lib"),
          File.join(BENCHTRACK, "exe", "benchtrack"),
          "compare", scenario[:base], scenario[:head],
          "--suite", "bench/ips.rb", "--seed", SEED.to_s, "--json", json]

  puts "", "== #{scenario[:name]}: compare #{scenario[:base]} #{scenario[:head]} =="
  system(*argv, chdir: repo)
  got = $?.exitstatus

  unless got == scenario[:expected]
    warn "#{scenario[:name]}: expected exit #{scenario[:expected]}, got #{got.inspect}"
    warn "report left at #{json}" if File.exist?(json)
    exit 1
  end

  FileUtils.cp(json, File.join(RESULTS, "#{scenario[:name]}.json"))
  scenario.merge(got: got)
end

puts "", format("%-16s %8s  %3s", "scenario", "expected", "got")
results.each do |r|
  puts format("%-16s %8d  %3d", r[:name], r[:expected], r[:got])
end
puts "all scenarios passed; reports in #{RESULTS}"
