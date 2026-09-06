# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "benchtrack"

class SuiteRunnerParseResultTest < Minitest::Test
  def test_well_formed_result_preserves_labels_and_ips_in_order
    text = JSON.generate(
      "format" => 1,
      "entries" => [
        { "label" => "parse small", "ips" => 1234.5 },
        { "label" => "parse big", "ips" => 67.89 },
        { "label" => "encode utf8", "ips" => 0.25 }
      ]
    )
    entries = BenchTrack::SuiteRunner.parse_result(text)
    assert_equal ["parse small", "parse big", "encode utf8"], entries.map(&:label)
    assert_equal [1234.5, 67.89, 0.25], entries.map(&:ips)
  end

  def test_duplicate_labels_keep_last_ips_at_first_position
    text = JSON.generate(
      "format" => 1,
      "entries" => [
        { "label" => "a", "ips" => 1.0 },
        { "label" => "b", "ips" => 2.0 },
        { "label" => "a", "ips" => 9.0 }
      ]
    )
    entries = BenchTrack::SuiteRunner.parse_result(text)
    assert_equal [["a", 9.0], ["b", 2.0]], entries.map { |e| [e.label, e.ips] }
  end

  def test_invalid_json_raises_suite_error
    error = assert_raises(BenchTrack::SuiteError) do
      BenchTrack::SuiteRunner.parse_result("not json {")
    end
    assert_match(/invalid benchmark result JSON/, error.message)
  end

  def test_document_without_format_marker_raises_suite_error
    error = assert_raises(BenchTrack::SuiteError) do
      BenchTrack::SuiteRunner.parse_result(JSON.generate("entries" => []))
    end
    assert_match(/unrecognized benchmark result format/, error.message)
  end

  def test_unknown_format_version_raises_suite_error
    assert_raises(BenchTrack::SuiteError) do
      BenchTrack::SuiteRunner.parse_result(JSON.generate("format" => 2, "entries" => []))
    end
  end

  def test_non_array_entries_raises_suite_error
    assert_raises(BenchTrack::SuiteError) do
      BenchTrack::SuiteRunner.parse_result(JSON.generate("format" => 1, "entries" => {}))
    end
  end

  def test_empty_label_raises_suite_error
    error = assert_raises(BenchTrack::SuiteError) { parse_single("", 1.0) }
    assert_match(/missing or empty label/, error.message)
  end

  def test_non_string_label_raises_suite_error
    assert_raises(BenchTrack::SuiteError) { parse_single(7, 1.0) }
  end

  def test_zero_ips_raises_suite_error
    error = assert_raises(BenchTrack::SuiteError) { parse_single("bench", 0) }
    assert_match(/invalid ips/, error.message)
  end

  def test_negative_ips_raises_suite_error
    assert_raises(BenchTrack::SuiteError) { parse_single("bench", -3.5) }
  end

  def test_null_ips_raises_suite_error
    assert_raises(BenchTrack::SuiteError) { parse_single("bench", nil) }
  end

  def test_string_ips_raises_suite_error
    assert_raises(BenchTrack::SuiteError) { parse_single("bench", "Infinity") }
  end

  def test_missing_suite_file_raises_suite_error_naming_the_path
    Dir.mktmpdir do |dir|
      error = assert_raises(BenchTrack::SuiteError) do
        BenchTrack::SuiteRunner.run_suite("no_such_suite.rb", chdir: dir)
      end
      assert_includes error.message, "no_such_suite.rb"
    end
  end

  def test_parse_error_message_includes_captured_output
    error = assert_raises(BenchTrack::SuiteError) do
      BenchTrack::SuiteRunner.parse_result("not json {", output: "boom")
    end
    assert_includes error.message, "boom"
  end

  private

  def parse_single(label, ips)
    BenchTrack::SuiteRunner.parse_result(
      JSON.generate("format" => 1, "entries" => [{ "label" => label, "ips" => ips }])
    )
  end
end

class MeasurementTest < Minitest::Test
  def test_collect_runs_each_side_exactly_once_per_block
    order = []
    runs = BenchTrack::Measurement.collect(blocks: 8, rng: Random.new(42)) do |side|
      order << side
      [BenchTrack::Entry.new("bench", 1.0)]
    end

    assert_equal 16, order.length
    8.times do |i|
      assert_equal({ base: 1, head: 1 }, order[2 * i, 2].tally,
                   "block #{i} should contain exactly one base and one head invocation")
    end
    assert_equal 8, runs[:base].length
    assert_equal 8, runs[:head].length
  end

  def test_collect_order_is_deterministic_for_a_fixed_seed
    assert_equal collect_order(seed: 42), collect_order(seed: 42)
    refute_equal collect_order(seed: 42), collect_order(seed: 43)
  end

  def test_pair_partitions_labels_into_series_and_per_side_leftovers
    base_runs = [entries("a" => 1.0, "b" => 2.0, "c" => 3.0),
                 entries("a" => 1.1, "b" => 2.1, "c" => 3.1)]
    head_runs = [entries("b" => 4.0, "c" => 5.0, "d" => 6.0),
                 entries("b" => 4.1, "c" => 5.1, "d" => 6.1)]

    pairing = BenchTrack::Measurement.pair(base_runs, head_runs)

    assert_equal %w[b c], pairing.series.map(&:label)
    assert_equal %w[a], pairing.base_only
    assert_equal %w[d], pairing.head_only
  end

  def test_pair_aligns_values_by_block_position_regardless_of_entry_order
    base_runs = [entries("x" => 10.0, "b" => 100.0),
                 entries("b" => 101.0, "x" => 11.0),
                 entries("x" => 12.0, "b" => 102.0)]
    head_runs = [entries("b" => 200.0, "x" => 20.0),
                 entries("x" => 21.0, "b" => 201.0),
                 entries("b" => 202.0, "x" => 22.0)]

    pairing = BenchTrack::Measurement.pair(base_runs, head_runs)

    series = pairing.series.find { |s| s.label == "b" }
    assert_equal [100.0, 101.0, 102.0], series.base
    assert_equal [200.0, 201.0, 202.0], series.head
  end

  def test_pair_rejects_inconsistent_base_labels_naming_side_and_labels
    base_runs = [entries("a" => 1.0, "b" => 2.0), entries("a" => 1.1)]
    head_runs = [entries("a" => 3.0), entries("a" => 3.1)]

    error = assert_raises(BenchTrack::SuiteError) do
      BenchTrack::Measurement.pair(base_runs, head_runs)
    end
    assert_includes error.message, "base"
    assert_includes error.message, "b"
  end

  def test_pair_rejects_inconsistent_head_labels_naming_side_and_labels
    base_runs = [entries("a" => 1.0), entries("a" => 1.1)]
    head_runs = [entries("a" => 3.0, "b" => 4.0), entries("a" => 3.1)]

    error = assert_raises(BenchTrack::SuiteError) do
      BenchTrack::Measurement.pair(base_runs, head_runs)
    end
    assert_includes error.message, "head"
    assert_includes error.message, "b"
  end

  private

  def collect_order(seed:)
    order = []
    BenchTrack::Measurement.collect(blocks: 8, rng: Random.new(seed)) do |side|
      order << side
      [BenchTrack::Entry.new("bench", 1.0)]
    end
    order
  end

  def entries(labels_to_ips)
    labels_to_ips.map { |label, ips| BenchTrack::Entry.new(label, ips) }
  end
end

class ReportJsonTest < Minitest::Test
  ENTRY_KEYS = %w[label effect_log_ratio percent_change ci_log_ratio p_value holm_p verdict].freeze
  FINGERPRINT_KEYS = %w[cpu_model cpu_cores os kernel ruby ruby_binary jit
                        lockfile_sha256 seed blocks timestamp benchtrack_version].freeze
  UNMATCHED_VARIANTS = [[], ["dropped bench"], ["left bench", "right bench"]].freeze

  def test_json_round_trips_generated_comparisons_through_json_parse
    rng = Random.new(20260211)

    (0..3).each do |count|
      results = Array.new(count) { |i| random_result(rng, i) }
      comparison = make_comparison(
        results: results,
        base_only: UNMATCHED_VARIANTS[count % 3],
        head_only: UNMATCHED_VARIANTS[(count + 1) % 3],
        overall: count.even? ? "pass" : "fail",
        fingerprint: count.odd? ? unknown_fingerprint : nil
      )

      parsed = JSON.parse(BenchTrack::Report.json(comparison))
      context = "comparison: #{comparison.to_h.inspect}"

      assert_equal comparison.overall, parsed["overall_verdict"], context
      assert_equal comparison.base_ref, parsed.dig("refs", "base"), context
      assert_equal comparison.head_ref, parsed.dig("refs", "head"), context
      assert_equal comparison.base_sha, parsed.dig("refs", "base_sha"), context
      assert_equal comparison.head_sha, parsed.dig("refs", "head_sha"), context
      assert_equal comparison.config.threshold_pct, parsed.dig("config", "threshold_pct"), context
      assert_equal BenchTrack::Stats::ALPHA, parsed.dig("config", "alpha"), context
      assert_equal comparison.base_only, parsed.dig("unmatched_labels", "base_only"), context
      assert_equal comparison.head_only, parsed.dig("unmatched_labels", "head_only"), context
      assert_equal comparison.fingerprint, parsed["environment"], context

      assert_equal count, parsed["entries"].length, context
      results.zip(parsed["entries"]).each do |result, entry|
        assert_equal result.label, entry["label"], context
        assert_equal result.effect, entry["effect_log_ratio"], context
        assert_equal result.percent_change, entry["percent_change"], context
        assert_equal [result.ci_low, result.ci_high], entry["ci_log_ratio"], context
        assert_equal result.p_value, entry["p_value"], context
        assert_equal result.holm_p, entry["holm_p"], context
        assert_equal result.verdict, entry["verdict"], context
      end
    end
  end

  def test_every_parsed_entry_contains_all_report_fields
    rng = Random.new(7)
    results = Array.new(3) { |i| random_result(rng, i) }
    comparison = make_comparison(results: results, overall: "fail")

    parsed = JSON.parse(BenchTrack::Report.json(comparison))

    assert_equal 3, parsed["entries"].length
    parsed["entries"].each do |entry|
      ENTRY_KEYS.each do |key|
        assert entry.key?(key), "entry #{entry.inspect} is missing key #{key}"
      end
    end
  end

  def test_parsed_environment_contains_every_fingerprint_key
    comparison = make_comparison(results: [], overall: "pass")

    environment = JSON.parse(BenchTrack::Report.json(comparison))["environment"]

    FINGERPRINT_KEYS.each do |key|
      assert environment.key?(key), "environment #{environment.inspect} is missing key #{key}"
    end
  end

  def test_non_trivial_float_values_round_trip_exactly
    effect = 0.0034521
    result = BenchTrack::EntryResult.new(
      label: "parse small",
      effect: effect,
      ci_low: -0.083121,
      ci_high: 0.0912345678,
      p_value: 0.001953125,
      holm_p: 0.005859375,
      percent_change: (Math.exp(effect) - 1) * 100,
      slowdown_pct: (1 - Math.exp(effect)) * 100,
      verdict: "pass"
    )
    comparison = make_comparison(results: [result], overall: "pass")

    entry = JSON.parse(BenchTrack::Report.json(comparison))["entries"].fetch(0)

    assert_equal 0.0034521, entry["effect_log_ratio"], "source result: #{result.to_h.inspect}"
    assert_equal(-0.083121, entry["ci_log_ratio"][0], "source result: #{result.to_h.inspect}")
    assert_equal 0.0912345678, entry["ci_log_ratio"][1], "source result: #{result.to_h.inspect}"
    assert_equal 0.001953125, entry["p_value"], "source result: #{result.to_h.inspect}"
    assert_equal 0.005859375, entry["holm_p"], "source result: #{result.to_h.inspect}"
    assert_equal result.percent_change, entry["percent_change"], "source result: #{result.to_h.inspect}"
  end

  private

  def make_comparison(results:, base_only: [], head_only: [], overall:, fingerprint: nil)
    config = BenchTrack::Config.new(
      command: "compare", suite: "bench/suite.rb", base: "v-base", head: "feature",
      threshold_pct: 5.0, blocks: 10, seed: 123_456_789, json_path: "benchtrack-report.json"
    )
    fingerprint ||= BenchTrack::Report.fingerprint(
      seed: config.seed, blocks: config.blocks,
      lockfile_hashes: { "base" => "unknown", "head" => "unknown" }
    )
    BenchTrack::Comparison.new(
      base_ref: config.base, head_ref: config.head,
      base_sha: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678",
      head_sha: "0f1e2d3c4b5a69788796a5b4c3d2e1f012345678",
      results: results, base_only: base_only, head_only: head_only,
      overall: overall, fingerprint: fingerprint, config: config
    )
  end

  def unknown_fingerprint
    {
      "cpu_model" => "unknown", "cpu_cores" => "unknown", "os" => "unknown",
      "kernel" => "unknown", "ruby" => RUBY_DESCRIPTION, "ruby_binary" => "unknown",
      "jit" => "unknown",
      "lockfile_sha256" => { "base" => "unknown", "head" => "unknown" },
      "seed" => 123_456_789, "blocks" => 10, "timestamp" => "unknown",
      "benchtrack_version" => BenchTrack::VERSION
    }
  end

  def random_result(rng, index)
    effect = (rng.rand * 0.2) - 0.1
    half_width = rng.rand * 0.05
    p_value = rng.rand
    BenchTrack::EntryResult.new(
      label: "bench #{index}",
      effect: effect,
      ci_low: effect - half_width,
      ci_high: effect + half_width,
      p_value: p_value,
      holm_p: [p_value * (index + 1), 1.0].min,
      percent_change: (Math.exp(effect) - 1) * 100,
      slowdown_pct: (1 - Math.exp(effect)) * 100,
      verdict: index.even? ? "pass" : "fail"
    )
  end
end
