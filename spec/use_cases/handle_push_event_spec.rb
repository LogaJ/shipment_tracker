# frozen_string_literal: true

require 'rails_helper'
require 'handle_push_event'
require 'payloads/github'

RSpec.describe HandlePushEvent do
  let(:default_payload_data) {
    {
      'ref' => 'refs/heads/branch_name',
      'before' => 'abc1234',
      'after' => 'def1234',
      'head_commit' => { 'id' => 'fca1234' },
      'created' => false,
      'deleted' => false,
      'repository' => { 'full_name' => 'owner/repo_name' },
    }
  }
  let(:payload_data) { default_payload_data }

  let(:payload) { Payloads::Github.new(payload_data) }

  before do
    allow_any_instance_of(CommitStatus).to receive(:reset)
    allow(GitRepositoryLocation).to receive(:repo_tracked?).and_return(true)
  end

  describe 'validation' do
    it 'fails if repo not audited' do
      allow(GitRepositoryLocation).to receive(:repo_tracked?).and_return(false)

      result = HandlePushEvent.run(payload)

      expect(result).to fail_with(:repo_not_under_audit)
    end

    it 'fails if event is for pushing an annotated tag' do
      github_payload = instance_double(Payloads::Github, push_annotated_tag?: true, branch_deleted?: false)

      result = HandlePushEvent.run(github_payload)
      expect(result).to fail_with(:annotated_tag)
    end

    context 'when branch is deleted' do
      let(:payload_data) { default_payload_data.merge('deleted' => true) }

      it 'fails with branch_deleted' do
        result = HandlePushEvent.run(payload)
        expect(result).to fail_with(:branch_deleted)
      end
    end
  end

  describe 'updating remote head' do
    context 'when repo not found' do
      before do
        allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(nil)
      end

      it 'fails' do
        result = HandlePushEvent.run(payload)
        expect(result).to fail_with(:repo_not_found)
      end
    end

    context 'repo exists' do
      let(:git_repository_location) { instance_double(GitRepositoryLocation) }
      let(:git_repository_loader) { instance_double(GitRepositoryLoader) }
      let(:git_repository) { instance_double(GitRepository) }

      before do
        allow_any_instance_of(CommitStatus).to receive(:not_found)

        allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(git_repository_location)

        allow(GitRepositoryLoader).to receive(:from_rails_config) { git_repository_loader }
        allow(git_repository_loader).to receive(:load) { git_repository }
        allow(git_repository).to receive(:commit_on_master?) { false }
      end

      it 'updates the corresponding repository location' do
        expect(git_repository_location).to receive(:update).with(remote_head: 'fca1234')
        HandlePushEvent.run(payload)
      end
    end
  end

  describe 'resetting commit status' do
    let(:git_repository_location) { instance_double(GitRepositoryLocation) }
    let(:git_repository_loader) { instance_double(GitRepositoryLoader) }
    let(:git_repository) { instance_double(GitRepository) }
    let(:commit_status) { instance_double(CommitStatus, not_found: nil, reset: nil) }

    before do
      allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(git_repository_location)
      allow(git_repository_location).to receive(:update)

      allow(GitRepositoryLoader).to receive(:from_rails_config) { git_repository_loader }
      allow(git_repository_loader).to receive(:load) { git_repository }
      allow(git_repository).to receive(:commit_on_master?) { false }
    end

    it 'resets the GitHub commit status' do
      allow(CommitStatus).to receive(:new).with(
        full_repo_name: payload.full_repo_name,
        sha: payload.after_sha,
      ).and_return(commit_status)
      expect(commit_status).to receive(:reset)

      HandlePushEvent.run(payload)
    end

    context 'commit is pushed to master' do
      let(:payload_data) { default_payload_data.merge('ref' => 'refs/heads/master') }

      it 'fails with :protected_branch' do
        expect_any_instance_of(CommitStatus).not_to receive(:reset)

        result = HandlePushEvent.run(payload)
        expect(result).to fail_with(:protected_branch)
      end
    end
  end

  describe 'relinking tickets' do
    let(:ticket_repo) { instance_double(Repositories::TicketRepository, tickets_for_versions: tickets) }
    let(:git_repo_loader) { instance_double(GitRepositoryLoader) }
    let(:git_repo) { instance_double(GitRepository) }
    let(:on_master) { false }
    let(:tickets) { [double] }

    before do
      git_repository_location = instance_double(GitRepositoryLocation, update: nil)
      allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(git_repository_location)
      allow(Repositories::TicketRepository).to receive(:new).and_return(ticket_repo)
      allow(GitRepositoryLoader).to receive(:from_rails_config) { git_repo_loader }
      allow(git_repo_loader).to receive(:load) { git_repo }
      allow(git_repo).to receive(:commit_on_master?) { on_master }
    end

    context 'when new branch created' do
      let(:payload_data) { default_payload_data.merge('created' => true) }
      let(:commit_status) { instance_double(CommitStatus, not_found: nil, reset: nil) }

      before do
        allow_any_instance_of(CommitStatus).to receive(:not_found)
      end

      it 'does not re-link' do
        expect(JiraClient).not_to receive(:post_comment)

        HandlePushEvent.run(payload)
      end

      it 'posts not found status' do
        allow(CommitStatus).to receive(:new).with(
          full_repo_name: 'owner/repo_name',
          sha: 'def1234',
        ).and_return(commit_status)
        expect(commit_status).to receive(:not_found)

        HandlePushEvent.run(payload)
      end
    end

    context 'when commit is already on master' do
      let(:on_master) { true }
      let(:commit_status) { instance_double(CommitStatus, not_found: nil, reset: nil) }

      before do
        allow_any_instance_of(CommitStatus).to receive(:not_found)
      end

      it 'does not re-link' do
        expect(JiraClient).not_to receive(:post_comment)

        HandlePushEvent.run(payload)
      end

      it 'posts not found status' do
        allow(CommitStatus).to receive(:new).with(
          full_repo_name: 'owner/repo_name',
          sha: 'def1234',
        ).and_return(commit_status)
        expect(commit_status).to receive(:not_found)

        HandlePushEvent.run(payload)
      end
    end

    context 'when there are no previously linked tickets' do
      let(:tickets) { [] }
      let(:commit_status) { instance_double(CommitStatus, not_found: nil, reset: nil) }

      before do
        allow_any_instance_of(CommitStatus).to receive(:not_found)
      end

      it 'does not post a JIRA comment' do
        expect(JiraClient).not_to receive(:post_comment)

        HandlePushEvent.run(payload)
      end

      it 'posts a "failure" commit status to GitHub' do
        allow(CommitStatus).to receive(:new).with(
          full_repo_name: 'owner/repo_name',
          sha: 'def1234',
        ).and_return(commit_status)
        expect(commit_status).to receive(:not_found)

        HandlePushEvent.run(payload)
      end
    end

    context 'when there are previously linked tickets' do
      let(:payload_data) { default_payload_data.merge('repository' => { 'full_name' => 'owner/app1' }) }

      let(:tickets) {
        [
          instance_double(Ticket, key: 'ISSUE-1', paths: paths_issue1),
          instance_double(Ticket, key: 'ISSUE-2', paths: paths_issue2),
        ]
      }

      context 'with multiple Feature Reviews' do
        context 'with one app per Feature Review' do
          let(:paths_issue1) {
            [
              feature_review_path(app1: 'abc5678'),
              feature_review_path(app1: 'abc1234'),
            ]
          }

          let(:paths_issue2) {
            [
              feature_review_path(app1: 'bcd1234'),
              feature_review_path(app1: 'ced1234'),
            ]
          }

          it 'posts linking comment to JIRA with relevant Feature Review' do
            expect(JiraClient).to receive(:post_comment).once.with(
              tickets.first.key,
              "[Feature ready for review|#{feature_review_url(app1: 'def1234')}]",
            )

            HandlePushEvent.run(payload)
          end
        end

        context 'with multiple apps per Feature Review' do
          let(:payload_data) { default_payload_data.merge('repository' => { 'full_name' => 'owner/app2' }) }

          let(:paths_issue1) {
            [
              feature_review_path(app1: 'bcd1234', app2: 'abc1234'),
              feature_review_path(app3: 'ccp1234', app4: 'ced1234'),
            ]
          }

          let(:paths_issue2) {
            [
              feature_review_path(app2: 'abc1234', app5: 'fdc1234'),
            ]
          }

          it 'posts linking comment to JIRA with relevant Feature Review' do
            expect(JiraClient).to receive(:post_comment).once.ordered.with(
              tickets.first.key,
              "[Feature ready for review|#{feature_review_url(app1: 'bcd1234', app2: 'def1234')}]",
            )
            expect(JiraClient).to receive(:post_comment).once.ordered.with(
              tickets.second.key,
              "[Feature ready for review|#{feature_review_url(app2: 'def1234', app5: 'fdc1234')}]",
            )

            HandlePushEvent.run(payload)
          end
        end
      end
    end

    context 'when the linking fails for a ticket' do
      let(:payload_data) { default_payload_data.merge('repository' => { 'full_name' => 'owner/app1' }) }
      let(:commit_status) { instance_double(CommitStatus, not_found: nil, reset: nil) }

      let(:tickets) {
        [
          instance_double(Ticket, key: 'ISSUE-1', paths: paths_issue1),
          instance_double(Ticket, key: 'ISSUE-2', paths: paths_issue2),
        ]
      }

      let(:paths_issue1) {
        [
          feature_review_path(app1: 'abc1234'),
          feature_review_path(app1: 'ced1234'),
        ]
      }

      let(:paths_issue2) {
        [
          feature_review_path(app1: 'abc1234'),
          feature_review_path(app1: 'caa1234'),
        ]
      }

      it 'rescues and continues to link other tickets' do
        allow_any_instance_of(CommitStatus).to receive(:error)
        allow(JiraClient).to receive(:post_comment).with(tickets.first.key, anything)
                                                   .and_raise(JiraClient::InvalidKeyError)

        expect(JiraClient).to receive(:post_comment).with(tickets.second.key, anything)

        HandlePushEvent.run(payload)
      end

      it 'posts "error" status to GitHub on InvalidKeyError' do
        allow(JiraClient).to receive(:post_comment).and_raise(JiraClient::InvalidKeyError)

        expect_any_instance_of(CommitStatus).to receive(:error).once

        HandlePushEvent.run(payload)
      end

      it 'posts "error" status to GitHub on any other error' do
        allow(JiraClient).to receive(:post_comment).and_raise

        allow(CommitStatus).to receive(:new).with(
          full_repo_name: 'owner/app1',
          sha: 'def1234',
        ).and_return(commit_status)
        expect(commit_status).to receive(:error).once

        HandlePushEvent.run(payload)
      end
    end
  end
end
