#!/usr/bin/env ruby
# frozen_string_literal: true

# No specific ruby version; only core dependencies
# (Using Javascript would fit better with the Github platform:
# https://docs.github.com/en/actions/creating-actions/creating-a-javascript-action)

class RepoLabelChecker
  def initialize(event, github_client)
    @event = event
    @github_client = github_client
  end

  attr_reader :event, :github_client

  def repo_full_name
    event.fetch('repository').fetch('full_name')
  end

  def run(strict:, definitions:)
    # https://docs.github.com/en/rest/reference/issues#list-labels-for-a-repository
    # https://docs.github.com/en/rest/reference/issues#create-a-label
    # https://docs.github.com/en/rest/reference/issues#update-a-label

    # FIXME: pagination. We've set the max per_page but there still might be more than that.
    labels_in_repo = github_client.get("https://api.github.com/repos/#{repo_full_name}/labels?per_page=100")
    warn 'Warning: 100 labels found; there might be more. FIXME, pagination' if labels_in_repo.count >= 100

    # rubocop:disable Style/MapToHash - ruby 2.5 compat
    by_name = labels_in_repo.map { |label| [label.fetch('name'), label] }.to_h
    # rubocop:enable Style/MapToHash

    definitions.each do |name, (color, description)|
      existing = by_name[name]

      if existing.nil?
        body = { name: name, color: color, description: description }
        # FIXME: race condition here, if we run concurrently on the same repo
        github_client.post("https://api.github.com/repos/#{repo_full_name}/labels", body)
      elsif strict && (
          existing.fetch('color').downcase != color.downcase || existing.fetch('description') != description
        )
        body = { new_name: name, color: color, description: description }
        github_client.patch(existing.fetch('url'), body)
      end
    end
  end
end
