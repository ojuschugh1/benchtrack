require "benchmark/ips"
require "json"

module BenchTrackIpsCapture
  CALLS = []

  def ips(*args, &block)
    report = super
    CALLS << report.entries.to_h { |e| [e.label.to_s, e.ips.to_f] }
    counts = CALLS.flat_map(&:keys).tally
    entries = CALLS.each_with_index.flat_map do |call, i|
      call.map do |label, ips|
        { "label" => counts[label] > 1 ? "#{label} [#{i + 1}]" : label, "ips" => ips }
      end
    end
    File.write(ENV.fetch("BENCHTRACK_RESULT_PATH"),
               JSON.generate({ "format" => 1, "entries" => entries }))
    report
  end
end

Benchmark.singleton_class.prepend(BenchTrackIpsCapture)
