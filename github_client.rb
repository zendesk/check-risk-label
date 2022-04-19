# frozen_string_literal: true

# No specific ruby version; only core dependencies
# (Using Javascript would fit better with the Github platform:
# https://docs.github.com/en/actions/creating-actions/creating-a-javascript-action)

require 'net/http'
require 'json'

class GithubClient
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
    return(res.body && JSON.parse(res.body)) if res.code == expected_status.to_s

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

  def delete(url)
    do_request(Net::HTTP::Delete, url, 204)
  end
end
