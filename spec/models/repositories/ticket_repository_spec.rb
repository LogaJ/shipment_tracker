# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Repositories::TicketRepository do
  subject(:repository) { Repositories::TicketRepository.new(git_repository_location: git_repo_location) }

  let(:git_repo_location) { class_double(GitRepositoryLocation) }

  describe '#table_name' do
    let(:active_record_class) { class_double(Snapshots::Ticket, table_name: 'the_table_name') }

    subject(:repository) { Repositories::TicketRepository.new(active_record_class) }

    it 'delegates to the active record class backing the repository' do
      expect(repository.table_name).to eq('the_table_name')
    end
  end

  describe '#tickets_for_* queries' do
    let(:attrs_a) {
      { key: 'JIRA-A',
        summary: 'JIRA-A summary',
        status: 'Done',
        paths: [
          feature_review_path(frontend: 'NON3', backend: 'NON2'),
          feature_review_path(frontend: 'abc', backend: 'NON1'),
        ],
        event_created_at: 9.days.ago,
        versions: %w(abc NON1 NON3 NON2) }
    }

    let(:attrs_b) {
      { key: 'JIRA-B',
        summary: 'JIRA-B summary',
        status: 'Done',
        paths: [
          feature_review_path(frontend: 'def', backend: 'NON4'),
          feature_review_path(frontend: 'NON3', backend: 'ghi'),
        ],
        event_created_at: 7.days.ago,
        versions: %w(def NON4 NON3 ghi) }
    }

    let(:attrs_c) {
      { key: 'JIRA-C',
        summary: 'JIRA-C summary',
        status: 'Done',
        paths: [feature_review_path(frontend: 'NON3', backend: 'NON2')],
        event_created_at: 5.days.ago,
        versions: %w(NON3 NON2) }
    }

    let(:attrs_d) {
      { key: 'JIRA-D',
        summary: 'JIRA-D summary',
        status: 'Done',
        paths: [feature_review_path(frontend: 'NON3', backend: 'ghi')],
        event_created_at: 3.days.ago,
        versions: %w(NON3 ghi) }
    }

    let(:attrs_e1) {
      { key: 'JIRA-E',
        summary: 'JIRA-E summary',
        status: 'Done',
        paths: [feature_review_path(frontend: 'abc', backend: 'NON1')],
        event_created_at: 1.day.ago,
        versions: %w(abc NON1) }
    }

    let(:attrs_e2) {
      { key: 'JIRA-E',
        summary: 'JIRA-E summary',
        status: 'Done',
        paths: [feature_review_path(frontend: 'abc', backend: 'NON1')],
        event_created_at: 1.day.ago,
        versions: %w(abc NON1) }
    }

    before :each do
      Snapshots::Ticket.create!(attrs_a)
      Snapshots::Ticket.create!(attrs_b)
      Snapshots::Ticket.create!(attrs_c)
      Snapshots::Ticket.create!(attrs_d)
      Snapshots::Ticket.create!(attrs_e1)
      Snapshots::Ticket.create!(attrs_e2)
    end

    describe '#tickets_for_path' do
      context 'with unspecified time' do
        subject {
          repository.tickets_for_path(
            feature_review_path(frontend: 'abc', backend: 'NON1'),
          )
        }

        it { is_expected.to match_array([Ticket.new(attrs_a), Ticket.new(attrs_e2)]) }
      end

      context 'with a specified time' do
        subject {
          repository.tickets_for_path(
            feature_review_path(frontend: 'abc', backend: 'NON1'),
            at: 4.days.ago,
          )
        }

        it { is_expected.to match_array([Ticket.new(attrs_a)]) }
      end
    end

    describe '#tickets_for_versions' do
      context 'when given an array' do
        it 'returns all tickets containing the versions' do
          tickets = repository.tickets_for_versions(%w(abc def))

          expect(tickets).to match_array([
            Ticket.new(attrs_a),
            Ticket.new(attrs_b),
            Ticket.new(attrs_e2),
          ])
        end
      end

      context 'when given a string' do
        it 'returns all tickets containing the versions' do
          tickets = repository.tickets_for_versions('abc')

          expect(tickets).to match_array([
            Ticket.new(attrs_a),
            Ticket.new(attrs_e2),
          ])
        end
      end
    end
  end

  describe '#apply' do
    let(:time) { Time.current.change(usec: 0) }
    let(:times) { [time - 3.hours, time - 2.hours, time - 1.hour, time - 1.minute] }
    let(:url) { feature_review_url(app: 'foo') }
    let(:path) { feature_review_path(app: 'foo') }
    let(:ticket_defaults) { { paths: [path], versions: %w(foo), version_timestamps: { 'foo' => nil } } }
    let(:repository_location) { instance_double(GitRepositoryLocation, full_repo_name: 'owner/frontend') }

    before do
      allow(git_repo_location).to receive(:find_by_name).and_return(repository_location)
      allow(CommitStatusUpdateJob).to receive(:perform_later)
    end

    it 'only snapshots tickets that contain a Feature Review' do
      event = build(:jira_event)
      expect { repository.apply(event) }.to_not change { repository.store.count }

      event = build(:jira_event, comment_body: "Feature Review #{url}")
      expect { repository.apply(event) }.to change { repository.store.count }
    end

    it 'projects latest associated tickets' do
      jira_1 = { key: 'JIRA-1', summary: 'Ticket 1' }
      ticket_1 = jira_1.merge(ticket_defaults)

      repository.apply(build(:jira_event, :created, jira_1.merge(comment_body: url)))
      results = repository.tickets_for_path(path)
      expect(results).to eq([
        Ticket.new(ticket_1.merge(status: 'To Do')),
      ])

      repository.apply(build(:jira_event, :started, jira_1))
      results = repository.tickets_for_path(path)
      expect(results).to eq([Ticket.new(ticket_1.merge(status: 'In Progress'))])

      repository.apply(build(:jira_event, :approved, jira_1.merge(created_at: time)))
      results = repository.tickets_for_path(path)
      expect(results).to eq([
        Ticket.new(
          ticket_1.merge(
            status: 'Ready for Deployment', approved_at: time, event_created_at: time,
          ),
        ),
      ])

      repository.apply(build(:jira_event, :deployed, jira_1.merge(created_at: time + 1.hour)))
      results = repository.tickets_for_path(path)
      expect(results).to eq([
        Ticket.new(ticket_1.merge(
                     status: 'Done', approved_at: time, event_created_at: time + 1.hour,
        )),
      ])

      repository.apply(build(:jira_event, :rejected, jira_1.merge(created_at: time + 2.hours)))
      results = repository.tickets_for_path(path)
      expect(results).to eq([
        Ticket.new(ticket_1.merge(
                     status: 'In Progress', approved_at: nil, event_created_at: time + 2.hours,
        )),
      ])
    end

    it 'snapshots tickets linked to a Feature Review' do
      jira_1 = { key: 'JIRA-1', summary: 'Ticket 1' }
      jira_4 = { key: 'JIRA-4', summary: 'Ticket 4' }
      ticket_1 = jira_1.merge(ticket_defaults)
      ticket_4 = jira_4.merge(ticket_defaults)

      [
        build(:jira_event, :created, jira_1),
        build(:jira_event, :started, jira_1),
        build(:jira_event, :development_completed, jira_1.merge(comment_body: "Please review #{url}")),

        build(:jira_event, :created, key: 'JIRA-2'),
        build(:jira_event, :created, key: 'JIRA-3', comment_body: 'http://example.com/feature_reviews/fake'),

        build(:jira_event, :created, jira_4),
        build(:jira_event, :started, jira_4),
        build(:jira_event, :development_completed, jira_4.merge(comment_body: url)),

        build(:jira_event, :deployed, jira_1.merge(created_at: time)),
      ].each do |event|
        repository.apply(event)
      end

      expect(repository.tickets_for_path(path)).to match_array([
        Ticket.new(
          ticket_1.merge(
            status: 'Done', approved_at: time, event_created_at: time,
          ),
        ),
        Ticket.new(ticket_4.merge(status: 'Ready For Review')),
      ])
    end

    it 'ignores events that are not JIRA issues' do
      event = build(:jira_event_user_created)

      expect { repository.apply(event) }.to_not change { repository.store.count }
    end

    context 'when multiple feature reviews are referenced in the same JIRA ticket' do
      let(:url1) { feature_review_url(app1: 'one') }
      let(:url2) { feature_review_url(app2: 'two') }
      let(:path1) { feature_review_path(app1: 'one') }
      let(:path2) { feature_review_path(app2: 'two') }

      subject(:repository1) { Repositories::TicketRepository.new }

      it 'projects the ticket referenced in the JIRA comments for each repository' do
        [
          build(:jira_event, key: 'JIRA-1', comment_body: "Review #{url1}", created_at: times[0]),
          build(:jira_event, key: 'JIRA-1', comment_body: "Review [FR link|#{url2}]", created_at: times[1]),
          build(:jira_event, key: 'JIRA-1', comment_body: "Review #{url1}", created_at: times[2]),
        ].each do |event|
          repository1.apply(event)
        end

        expect(repository1.tickets_for_path(path1)).to eq([
          Ticket.new(
            key: 'JIRA-1',
            paths: [path1, path2],
            versions: %w(one two),
            version_timestamps: { 'one' => times[0], 'two' => times[1] }),
        ])
      end
    end

    context 'with at specified' do
      it 'returns the state at that moment' do
        jira_1 = { key: 'JIRA-1', summary: 'Ticket 1' }
        jira_2 = { key: 'JIRA-2', summary: 'Ticket 2' }
        ticket_1 = jira_1.merge(ticket_defaults)

        [
          build(:jira_event, :created, jira_1.merge(comment_body: url, created_at: times[0])),
          build(:jira_event, :approved, jira_1.merge(created_at: times[1])),
          build(:jira_event, :created, jira_2.merge(created_at: times[2])),
          build(:jira_event, :created, jira_2.merge(comment_body: url, created_at: times[3])),
        ].each do |event|
          repository.apply(event)
        end

        expect(repository.tickets_for_path(path, at: times[2])).to match_array([
          Ticket.new(
            ticket_1.merge(
              status: 'Ready for Deployment',
              approved_at: times[1],
              event_created_at: times[1],
              version_timestamps: { 'foo' => times[0] },
            ),
          ),
        ])
      end
    end

    describe 'GitHub Commit Statuses' do
      before do
        allow(CommitStatusUpdateJob).to receive(:perform_later)
        allow(Rails.configuration).to receive(:data_maintenance_mode).and_return(false)
        allow(git_repo_location).to receive(:find_by_name).with('frontend').and_return(repository_location)
      end

      context 'when in maintenance mode' do
        before do
          allow(Rails.configuration).to receive(:data_maintenance_mode).and_return(true)
        end

        it 'does not schedule commit status updates' do
          expect(CommitStatusUpdateJob).to_not receive(:perform_later)

          event = build(:jira_event, comment_body: feature_review_url(frontend: 'abc'))
          repository.apply(event)
        end
      end

      context 'when ticket event is for a comment' do
        context 'when event contains a Feature Review link' do
          let(:event) {
            build(
              :jira_event,
              key: 'JIRA-XYZ',
              comment_body: "#{feature_review_url(frontend: 'abc')} #{feature_review_url(frontend: 'def')}",
            )
          }

          it 'schedules commit status updates for each version' do
            expect(CommitStatusUpdateJob).to receive(:perform_later).with(
              full_repo_name: 'owner/frontend',
              sha: 'abc',
            )
            expect(CommitStatusUpdateJob).to receive(:perform_later).with(
              full_repo_name: 'owner/frontend',
              sha: 'def',
            )
            repository.apply(event)
          end
        end

        context 'when event does not contain a Feature Review link' do
          let(:event) {
            build(
              :jira_event,
              key: 'JIRA-XYZ',
              comment_body: 'Just some update',
              created_at: time,
            )
          }

          before do
            event = build(
              :jira_event,
              key: 'JIRA-XYZ',
              comment_body: "Reviews: http://foo.com#{feature_review_path(frontend: 'abc')}",
              created_at: time - 1.hour,
            )
            repository.apply(event)
          end

          it 'does not schedule a commit status update' do
            expect(CommitStatusUpdateJob).to_not receive(:perform_later)
            repository.apply(event)
          end
        end
      end

      context 'when ticket event is for an approval' do
        let(:approval_event) { build(:jira_event, :approved, key: 'JIRA-XYZ', created_at: time) }

        before do
          event = build(
            :jira_event,
            key: 'JIRA-XYZ',
            comment_body: "Reviews: http://foo.com#{feature_review_path(frontend: 'abc')}",
            created_at: time - 1.hour,
          )
          repository.apply(event)
        end

        it 'schedules a commit status update for each version' do
          expect(CommitStatusUpdateJob).to receive(:perform_later).with(
            full_repo_name: 'owner/frontend',
            sha: 'abc',
          )
          repository.apply(approval_event)
        end
      end

      context 'when ticket event is for an unapproval' do
        let(:unapproval_event) { build(:jira_event, :rejected, key: 'JIRA-XYZ', created_at: time) }

        before do
          event = build(
            :jira_event,
            key: 'JIRA-XYZ',
            comment_body: "Reviews: http://foo.com#{feature_review_path(frontend: 'abc')}",
            created_at: time - 1.hour,
          )
          repository.apply(event)
        end

        it 'schedules a commit status update for each version' do
          expect(CommitStatusUpdateJob).to receive(:perform_later).with(
            full_repo_name: 'owner/frontend',
            sha: 'abc',
          )
          repository.apply(unapproval_event)
        end
      end

      context 'when ticket event is for any other activity' do
        let(:random_event) { build(:jira_event, key: 'JIRA-XYZ', created_at: time) }

        before do
          event = build(
            :jira_event,
            key: 'JIRA-XYZ',
            comment_body: "Reviews: http://foo.com#{feature_review_path(frontend: 'abc')}",
            created_at: time - 1.hour,
          )
          repository.apply(event)
        end

        it 'does not schedule a commit status update' do
          expect(CommitStatusUpdateJob).not_to receive(:perform_later)
          repository.apply(random_event)
        end
      end

      context 'when repository location can not be found' do
        let(:event) {
          build(
            :jira_event,
            key: 'JIRA-XYZ',
            comment_body: "Reviews: http://foo.com#{feature_review_path(frontend: 'abc')}",
            created_at: time,
          )
        }

        before do
          allow(git_repo_location).to receive(:find_by_name).with('frontend').and_return(nil)
        end

        it 'does not schedule a commit status update' do
          expect(CommitStatusUpdateJob).to_not receive(:perform_later)
          repository.apply(event)
        end
      end
    end
  end
end
