# frozen_string_literal: true

module BenchTrack
  module Stats
    ALPHA       = 0.05
    ENUM_LIMIT  = 20
    MC_ROUNDS   = 10_000
    BOOT_ROUNDS = 10_000

    module_function

    def log_ratios(series)
      series.base.zip(series.head).map { |base, head| Math.log(head / base) }
    end

    def mean(xs)
      xs.sum / xs.length
    end

    def permutation_pvalue(xs, rng)
      n = xs.length
      observed = 0.0
      xs.each { |x| observed += x }
      observed = observed.abs

      if n <= ENUM_LIMIT
        total = 1 << n
        count = 0
        total.times do |mask|
          sum = 0.0
          n.times { |i| sum += mask[i] == 1 ? -xs[i] : xs[i] }
          count += 1 if sum.abs >= observed
        end
        count.fdiv(total)
      else
        hits = 0
        MC_ROUNDS.times do
          sum = 0.0
          n.times { |i| sum += rng.rand(2).zero? ? xs[i] : -xs[i] }
          hits += 1 if sum.abs >= observed
        end
        (hits + 1.0) / (MC_ROUNDS + 1)
      end
    end

    def bootstrap_ci(xs, rng)
      n = xs.length
      means = Array.new(BOOT_ROUNDS) { mean(Array.new(n) { xs[rng.rand(n)] }) }
      means.sort!
      [means[((BOOT_ROUNDS - 1) * 0.025).round], means[((BOOT_ROUNDS - 1) * 0.975).round]]
    end

    def holm(pvalues)
      return pvalues.dup if pvalues.length < 2

      m = pvalues.length
      order = pvalues.each_index.sort_by { |i| [pvalues[i], i] }
      adjusted = Array.new(m)
      running_max = 0.0
      order.each_with_index do |original, rank|
        candidate = (m - rank) * pvalues[original]
        running_max = candidate if candidate > running_max
        adjusted[original] = [running_max, 1.0].min
      end
      adjusted
    end

    def verdict(slowdown_pct, holm_p, threshold_pct)
      slowdown_pct > threshold_pct && holm_p < ALPHA ? "fail" : "pass"
    end

    def analyze(series_list, seed:, threshold_pct:)
      rng = Random.new(seed)
      partials = series_list.sort_by(&:label).map do |series|
        perm_seed = rng.rand(2**32)
        boot_seed = rng.rand(2**32)
        xs = log_ratios(series)
        p_value = permutation_pvalue(xs, Random.new(perm_seed))
        ci_low, ci_high = bootstrap_ci(xs, Random.new(boot_seed))
        { label: series.label, effect: mean(xs), p_value: p_value,
          ci_low: ci_low, ci_high: ci_high }
      end

      holm_ps = holm(partials.map { |partial| partial[:p_value] })

      partials.zip(holm_ps).map do |partial, holm_p|
        effect = partial[:effect]
        slowdown_pct = (1 - Math.exp(effect)) * 100
        EntryResult.new(
          label: partial[:label],
          effect: effect,
          ci_low: partial[:ci_low],
          ci_high: partial[:ci_high],
          p_value: partial[:p_value],
          holm_p: holm_p,
          percent_change: (Math.exp(effect) - 1) * 100,
          slowdown_pct: slowdown_pct,
          verdict: verdict(slowdown_pct, holm_p, threshold_pct)
        )
      end
    end
  end
end
