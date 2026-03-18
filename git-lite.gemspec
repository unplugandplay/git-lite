Gem::Specification.new do |spec|
  spec.name          = "git-lite"
  spec.version       = "1.0.0"
  spec.authors       = ["GitLite Contributors"]
  spec.email         = ["dev@example.com"]
  
  spec.summary       = "A Git-like version control system backed by SQLite"
  spec.description   = "Lightweight version control with SQLite storage, compatible with mruby"
  spec.homepage      = "https://github.com/example/git-lite"
  spec.license       = "MIT"
  
  spec.files         = Dir["bin/**/*", "lib/**/*", "README.md", "LICENSE"]
  spec.bindir        = "bin"
  spec.executables   = ["git-lite"]
  spec.require_paths = ["lib"]
  
  spec.required_ruby_version = ">= 2.7.0"
  
  spec.add_dependency "sqlite3", "~> 1.4"
  
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
