#!/usr/bin/env ruby
# git-lite - Main entry point
# Called by bin/git-lite wrapper

require 'git-lite'

GitLite::CLI.run(ARGV)
