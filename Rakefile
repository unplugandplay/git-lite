require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
  t.warning = false
end

Rake::TestTask.new(:test_unit) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/*_test.rb'
  t.verbose = true
end

desc "Run all tests"
task :test => :test_unit

desc "Run tests with coverage"
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:test].invoke
end

desc "Run only unit tests (fast)"
task :fast do
  tests = %w[util_test ui_test config_test db_test]
  tests.each do |test|
    system("ruby -Ilib:test test/#{test}")
  end
end

desc "Run integration tests (slower)"
task :integration do
  tests = %w[integration_test git_importer_test edge_cases_test]
  tests.each do |test|
    system("ruby -Ilib:test test/#{test}")
  end
end

desc "Run performance tests"
task :performance do
  ENV['PERFORMANCE'] = 'true'
  system("ruby -Ilib:test test/performance_test.rb")
end

desc "Build standalone mruby binary"
task :build do
  puts "Building git-lite..."
  puts "Note: Requires mruby with sqlite3 gem compiled in"
  
  # This would compile with mruby
  # mrbc -Bgit_lite lib/git-lite.rb
end

desc "Install locally"
task :install do
  target = File.expand_path('~/.local/bin')
  Dir.mkdir(target) unless Dir.exist?(target)
  
  FileUtils.cp('bin/git-lite', File.join(target, 'git-lite'))
  FileUtils.chmod(0755, File.join(target, 'git-lite'))
  
  puts "Installed to #{target}/git-lite"
  puts "Make sure #{target} is in your PATH"
end

desc "Run linting"
task :lint do
  system("ruby -c lib/git-lite.rb")
  Dir['lib/git-lite/*.rb'].each do |file|
    system("ruby -c #{file}")
  end
end

desc "Generate documentation"
task :docs do
  system("rdoc lib/")
end

task default: :test
