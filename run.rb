#!/usr/bin/env ruby
# frozen_string_literal: true

# No specific ruby version; only core dependencies
# (Using Javascript would fit better with the Github platform:
# https://docs.github.com/en/actions/creating-actions/creating-a-javascript-action)

require 'net/http'
require 'json'

RISK_LABELS = {
  'risk:none' => ['999999', 'Asserts that the PR does not change any deployable files'],
  'risk:low' => ['fbca04', 'Deployment risk: low'],
  'risk:medium' => ['ff8000', 'Deployment risk: medium'],
  'risk:high' => ['ff0000', 'Deployment risk: high']
}.freeze

RISK_LABELS_RE = /\Arisk:(none|low|medium|high)\z/.freeze

@errors = 0

def error(message)
  warn("ERROR: #{message}")
  @errors += 1
end

def abort_if_errors
  exit 1 if @errors.positive?
end

def github_api_session
  @github_api_session ||= begin
    http = Net::HTTP.new('api.github.com', 443)
    http.use_ssl = true
    http.start
    http
  end
end

def user_and_password(file)
  @user_and_password ||= begin
    creds = JSON.parse(File.read(file))
    "#{creds.fetch('github').fetch('user')}:#{creds.fetch('github').fetch('pass')}"
  end
end

def do_request(klass, url, expected_status, body = nil)
  uri = URI.parse(url)
  req = klass.new(uri)

  req['Authorization'] = if (file = ENV['DEBUG_CREDENTIALS_PATH'])
                           "Basic #{[user_and_password(file)].pack('m0')}"
                         else
                           "Bearer #{ENV.fetch('GITHUB_TOKEN')}"
                         end

  req['Accept'] = 'application/vnd.github.v3+json'

  if body
    req.body = JSON.generate(body)
    req['Content-Type'] = 'application/json'
  end

  res = github_api_session.request(req)
  return JSON.parse(res.body) if res.code == expected_status.to_s

  raise <<~MESSAGE
    #{req.method} #{url} -> HTTP/#{res.http_version} #{res.code} #{res.message} (expected #{expected_status})
  MESSAGE
end

def get(url)
  do_request(Net::HTTP::Get, url, 200)
end

def post(url, body)
  do_request(Net::HTTP::Post, url, 201, body)
end

def patch(url, body)
  do_request(Net::HTTP::Patch, url, 200, body)
end

def ensure_labels_present(strict:)
  # https://docs.github.com/en/rest/reference/issues#list-labels-for-a-repository
  # https://docs.github.com/en/rest/reference/issues#create-a-label
  # https://docs.github.com/en/rest/reference/issues#update-a-label

  # FIXME: pagination. We've set the max per_page but there still might be more than that.
  labels_in_repo = get("https://api.github.com/repos/#{repo_full_name}/labels?per_page=100")
  warn 'Warning: 100 labels found; there might be more. FIXME, pagination' if labels_in_repo.count >= 100

  by_name = labels_in_repo.to_h { |label| [label.fetch('name'), label] }

  RISK_LABELS.each do |name, (color, description)|
    existing = by_name[name]

    if existing.nil?
      body = { name: name, color: color, description: description }
      # FIXME: race condition here, if we run concurrently on the same repo
      post("https://api.github.com/repos/#{repo_full_name}/labels", body)
    elsif strict && (existing.fetch('color').downcase != color.downcase || existing.fetch('description') != description)
      body = { new_name: name, color: color, description: description }
      patch(existing.fetch('url'), body)
    end
  end
end

def repo_full_name
  event.fetch('repository').fetch('full_name')
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

def ensure_template_text_removed(text:, message:)
  pr_description = event.fetch('pull_request').fetch('body')

  error(message) if pr_description.include?(text)
end

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
ensure_template_text_removed(text: ensure_template_text_removed_text, message: ensure_template_text_removed_message) \
  unless ensure_template_text_removed_text == ''

abort_if_errors
