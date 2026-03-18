# build_config.rb - mruby build configuration for git-lite
MRuby::Build.new do |conf|
  toolchain :clang

  # Core gems
  conf.gembox 'default'

  # File I/O
  conf.gem mgem: 'mruby-io'
  conf.gem mgem: 'mruby-dir'
  conf.gem mgem: 'mruby-dir-glob'
  conf.gem mgem: 'mruby-env'
  conf.gem mgem: 'mruby-errno'

  # Data formats
  conf.gem mgem: 'mruby-json'
  conf.gem mgem: 'mruby-pack'

  # Crypto / Compression
  conf.gem mgem: 'mruby-sha2'
  conf.gem mgem: 'mruby-zlib'

  # Database
  conf.gem mgem: 'mruby-sqlite3'

  # Time formatting
  conf.gem mgem: 'mruby-time-strftime'

  # Testing
  conf.gem mgem: 'mruby-mtest'
  conf.gem mgem: 'mruby-stringio'

  # Enable debug for development
  conf.enable_debug
  conf.enable_test
end
