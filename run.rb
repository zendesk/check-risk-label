#!/usr/bin/env ruby
# frozen_string_literal: true

# No specific ruby version; only core dependencies
# (Using Javascript would fit better with the Github platform:
# https://docs.github.com/en/actions/creating-actions/creating-a-javascript-action)

require 'net/http'
require 'json'

class Runner
  RISK_LABELS = {
    'risk:none' => ['999999', 'Asserts that the PR does not change any deployable files'],
    'risk:low' => ['fbca04', 'Deployment risk: low'],
    'risk:medium' => ['ff8000', 'Deployment risk: medium'],
    'risk:high' => ['ff0000', 'Deployment risk: high']
  }.freeze

  RISK_LABELS_RE = /\Arisk:(none|low|medium|high)\z/

  def error(message)
    warn("ERROR: #{message}")
    @errors += 1
  end

  def abort_if_errors
    exit 1 if @errors.positive?
  end

  def ensure_labels_present(strict:)
    require_relative 'github_client'
    require_relative 'repo_label_checker'
    RepoLabelChecker.new(event, GithubClient.new).run(strict: strict, definitions: RISK_LABELS)
  end

  def event
    @event ||= JSON.parse(File.read(ENV.fetch('GITHUB_EVENT_PATH')))
  end

  def ensure_one_label_applied
    labels_on_pr = event.fetch('pull_request').fetch('labels').map { |label| label.fetch('name') }.sort
    puts "Labels on this PR: #{labels_on_pr.inspect}"

    risk_labels_on_pr = labels_on_pr.grep(RISK_LABELS_RE)

    error("Please apply exactly one of the risk labels: #{RISK_LABELS.keys.join(', ')}") if risk_labels_on_pr.count > 1

    try_auto_add_label if risk_labels_on_pr.empty?
  end

  def ensure_template_text_removed(text:, message:)
    pr_description = event.fetch('pull_request').fetch('body')

    error(message) if pr_description&.include?(text)
  end

  def find_labels_in_description(description)
    labels = []
    if description.downcase.include?('## risks') || description.downcase.include?('## deploy risks')
      risk_section = description.split('#').select do |body|
        body.downcase.strip.start_with?('risk') || body.downcase.strip.start_with?('deploy risks')
      end
      risk_section_labels = %w[none low medium high].select do |label|
        risk_section.any? do |section|
          section.downcase.include?(label)
        end
      end
      labels << risk_section_labels.map { |label| "risk:#{label}" }
    end
    labels.flatten!
  end

  def remove_comments_from_description(description)
    sanitized = description
    previous = nil
    while sanitized != previous
      previous = sanitized
      sanitized = sanitized.gsub(/<!--.*?-->/m, '')
    end
    sanitized
  end

  def try_auto_add_label
    require_relative 'github_client'
    github_client = GithubClient.new

    description = event.fetch('pull_request').fetch('body')
    visible_description = remove_comments_from_description(description)
    risk_labels_in_description = find_labels_in_description(visible_description)

    puts "Risk labels found in description: #{risk_labels_in_description.inspect}"

    add_label_to_pr(risk_labels_in_description.first) if risk_labels_in_description&.one?

    commits = github_client.get(event.fetch('pull_request').fetch('commits_url'))
    risk_labels_in_commits = commits&.flat_map do |commit|
      RISK_LABELS.keys.select { |label| commit.fetch('commit').fetch('message')&.include?(label) }
    end&.uniq

    puts "Risk labels found in commits: #{risk_labels_in_commits.inspect}"

    add_label_to_pr(risk_labels_in_commits.first) if risk_labels_in_commits&.one?

    return unless ((risk_labels_in_description || []) + (risk_labels_in_commits || [])).count != 1

    error("Please apply exactly one of the risk labels: #{RISK_LABELS.keys.join(', ')}")
  end

  def add_label_to_pr(label)
    require_relative 'github_client'
    github_client = GithubClient.new

    github_client.post(event.fetch('pull_request').fetch('_links').fetch('issue').fetch('href'),
                       { 'labels' => [label] })
  end

  def run
    @errors = 0

    ensure_labels_defined = ENV.fetch('ENSURE_LABELS_DEFINED')
    error('ensure_labels_defined must be one of: strict, names-only, false') \
      unless %w[strict names-only false].include?(ensure_labels_defined)

    ensure_pr_is_labelled = ENV.fetch('ENSURE_PR_IS_LABELLED')
    error('ensure_pr_is_labelled must be one of: true, false') \
      unless %w[true false].include?(ensure_pr_is_labelled)

    ensure_template_text_removed_text = ENV.fetch('ENSURE_TEMPLATE_TEXT_REMOVED_TEXT')
    ensure_template_text_removed_message = ENV.fetch('ENSURE_TEMPLATE_TEXT_REMOVED_MESSAGE')

    abort_if_errors

    ensure_labels_present(strict: ensure_labels_defined == 'strict') unless ensure_labels_defined == 'false'
    ensure_one_label_applied if ensure_pr_is_labelled
    unless ensure_template_text_removed_text == ''
      ensure_template_text_removed(text: ensure_template_text_removed_text,
                                   message: ensure_template_text_removed_message)
    end

    abort_if_errors
  end
end

Runner.new.run if $PROGRAM_NAME == __FILE__
