# frozen_string_literal: true

require 'json'
require_relative '../github_client'
require_relative '../repo_label_checker'

RSpec.describe RepoLabelChecker do
  let(:event) { JSON.parse(File.read(File.join(File.dirname(__FILE__), 'sample_event.json'))) }
  let(:github_client) { instance_double('github-client') }

  let(:definitions) do
    {
      'foo' => ['111111', 'The foo label'],
      'bar' => ['222222', 'The bar label'],
      'baz' => ['333333', 'The baz label']
    }.freeze
  end

  let(:existing_labels) do
    [
      { 'url' => 'url-of-foo', 'name' => 'foo', 'color' => '111111', 'description' => 'The foo label' },
      { 'url' => 'url-of-bar', 'name' => 'bar', 'color' => '222222', 'description' => 'The bar label' },
      { 'url' => 'url-of-baz', 'name' => 'baz', 'color' => '333333', 'description' => 'The baz label' }
    ]
  end

  let(:labels_url) { 'https://api.github.com/repos/zendesk/check-risk-label/labels' }

  before do
    expect_get(existing_labels)
  end

  def expect_get(response_body)
    expect(github_client).to receive(:get).with('https://api.github.com/repos/zendesk/check-risk-label/labels?per_page=100').and_return(response_body)
  end

  def expect_post(request_body)
    expect(github_client).to receive(:post).with(labels_url, request_body)
  end

  def expect_patch(label_url, request_body)
    expect(github_client).to receive(:patch).with(label_url, request_body)
  end

  it 'creates all the labels if they are missing' do
    existing_labels.clear

    expect_post({ name: 'foo', color: '111111', description: 'The foo label' })
    expect_post({ name: 'bar', color: '222222', description: 'The bar label' })
    expect_post({ name: 'baz', color: '333333', description: 'The baz label' })

    checker = RepoLabelChecker.new(event, github_client)
    checker.run(strict: true, definitions: definitions)
  end

  it 'does nothing if all the labels are already correct' do
    checker = RepoLabelChecker.new(event, github_client)
    checker.run(strict: true, definitions: definitions)
  end

  it 'creates one label if missing' do
    existing_labels.delete_at(1) # bar
    expect_post({ name: 'bar', color: '222222', description: 'The bar label' })

    checker = RepoLabelChecker.new(event, github_client)
    checker.run(strict: true, definitions: definitions)
  end

  it 'updates a label if it is wrong, and strict mode is on' do
    existing_labels[0]['color'] = '000000'
    existing_labels[1]['description'] = 'The wrong text'

    expect_patch('url-of-foo', { new_name: 'foo', color: '111111', description: 'The foo label' })
    expect_patch('url-of-bar', { new_name: 'bar', color: '222222', description: 'The bar label' })

    checker = RepoLabelChecker.new(event, github_client)
    checker.run(strict: true, definitions: definitions)
  end

  it 'does not update a label if wrong, and strict mode is off' do
    existing_labels[0]['color'] = '000000'
    existing_labels[1]['description'] = 'The wrong text'

    checker = RepoLabelChecker.new(event, github_client)
    checker.run(strict: false, definitions: definitions)
  end
end
