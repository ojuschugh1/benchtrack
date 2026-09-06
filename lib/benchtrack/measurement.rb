# frozen_string_literal: true

module BenchTrack
  module Measurement
    Pairing = Struct.new(:series, :base_only, :head_only, keyword_init: true)

    module_function

    def collect(blocks:, rng:)
      runs = { base: [], head: [] }
      blocks.times do
        first = rng.rand(2).zero? ? :base : :head
        second = first == :base ? :head : :base
        runs[first] << yield(first)
        runs[second] << yield(second)
      end
      runs
    end

    def pair(base_runs, head_runs)
      base_labels = consistent_labels(:base, base_runs)
      head_labels = consistent_labels(:head, head_runs)

      base_ips = base_runs.map { |run| run.to_h { |e| [e.label, e.ips] } }
      head_ips = head_runs.map { |run| run.to_h { |e| [e.label, e.ips] } }

      series = (base_labels & head_labels).sort.map do |label|
        PairedSeries.new(label,
                         base_ips.map { |h| h.fetch(label) },
                         head_ips.map { |h| h.fetch(label) })
      end

      Pairing.new(series: series,
                  base_only: (base_labels - head_labels).sort,
                  head_only: (head_labels - base_labels).sort)
    end

    def consistent_labels(side, runs)
      labels = runs.first.map(&:label)
      runs.each do |run|
        got = run.map(&:label)
        next if got.sort == labels.sort

        diff = ((labels - got) | (got - labels)).sort
        raise SuiteError,
              "#{side} suite produced inconsistent labels across runs (differing: #{diff.join(", ")})"
      end
      labels
    end
  end
end
