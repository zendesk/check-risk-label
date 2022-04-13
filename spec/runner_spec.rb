# frozen_string_literal: true

require 'English'
require_relative '../repo_label_checker'
require_relative '../run'

RSpec.describe Runner do
  let(:event) { JSON.parse(File.read(File.join(File.dirname(__FILE__), 'sample_event.json'))) }
  let(:github_client) { instance_double('github-client') }
  let(:repo_label_checker) { instance_double(RepoLabelChecker, 'repo-label-checker') }
  let(:runner) { Runner.new }
  let(:warnings) { [] }

  around do |scenario|
    old_env = ENV.to_h
    begin
      scenario.call
    ensure
      ENV.clear
      ENV.merge!(old_env)
    end
  end

  before do
    ENV['ENSURE_LABELS_DEFINED'] = 'strict'
    ENV['GITHUB_TOKEN'] = 'a-token'
    ENV['ENSURE_PR_IS_LABELLED'] = 'true'
    ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = ''
    ENV['ENSURE_TEMPLATE_TEXT_REMOVED_MESSAGE'] = 'Oh no!'

    allow(runner).to receive(:warn) { |text| warnings << text }
    allow(runner).to receive(:event) { event }
    allow(GithubClient).to receive(:new) { github_client }
    allow(RepoLabelChecker).to receive(:new).with(event, github_client) { repo_label_checker }
  end

  def expect_failure(*expected_warnings)
    aggregate_failures do
      expect { runner.run }.to raise_error(SystemExit) do |err|
        expect(err.status).to eq(1)
      end

      expect(warnings).to contain_exactly(*expected_warnings)
    end
  end

  def expect_success
    aggregate_failures do
      # See https://medium.com/@rvedotrc/rspec-and-exceptions-7d3fc5b17805
      expect do
        runner.run
      end.not_to raise_error

      expect(warnings).to be_empty
    end
  end

  it 'validates ENSURE_LABELS_DEFINED' do
    ENV['ENSURE_LABELS_DEFINED'] = 'well this is awkward'

    expect_failure('ERROR: ensure_labels_defined must be one of: strict, names-only, false')
  end

  it 'validates ENSURE_PR_IS_LABELLED' do
    ENV['ENSURE_PR_IS_LABELLED'] = 'well this is awkward'

    expect_failure('ERROR: ensure_pr_is_labelled must be one of: true, false')
  end

  describe 'ENSURE_LABELS_DEFINED' do
    before do
      ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = ''
      event['pull_request']['labels'] = [{ 'name' => 'risk:none' }]
    end

    it 'respects false' do
      ENV['ENSURE_LABELS_DEFINED'] = 'false'
      expect(repo_label_checker).not_to receive(:run)
      expect_success
    end

    it 'calls in strict mode if strict' do
      ENV['ENSURE_LABELS_DEFINED'] = 'strict'
      expect(repo_label_checker).to receive(:run).with(strict: true, definitions: Runner::RISK_LABELS)
      expect_success
    end

    it 'calls in non-strict mode if names-only' do
      ENV['ENSURE_LABELS_DEFINED'] = 'names-only'
      expect(repo_label_checker).to receive(:run).with(strict: false, definitions: Runner::RISK_LABELS)
      expect_success
    end
  end

  describe 'ENSURE_TEMPLATE_TEXT_REMOVED_TEXT' do
    before do
      ENV['ENSURE_LABELS_DEFINED'] = 'false'
      event['pull_request']['labels'] = [{ 'name' => 'risk:none' }]
    end

    it 'skips if the text is empty' do
      ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = ''
      expect_success
    end

    it 'fails if the text is present' do
      ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = 'one'
      expect_failure('ERROR: Oh no!')
    end

    it 'passes if the text is absent' do
      ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = 'foo'
      expect_success
    end
  end

  describe 'ENSURE_PR_IS_LABELLED' do
    before do
      ENV['ENSURE_LABELS_DEFINED'] = 'false'
      ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = ''
    end

    it 'fails if there are no risk labels' do
      event['pull_request']['labels'] = [{ 'name' => 'risk:not_a_recognised_label' }]
      expect_failure('ERROR: Please apply exactly one of the risk labels: risk:none, risk:low, risk:medium, risk:high')
    end

    it 'passes if there is one risk label' do
      event['pull_request']['labels'] = [{ 'name' => 'risk:medium' }]
      expect_success
    end

    it 'fails if there are multiple risk labels' do
      event['pull_request']['labels'] = [{ 'name' => 'risk:low' }, { 'name' => 'risk:high' }]
      expect_failure('ERROR: Please apply exactly one of the risk labels: risk:none, risk:low, risk:medium, risk:high')
    end
  end

  it 'reports all the (non-invocation) problems at once' do
    ENV['ENSURE_LABELS_DEFINED'] = 'false'
    ENV['ENSURE_TEMPLATE_TEXT_REMOVED_TEXT'] = 'one'
    event['pull_request']['labels'] = []

    expect_failure(
      'ERROR: Oh no!',
      'ERROR: Please apply exactly one of the risk labels: risk:none, risk:low, risk:medium, risk:high'
    )
  end
end
