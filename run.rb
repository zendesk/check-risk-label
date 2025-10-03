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

    error("Please apply exactly one of the risk labels: #{RISK_LABELS.keys.join(', ')}") if risk_labels_on_pr.count != 1
  end

  def repo_full_name
    event.fetch('repository').fetch('full_name')
  end

  def pull_number
    event.fetch('number')
  end

  def detect_risk_label
    labels_on_pr = event.fetch('pull_request').fetch('labels').map { |label| label.fetch('name') }
    labels_on_pr.grep(RISK_LABELS_RE).first
  end

  def required_approvals_for(risk_label)
    case risk_label
    when 'risk:none'
      ENV.fetch('MIN_APPROVALS_NONE', '1').to_i
    when 'risk:low'
      ENV.fetch('MIN_APPROVALS_LOW', '1').to_i
    when 'risk:medium'
      ENV.fetch('MIN_APPROVALS_MEDIUM', '1').to_i
    when 'risk:high'
      ENV.fetch('MIN_APPROVALS_HIGH', '2').to_i
    else
      0
    end
  end

  def count_distinct_approvers_with_latest_state_approved
    require_relative 'github_client'
    client = GithubClient.new
    reviews = client.get("https://api.github.com/repos/#{repo_full_name}/pulls/#{pull_number}/reviews")

    latest_state_by_user = {}
    reviews.each do |review|
      user = review.fetch('user')
      user_id = user && user.fetch('id')
      state = review.fetch('state')
      latest_state_by_user[user_id] = state if user_id
    end

    latest_state_by_user.values.count { |state| state == 'APPROVED' }
  end

  def enforce_min_approvals_if_enabled
    enforce = ENV.fetch('ENFORCE_MIN_APPROVALS')
    return if enforce == 'false'

    risk_label = detect_risk_label
    return unless risk_label # ensure_one_label_applied will handle errors

    required = required_approvals_for(risk_label)
    return if required <= 0

    approved_count = count_distinct_approvers_with_latest_state_approved
    error("Need at least #{required} approvals for #{risk_label}; found #{approved_count}") if approved_count < required
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

    enforce_min_approvals = ENV.fetch('ENFORCE_MIN_APPROVALS')
    error('enforce_min_approvals must be one of: true, false') \
      unless %w[true false].include?(enforce_min_approvals)

    ensure_template_text_removed_text = ENV.fetch('ENSURE_TEMPLATE_TEXT_REMOVED_TEXT')
    ensure_template_text_removed_message = ENV.fetch('ENSURE_TEMPLATE_TEXT_REMOVED_MESSAGE')

    abort_if_errors

    ensure_labels_present(strict: ensure_labels_defined == 'strict') unless ensure_labels_defined == 'false'
    ensure_one_label_applied if ensure_pr_is_labelled
    unless ensure_template_text_removed_text == ''
      ensure_template_text_removed(text: ensure_template_text_removed_text,
                                   message: ensure_template_text_removed_message)
    end

    enforce_min_approvals_if_enabled

    abort_if_errors
  end
end

Runner.new.run if $PROGRAM_NAME == __FILE__
