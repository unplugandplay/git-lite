# Rakefile for git-lite (mruby build)

MRUBY_DIR = ENV['MRUBY_DIR'] || File.expand_path('~/mruby')

desc "Build git-lite with mruby"
task :build do
  unless File.directory?(MRUBY_DIR)
    puts "mruby not found at #{MRUBY_DIR}"
    puts "Set MRUBY_DIR environment variable or install mruby"
    exit 1
  end

  # Copy build_config.rb to mruby dir
  cp 'build_config.rb', File.join(MRUBY_DIR, 'build_config.rb')

  # Build mruby with our config
  Dir.chdir(MRUBY_DIR) do
    sh 'rake'
  end

  puts "Build complete!"
end

desc "Run all tests with mruby"
task :test do
  test_files = Dir['test/*_test.rb'].sort
  failures = 0

  test_files.each do |f|
    puts "\n=== #{File.basename(f)} ==="
    unless system("mruby -I lib -I test #{f}")
      failures += 1
    end
  end

  puts "\n#{test_files.length} test files, #{failures} failures"
  exit(1) if failures > 0
end

desc "Run unit tests only"
task :fast do
  tests = %w[util_test ui_test config_test db_test sqlite_wrapper_test]
  tests.each do |t|
    puts "\n=== #{t}.rb ==="
    system("mruby -I lib -I test test/#{t}.rb")
  end
end

desc "Run integration tests"
task :integration do
  tests = %w[integration_test git_importer_test edge_cases_test]
  tests.each do |t|
    puts "\n=== #{t}.rb ==="
    system("mruby -I lib -I test test/#{t}.rb")
  end
end

desc "Compile to standalone binary"
task :compile do
  Dir.mkdir('build') unless File.directory?('build')

  # Concatenate all lib files into single source
  sources = %w[
    lib/git-lite/mruby_compat.rb
    lib/git-lite/sqlite_wrapper.rb
    lib/git-lite/util.rb
    lib/git-lite/config.rb
    lib/git-lite/db.rb
    lib/git-lite/repo.rb
    lib/git-lite/ui.rb
    lib/git-lite/delta.rb
    lib/git-lite/content_store.rb
    lib/git-lite/git_importer.rb
    lib/git-lite/cli.rb
  ]

  combined = sources.map { |f| File.read(f) }.join("\n")
  combined += "\nGitLite::CLI.run(ARGV)\n"

  File.write('build/git-lite-combined.rb', combined)

  # Compile with mrbc
  sh "mrbc -o build/git-lite.mrb build/git-lite-combined.rb"
  puts "Compiled to build/git-lite.mrb"
end

desc "Check syntax"
task :lint do
  Dir['lib/**/*.rb'].each do |f|
    sh "mruby -c #{f}"
  end
end

task default: :test
