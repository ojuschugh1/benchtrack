# frozen_string_literal: true

require "benchmark/ips"

Benchmark.ips do |x|
  x.config(warmup: 0.05, time: 0.05)
  x.report("a") { "a" * 2 }
  x.report("b") { "b" * 2 }
end

Benchmark.ips do |x|
  x.config(warmup: 0.05, time: 0.05)
  x.report("a") { "a" * 3 }
  x.report("c") { "c" * 3 }
end
