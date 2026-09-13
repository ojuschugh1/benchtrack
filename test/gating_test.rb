# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "benchtrack"

class GatingTest < Minitest::Test
  RNG_SEED = 20260214

  def test_verdict_covers_all_four_quadrants_of_threshold_and_significance
    threshold = 5.0
    assert_equal "fail", BenchTrack::Stats.verdict(10.0, 0.01, threshold)
    assert_equal "pass", BenchTrack::Stats.verdict(10.0, 0.5, threshold)
    assert_equal "pass", BenchTrack::Stats.verdict(1.0, 0.01, threshold)
    assert_equal "pass", BenchTrack::Stats.verdict(1.0, 0.5, threshold)
  end

  def test_verdict_boundary_equalities_pass
    assert_equal "pass", BenchTrack::Stats.verdict(5.0, 0.01, 5.0)
    assert_equal "pass", BenchTrack::Stats.verdict(10.0, BenchTrack::Stats::ALPHA, 5.0)
    assert_equal "pass", BenchTrack::Stats.verdict(5.0, BenchTrack::Stats::ALPHA, 5.0)
  end

  def test_verdict_matches_gating_rule_on_randomized_triples
    rng = Random.new(RNG_SEED)
    200.times do
      slowdown = rng.rand(-50.0..50.0)
      holm_p = rng.rand
      threshold = rng.rand(0.1..20.0)
      expected = slowdown > threshold && holm_p < BenchTrack::Stats::ALPHA ? "fail" : "pass"
      assert_equal expected, BenchTrack::Stats.verdict(slowdown, holm_p, threshold),
                   "slowdown=#{slowdown} holm_p=#{holm_p} threshold=#{threshold}"
    end
  end

  def test_verdict_never_fails_for_speedups
    [-0.001, -0.5, -5.0, -50.0, -400.0].each do |slowdown|
      assert_equal "pass", BenchTrack::Stats.verdict(slowdown, 1e-9, 5.0), "slowdown=#{slowdown}"
      assert_equal "pass", BenchTrack::Stats.verdict(slowdown, 0.0, 5.0), "slowdown=#{slowdown}"
    end
  end

  def test_analyze_passes_significant_speedups
    [1.1, 2.0, 10.0].each do |factor|
      base = Array.new(10) { 100.0 }
      head = base.map { |b| b * factor }
      series = BenchTrack::PairedSeries.new("speedup", base, head)
      result = BenchTrack::Stats.analyze([series], seed: RNG_SEED, threshold_pct: 5.0).first
      assert_operator result.slowdown_pct, :<, 0.0, "factor=#{factor}"
      assert_operator result.holm_p, :<, BenchTrack::Stats::ALPHA, "factor=#{factor}"
      assert_equal "pass", result.verdict, "factor=#{factor}"
    end
  end

  def test_analyze_gates_large_deterministic_regression_and_passes_unchanged_entry
    base = Array.new(10) { |i| 100.0 + i }
    regression = BenchTrack::PairedSeries.new("regressed", base, base.map { |b| b * 0.5 })
    unchanged = BenchTrack::PairedSeries.new("unchanged", base.dup, base.dup)
    results = BenchTrack::Stats.analyze([regression, unchanged],
                                        seed: RNG_SEED, threshold_pct: 5.0)

    regressed = results.find { |r| r.label == "regressed" }
    assert_in_delta 50.0, regressed.slowdown_pct, 1e-9
    assert_equal 2.fdiv(2**10), regressed.p_value
    assert_operator regressed.holm_p, :<, BenchTrack::Stats::ALPHA
    assert_equal "fail", regressed.verdict

    clean = results.find { |r| r.label == "unchanged" }
    assert_in_delta 0.0, clean.slowdown_pct, 1e-12
    assert_equal 1.0, clean.p_value
    assert_equal "pass", clean.verdict
  end

  def test_exit_status_constants_match_contract
    assert_equal 0, BenchTrack::CLI::EXIT_OK
    assert_equal 1, BenchTrack::CLI::EXIT_REGRESSION
    assert_equal 2, BenchTrack::CLI::EXIT_ERROR
  end

  def test_compare_maps_overall_fail_to_regression_exit_status
    comparison = fake_comparison(overall: "fail", verdicts: %w[pass fail pass])
    status, json_written = run_compare_with_stub(comparison)
    assert_equal BenchTrack::CLI::EXIT_REGRESSION, status
    assert json_written
  end

  def test_compare_maps_overall_pass_to_ok_exit_status
    comparison = fake_comparison(overall: "pass", verdicts: %w[pass pass])
    status, json_written = run_compare_with_stub(comparison)
    assert_equal BenchTrack::CLI::EXIT_OK, status
    assert json_written
  end

  private

  def run_compare_with_stub(comparison)
    Dir.mktmpdir do |tmp|
      json_path = File.join(tmp, "report.json")
      status = nil
      with_orchestrator_returning(comparison) do
        capture_io do
          status = BenchTrack::CLI.start(
            ["compare", "v-base", "feature", "--suite", "bench/ips.rb", "--json", json_path]
          )
        end
      end
      return status, File.exist?(json_path)
    end
  end

  def with_orchestrator_returning(comparison)
    singleton = BenchTrack::Orchestrator.singleton_class
    singleton.send(:alias_method, :__gating_test_compare, :compare)
    singleton.send(:remove_method, :compare)
    BenchTrack::Orchestrator.define_singleton_method(:compare) { |_config| comparison }
    yield
  ensure
    singleton.send(:remove_method, :compare)
    singleton.send(:alias_method, :compare, :__gating_test_compare)
    singleton.send(:remove_method, :__gating_test_compare)
  end

  def fake_comparison(overall:, verdicts:)
    results = verdicts.each_with_index.map do |verdict, i|
      BenchTrack::EntryResult.new(
        label: "entry #{i}", effect: 0.01, ci_low: -0.02, ci_high: 0.04,
        p_value: 0.4, holm_p: 0.4, percent_change: 1.0, slowdown_pct: -1.0,
        verdict: verdict
      )
    end
    config = BenchTrack::Config.new(command: "compare", suite: "bench/ips.rb",
                                    base: "v-base", head: "feature",
                                    threshold_pct: 5.0, blocks: 10, seed: 1,
                                    json_path: "unused.json")
    BenchTrack::Comparison.new(
      base_ref: "v-base", head_ref: "feature",
      base_sha: "a" * 40, head_sha: "b" * 40,
      results: results, base_only: [], head_only: [],
      overall: overall,
      fingerprint: BenchTrack::Report.fingerprint(
        seed: 1, blocks: 10, lockfile_hashes: { "base" => "unknown", "head" => "unknown" }
      ),
      config: config
    )
  end
end
