require 'rails_helper'

RSpec.describe EventFactory do
  subject(:factory) {
    EventFactory.new(
      external_types: { 'circleci' => CircleCiEvent },
      internal_types: { 'manual_test' => ManualTestEvent },
    )
  }

  describe '#create' do
    let(:payload) { { 'foo' => 'bar' } }
    let(:user_email) { 'foo@bar.com' }

    let(:created_event) { factory.create(event_type, payload, user_email) }

    context 'with an external event type' do
      let(:event_type) { 'circleci' }

      it 'returns an instance of the correct class' do
        expect(created_event).to be_an_instance_of(CircleCiEvent)
      end

      it 'stores the payload in the event details' do
        expect(created_event.details).to eq('foo' => 'bar')
      end
    end

    context 'with an internal event type' do
      let(:event_type) { 'manual_test' }

      it 'returns an instance of the correct class' do
        expect(created_event).to be_an_instance_of(ManualTestEvent)
      end

      it 'stores the payload in the event details, including the user email' do
        expect(created_event.details).to eq('foo' => 'bar', 'email' => 'foo@bar.com')
      end

      context 'when the user email is nil' do
        let(:user_email) { nil }

        it 'omits the email from the payload' do
          expect(created_event.details).to eq('foo' => 'bar')
        end
      end
    end

    context 'with an unrecognized event type' do
      let(:event_type) { 'unexistent' }

      it 'raises an error' do
        expect { created_event }.to raise_error("Unrecognized event type 'unexistent'")
      end
    end
  end

  describe '#supported_external_types' do
    it 'returns a list of supported external event types' do
      expect(factory.supported_external_types).to eq(%w(circleci))
    end
  end
end