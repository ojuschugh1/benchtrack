# frozen_string_literal: true

require "minitest/autorun"
require "benchtrack"

class StatsTest < Minitest::Test
  RNG_SEED = 20260214

  def brute_force_pvalue(xs)
    sums = [1.0, -1.0].repeated_permutation(xs.length).map do |signs|
      signs.each_with_index.inject(0.0) { |acc, (sign, i)| acc + sign * xs[i] }
    end
    observed = sums.first.abs
    sums.count { |sum| sum.abs >= observed }.fdiv(2**xs.length)
  end

  def holm_oracle(pvalues)
    m = pvalues.length
    sorted = pvalues.sort
    pvalues.map do |p|
      rank = sorted.rindex(p)
      adjusted = (0..rank).map { |j| (m - j) * sorted[j] }.max
      [adjusted, 1.0].min
    end
  end

  def random_series(rng, label, blocks)
    base = Array.new(blocks) { 100.0 + rng.rand * 100.0 }
    head = base.map { |b| b * (0.8 + rng.rand * 0.45) }
    BenchTrack::PairedSeries.new(label, base, head)
  end

  def test_log_ratios_match_independent_recomputation
    rng = Random.new(RNG_SEED)
    100.times do
      blocks = 1 + rng.rand(12)
      series = random_series(rng, "entry", blocks)
      got = BenchTrack::Stats.log_ratios(series)
      assert_equal blocks, got.length, "series=#{series.inspect}"
      got.each_with_index do |ratio, i|
        expected = Math.log(series.head[i]) - Math.log(series.base[i])
        assert_in_delta expected, ratio, 1e-12, "block #{i} series=#{series.inspect}"
      end
    end
  end

  def test_analyze_effect_equals_mean_of_recomputed_log_ratios
    rng = Random.new(RNG_SEED)
    20.times do
      blocks = 2 + rng.rand(10)
      series_list = [random_series(rng, "alpha", blocks),
                     random_series(rng, "beta", blocks)]
      results = BenchTrack::Stats.analyze(series_list, seed: rng.rand(2**32),
                                                       threshold_pct: 5.0)
      series_list.each do |series|
        result = results.find { |r| r.label == series.label }
        logs = series.base.zip(series.head).map { |b, h| Math.log(h) - Math.log(b) }
        expected = logs.inject(0.0, :+) / logs.length
        assert_in_delta expected, result.effect, 1e-12, "series=#{series.inspect}"
      end
    end
  end

  def test_permutation_pvalue_matches_brute_force_oracle_for_small_n
    rng = Random.new(RNG_SEED)
    100.times do
      n = 1 + rng.rand(8)
      xs = Array.new(n) { rng.rand * 2.0 - 1.0 }
      got = BenchTrack::Stats.permutation_pvalue(xs, Random.new(rng.rand(2**32)))
      assert_equal brute_force_pvalue(xs), got, "xs=#{xs.inspect}"
      assert_operator got, :>, 0.0, "xs=#{xs.inspect}"
      assert_operator got, :<=, 1.0, "xs=#{xs.inspect}"
    end
  end

  def test_permutation_pvalue_hand_enumerated_three_block_case
    p = BenchTrack::Stats.permutation_pvalue([1.0, 2.0, 3.0], Random.new(1))
    assert_equal 0.25, p
  end

  def test_permutation_pvalue_sign_symmetric_on_enumeration_path
    rng = Random.new(RNG_SEED)
    50.times do
      n = 1 + rng.rand(12)
      xs = Array.new(n) { rng.rand * 2.0 - 1.0 }
      seed = rng.rand(2**32)
      p_pos = BenchTrack::Stats.permutation_pvalue(xs, Random.new(seed))
      p_neg = BenchTrack::Stats.permutation_pvalue(xs.map(&:-@), Random.new(seed))
      assert_equal p_pos, p_neg, "xs=#{xs.inspect}"
    end
  end

  def test_permutation_pvalue_sign_symmetric_on_monte_carlo_path
    rng = Random.new(RNG_SEED)
    5.times do
      xs = Array.new(25) { rng.rand * 2.0 - 1.0 }
      seed = rng.rand(2**32)
      p_pos = BenchTrack::Stats.permutation_pvalue(xs, Random.new(seed))
      p_neg = BenchTrack::Stats.permutation_pvalue(xs.map(&:-@), Random.new(seed))
      assert_equal p_pos, p_neg, "xs=#{xs.inspect}"
      assert_operator p_pos, :>, 0.0, "xs=#{xs.inspect}"
      assert_operator p_pos, :<=, 1.0, "xs=#{xs.inspect}"
    end
  end

  def test_monte_carlo_pvalue_deterministic_for_fixed_seed
    rng = Random.new(RNG_SEED)
    xs = Array.new(25) { rng.rand * 2.0 - 1.0 }
    first = BenchTrack::Stats.permutation_pvalue(xs, Random.new(424_242))
    second = BenchTrack::Stats.permutation_pvalue(xs, Random.new(424_242))
    assert_equal first, second, "xs=#{xs.inspect}"
  end

  def test_monte_carlo_pvalue_within_tolerance_of_exact_answer
    xs = [0.7] + Array.new(24, 0.0)
    p = BenchTrack::Stats.permutation_pvalue(xs, Random.new(7))
    assert_in_delta 1.0, p, 1e-12

    xs = Array.new(25) { |i| 0.5 + i * 0.01 }
    p = BenchTrack::Stats.permutation_pvalue(xs, Random.new(7))
    assert_in_delta 2.0 / 2**25, p, 0.001
  end

  def test_bootstrap_ci_invariants_on_randomized_input
    rng = Random.new(RNG_SEED)
    30.times do
      n = 1 + rng.rand(12)
      xs = Array.new(n) { rng.rand * 2.0 - 1.0 }
      lo, hi = BenchTrack::Stats.bootstrap_ci(xs, Random.new(rng.rand(2**32)))
      assert_operator lo, :<=, hi, "xs=#{xs.inspect}"
      assert_operator lo, :>=, xs.min - 1e-12, "xs=#{xs.inspect}"
      assert_operator hi, :<=, xs.max + 1e-12, "xs=#{xs.inspect}"
    end
  end

  def test_bootstrap_ci_degenerate_on_constant_input
    rng = Random.new(RNG_SEED)
    10.times do
      constant = rng.rand * 2.0 - 1.0
      n = 2 + rng.rand(10)
      lo, hi = BenchTrack::Stats.bootstrap_ci(Array.new(n, constant),
                                              Random.new(rng.rand(2**32)))
      assert_equal lo, hi, "constant=#{constant} n=#{n}"
      assert_in_delta constant, lo, 1e-9, "constant=#{constant} n=#{n}"
    end
  end

  def test_bootstrap_ci_deterministic_for_fixed_seed
    rng = Random.new(RNG_SEED)
    5.times do
      xs = Array.new(10) { rng.rand * 2.0 - 1.0 }
      seed = rng.rand(2**32)
      assert_equal BenchTrack::Stats.bootstrap_ci(xs, Random.new(seed)),
                   BenchTrack::Stats.bootstrap_ci(xs, Random.new(seed)),
                   "xs=#{xs.inspect}"
    end
  end

  def test_holm_matches_textbook_stepdown_vector
    got = BenchTrack::Stats.holm([0.01, 0.04, 0.03])
    [0.03, 0.06, 0.06].zip(got).each do |expected, actual|
      assert_in_delta expected, actual, 1e-12
    end
  end

  def test_holm_matches_direct_formula_on_randomized_vectors
    rng = Random.new(RNG_SEED)
    100.times do
      m = 1 + rng.rand(8)
      pvalues = Array.new(m) { rng.rand(0.001..1.0) }
      got = BenchTrack::Stats.holm(pvalues)
      holm_oracle(pvalues).zip(got).each_with_index do |(expected, actual), i|
        assert_in_delta expected, actual, 1e-12, "index #{i} pvalues=#{pvalues.inspect}"
      end
    end
  end

  def test_holm_adjusted_values_dominate_raw_and_cap_at_one
    rng = Random.new(RNG_SEED)
    100.times do
      m = 2 + rng.rand(7)
      pvalues = Array.new(m) { rng.rand(0.001..1.0) }
      adjusted = BenchTrack::Stats.holm(pvalues)
      pvalues.zip(adjusted).each do |raw, adj|
        assert_operator adj, :>=, raw, "pvalues=#{pvalues.inspect}"
        assert_operator adj, :<=, 1.0, "pvalues=#{pvalues.inspect}"
      end
    end
  end

  def test_holm_caps_adjusted_values_at_one
    assert_equal [1.0, 1.0, 1.0], BenchTrack::Stats.holm([0.9, 0.8, 0.7])
  end

  def test_holm_preserves_raw_pvalue_ordering
    rng = Random.new(RNG_SEED)
    100.times do
      m = 2 + rng.rand(7)
      pvalues = Array.new(m) { rng.rand(0.001..1.0) }
      adjusted = BenchTrack::Stats.holm(pvalues)
      pvalues.each_index do |i|
        pvalues.each_index do |j|
          next unless pvalues[i] <= pvalues[j]

          assert_operator adjusted[i], :<=, adjusted[j],
                          "raw #{pvalues[i]} vs #{pvalues[j]} pvalues=#{pvalues.inspect}"
        end
      end
    end
  end

  def test_holm_returns_single_element_unchanged
    assert_equal [0.42], BenchTrack::Stats.holm([0.42])
  end

  def test_analyze_deterministic_across_repeated_calls
    rng = Random.new(RNG_SEED)
    [10, 25].each do |blocks|
      series_list = %w[alpha beta gamma].map { |label| random_series(rng, label, blocks) }
      seed = rng.rand(2**32)
      first = BenchTrack::Stats.analyze(series_list, seed: seed, threshold_pct: 5.0)
      second = BenchTrack::Stats.analyze(series_list, seed: seed, threshold_pct: 5.0)
      assert_equal first, second, "blocks=#{blocks} seed=#{seed}"
      first.zip(second).each do |a, b|
        a.to_h.each do |field, value|
          assert_equal value, b[field], "field=#{field} blocks=#{blocks} seed=#{seed}"
        end
      end
    end
  end
end
