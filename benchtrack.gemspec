Gem::Specification.new do |spec|
  spec.name    = "benchtrack"
  spec.version = "0.1.0"
  spec.authors = ["Ojus Chugh"]

  spec.summary     = "Pull-request-time performance regression testing for Ruby libraries"
  spec.description = "Turns an existing benchmark-ips suite into a paired base-versus-head " \
                     "performance comparison over git worktrees. Fails CI only when a slowdown " \
                     "is both practically large and statistically supported."
  spec.homepage    = "https://github.com/ojuschugh1/benchtrack"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = ["benchtrack"]
  spec.require_paths = ["lib"]
end
