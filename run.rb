#!/usr/bin/env ruby
# frozen_string_literal: true

# No specific ruby version; only core dependencies
# (Using Javascript would fit better with the Github platform:
# https://docs.github.com/en/actions/creating-actions/creating-a-javascript-action)

require 'net/http'
require 'json'
require 'uri'

class Runner
  RISK_LABELS = {
    'risk:none' => ['999999', 'Asserts that the PR does not change any deployable files'],
    'risk:low' => ['fbca04', 'Deployment risk: low'],
    'risk:medium' => ['ff8000', 'Deployment risk: medium'],
    'risk:high' => ['ff0000', 'Deployment risk: high']
  }.freeze

  RISK_LABELS_RE = /\Arisk:(none|low|medium|high)\z/
  RISK_SECTION_ERROR = 'Please ensure that the PR description contains a ' \
                       '`### Risks` section with a line starting with one of ' \
                       'the words `high`, `medium`, `low` or `none`.'

  def error(message)
    warn("ERROR: #{message}")
    @errors += 1
  end

  def abort_if_errors
    exit 1 if @errors.positive?
  end

  def ensure_labels_present(strict:)
    require_relative 'repo_label_checker'
    RepoLabelChecker.new(event, github_client).run(strict: strict, definitions: RISK_LABELS)
  end

  def event
    @event ||= JSON.parse(File.read(ENV.fetch('GITHUB_EVENT_PATH')))
  end

  def github_client
    require_relative 'github_client'
    @github_client ||= GithubClient.new
  end

  def repo_full_name
    event.fetch('repository').fetch('full_name')
  end

  def pr_number
    event.fetch('number')
  end

  def issue_labels_url
    "https://api.github.com/repos/#{repo_full_name}/issues/#{pr_number}/labels"
  end

  def issue_label_url(label_name)
    "#{issue_labels_url}/#{URI.encode_www_form_component(label_name)}"
  end

  def risk_from_pr_body
    pr_body = event.fetch('pull_request').fetch('body')
    return nil if pr_body.nil?

    risk_section = pr_body.lines.drop_while { |line| line !~ /^###\s+Risks\b/i }.join
    return nil if risk_section.empty?

    uncommented_risk_section = risk_section.gsub(/<!--.*?-->/m, '')

    %w[high medium low none].find do |risk|
      uncommented_risk_section.lines.any? { |line| line.match?(/^\W*#{risk}\b/i) }
    end
  end

  def auto_apply_risk_label
    desired_risk = risk_from_pr_body

    if desired_risk.nil?
      error(RISK_SECTION_ERROR)
      return
    end

    desired_label = "risk:#{desired_risk}"
    labels_on_pr = event.fetch('pull_request').fetch('labels').map { |label| label.fetch('name') }
    risk_labels_on_pr = labels_on_pr.grep(RISK_LABELS_RE)
    stale_risk_labels = risk_labels_on_pr - [desired_label]

    stale_risk_labels.each { |label| github_client.delete(issue_label_url(label)) }
    github_client.post(issue_labels_url, { labels: [desired_label] }) unless risk_labels_on_pr.include?(desired_label)

    updated_labels = labels_on_pr - stale_risk_labels
    updated_labels << desired_label unless updated_labels.include?(desired_label)
    event.fetch('pull_request')['labels'] = updated_labels.map { |label| { 'name' => label } }
  end

  def ensure_one_label_applied
    labels_on_pr = event.fetch('pull_request').fetch('labels').map { |label| label.fetch('name') }.sort
    puts "Labels on this PR: #{labels_on_pr.inspect}"

    risk_labels_on_pr = labels_on_pr.grep(RISK_LABELS_RE)

    error("Please apply exactly one of the risk labels: #{RISK_LABELS.keys.join(', ')}") if risk_labels_on_pr.count != 1
  end

  def ensure_template_text_removed(text:, message:)
    pr_description = event.fetch('pull_request').fetch('body')

    error(message) if pr_description&.include?(text)
  end

  def run
    @errors = 0

    ensure_labels_defined = ENV.fetch('ENSURE_LABELS_DEFINED')
    error('ensure_labels_defined must be one of: strict, names-only, false') \
      unless %w[strict names-only false].include?(ensure_labels_defined)

    ensure_pr_is_labelled = ENV.fetch('ENSURE_PR_IS_LABELLED')
    error('ensure_pr_is_labelled must be one of: true, false') \
      unless %w[true false].include?(ensure_pr_is_labelled)

    auto_apply_label = ENV.fetch('AUTO_APPLY_LABEL')
    error('auto_apply_label must be one of: true, false') \
      unless %w[true false].include?(auto_apply_label)

    ensure_template_text_removed_text = ENV.fetch('ENSURE_TEMPLATE_TEXT_REMOVED_TEXT')
    ensure_template_text_removed_message = ENV.fetch('ENSURE_TEMPLATE_TEXT_REMOVED_MESSAGE')

    abort_if_errors

    ensure_labels_present(strict: ensure_labels_defined == 'strict') unless ensure_labels_defined == 'false'
    auto_apply_risk_label if auto_apply_label == 'true'
    ensure_one_label_applied if ensure_pr_is_labelled == 'true'
    unless ensure_template_text_removed_text == ''
      ensure_template_text_removed(text: ensure_template_text_removed_text,
                                   message: ensure_template_text_removed_message)
    end

    abort_if_errors
  end
end

Runner.new.run if $PROGRAM_NAME == __FILE__
