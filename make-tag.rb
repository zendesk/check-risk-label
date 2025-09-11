#!/usr/bin/env ruby
# frozen_string_literal: true

# A perhaps rather overkill script to remove the dev stuff (DISCARDS)
# from tags, so that the action is nice and lightweight when in use.

require 'English'

DISCARDS = %w[
  .github
  .rubocop.yml
  .ruby-version
  Gemfile
  Gemfile.lock
  make-tag.rb
  spec
  vendor
].freeze

version = ARGV.first
raise 'Usage: ./make-tag.rb vMAJOR.MINOR.PATCH' unless ARGV.one? && version.match?(/^v(\d+)\.(\d+)\.(\d+)$/)

_ = `git rev-parse --verify refs/tags/#{version} 2>/dev/null`
raise 'Tag already exists' if $CHILD_STATUS.success?

root_tree = `git ls-tree -z HEAD:`.split("\0")
$CHILD_STATUS.success? or exit 1

root_tree.reject! do |entry|
  m = entry.match(/\A\d+\s+\w+\s+\w+\t(.*)\z/)
  m && DISCARDS.include?(m[1])
end

require 'tempfile'
tree_id = Tempfile.open do |stdin|
  Tempfile.open do |stdout|
    root_tree.each { |entry| stdin.write("#{entry}\0") }
    stdin.flush
    stdin.rewind

    system 'git mktree -z', in: stdin.fileno, out: stdout.fileno
    $CHILD_STATUS.success? or exit 1

    stdout.rewind
    stdout.read.chomp
  end
end

commit = `git commit-tree -p HEAD -m 'make-tag #{version}' #{tree_id}`.chomp
$CHILD_STATUS.success? or exit 1

system "git tag #{version} #{commit}"
$CHILD_STATUS.success? or exit 1

puts "Created tag #{version} -> #{commit}"
