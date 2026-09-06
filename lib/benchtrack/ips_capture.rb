require "benchmark/ips"
require "json"

module BenchTrackIpsCapture
  ENTRIES = {}

  def ips(*args, &block)
    report = super
    report.entries.each { |e| ENTRIES[e.label.to_s] = e.ips.to_f }
    File.write(ENV.fetch("BENCHTRACK_RESULT_PATH"),
               JSON.generate({ "format" => 1,
                               "entries" => ENTRIES.map { |l, v| { "label" => l, "ips" => v } } }))
    report
  end
end

Benchmark.singleton_class.prepend(BenchTrackIpsCapture)
