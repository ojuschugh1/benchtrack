# frozen_string_literal: true

require "benchmark/ips"

Benchmark.ips do |x|
  x.config(warmup: 0.05, time: 0.05)
  x.report("string concat") { "a" + "b" }
  x.report("string upcase") { "hello".upcase }
end
