#!/usr/bin/env ruby

# No specific ruby version; only core dependencies
# (Using Javascript would fit better with the Github platform:
# https://docs.github.com/en/actions/creating-actions/creating-a-javascript-action)

require 'net/http'
require 'json'

RISK_LABELS = {
  'risk:none'   => [ '999999', 'Asserts that the PR does not change any deployable files' ],
  'risk:low'    => [ 'fbca04', 'Deployment risk: low' ],
  'risk:medium' => [ 'ff8000', 'Deployment risk: medium' ],
  'risk:high'   => [ 'ff0000', 'Deployment risk: high' ],
}

RISK_LABELS_RE = /\Arisk:(none|low|medium|high)\z/

def github_api_session
  @session ||= begin
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

  if file = ENV['DEBUG_CREDENTIALS_PATH']
    req['Authorization'] = "Basic #{[user_and_password(file)].pack('m0')}"
  else
    req['Authorization'] = "Bearer #{ENV.fetch('GITHUB_TOKEN')}"
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

def ensure_labels_present
  # https://docs.github.com/en/rest/reference/issues#list-labels-for-a-repository
  # https://docs.github.com/en/rest/reference/issues#create-a-label
  # https://docs.github.com/en/rest/reference/issues#update-a-label

  # TODO: pagination. We've set the max per_page but there still might be more than that.
  labels_in_repo = get("https://api.github.com/repos/#{repo_full_name}/labels?per_page=100")
  if labels_in_repo.count >= 100
    $stderr.puts "Warning: 100 labels found; there might be more. TODO, pagination"
  end

  by_name = labels_in_repo.map { |label| [label.fetch('name'), label] }.to_h

  RISK_LABELS.each do |name, (color, description)|
    existing = by_name[name]

    if existing.nil?
      body = { name: name, color: color, description: description }
      post("https://api.github.com/repos/#{repo_full_name}/labels", body)
    elsif existing.fetch('color').downcase != color.downcase || existing.fetch('description') != description
      body = { new_name: name, color: color, description: description }
      patch(existing.fetch('url'), body)
    end
  end
end

def repo_full_name
  event.fetch('repository').fetch('full_name')
end

def event
  @event ||= begin
    JSON.parse(File.read(ENV.fetch('GITHUB_EVENT_PATH')))
  end
end

def ensure_one_label_applied
  labels_on_pr = event.fetch('pull_request').fetch('labels').map { |label| label.fetch('name') }.sort
  puts "Labels on this PR: #{labels_on_pr.inspect}"

  risk_labels_on_pr = labels_on_pr.select { |t| t.match?(RISK_LABELS_RE) }

  if risk_labels_on_pr.count != 1
    $stderr.puts "Please apply exactly one of the risk labels: #{RISK_LABELS.keys.join(', ')}"
    exit 1
  end
end

ensure_labels_present
ensure_one_label_applied
