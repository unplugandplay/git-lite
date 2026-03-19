# build_config.rb - mruby build configuration for git-lite
MRuby::Build.new do |conf|
  toolchain :clang

  # Core gems (includes mruby-io, mruby-dir, mruby-errno, mruby-pack, etc.)
  conf.gembox 'default'

  # Dir.glob support
  conf.gem github: 'gromnitsky/mruby-dir-glob'

  # Environment variables
  conf.gem github: 'iij/mruby-env'

  # Regexp (Oniguruma)
  conf.gem github: 'mattn/mruby-onig-regexp'

  # JSON
  conf.gem github: 'mattn/mruby-json'

  # Digest (SHA256 via CommonCrypto on macOS)
  conf.gem github: 'iij/mruby-digest'

  # Zlib compression
  conf.gem github: 'iij/mruby-zlib'

  # SQLite3
  conf.gem github: 'mattn/mruby-sqlite3'

  # Time formatting
  conf.gem github: 'monochromegane/mruby-time-strftime'

  # Testing
  conf.gem github: 'iij/mruby-mtest'
  conf.gem github: 'ksss/mruby-stringio'

  # Enable debug for development
  conf.enable_debug
  conf.enable_test
end
