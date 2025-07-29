# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AwsAccount, type: :model do
  describe 'validations' do
    let(:aws_account) { build(:aws_account) }

    it { should validate_presence_of(:account_id) }
    it { should validate_uniqueness_of(:account_id) }
    it { should validate_length_of(:account_id).is_equal_to(12) }
    it { should validate_presence_of(:access_key) }
    it { should validate_length_of(:access_key).is_at_least(16).is_at_most(128) }
    it { should validate_presence_of(:secret_key) }
    it { should validate_length_of(:secret_key).is_at_least(40) }
    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_length_of(:description).is_at_most(500) }

    it 'validates account_id format' do
      aws_account.account_id = 'invalid'
      expect(aws_account).not_to be_valid
      expect(aws_account.errors[:account_id]).to include('必须是12位数字的AWS账号ID')
    end

    it 'validates access_key format' do
      aws_account.access_key = 'invalid'
      expect(aws_account).not_to be_valid
      expect(aws_account.errors[:access_key]).to include('不是有效的AWS Access Key格式')
    end
  end

  describe 'associations' do
    it { should have_many(:account_quotas).dependent(:destroy) }
    it { should have_many(:quota_definitions).through(:account_quotas) }
    it { should have_many(:refresh_jobs).dependent(:nullify) }
    it { should have_many(:audit_logs).dependent(:destroy) }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(active: 0, inactive: 1, sold_out: 2, maintenance: 3) }
    it { should define_enum_for(:connection_status).with_values(connected: 0, error: 1, unknown: 2) }
  end

  describe 'scopes' do
    let!(:active_account) { create(:aws_account, status: :active) }
    let!(:inactive_account) { create(:aws_account, status: :inactive) }

    it 'filters active accounts' do
      expect(AwsAccount.active).to include(active_account)
      expect(AwsAccount.active).not_to include(inactive_account)
    end

    it 'searches by name, account_id, and description' do
      account = create(:aws_account, name: 'test account', description: 'test description')
      expect(AwsAccount.search('test')).to include(account)
    end
  end

  describe 'callbacks' do
    it 'sets default values before validation' do
      aws_account = AwsAccount.new
      aws_account.valid?
      expect(aws_account.status).to eq('active')
      expect(aws_account.connection_status).to eq('unknown')
    end

    it 'tests connection after create' do
      expect_any_instance_of(AwsAccount).to receive(:test_connection_async)
      create(:aws_account)
    end
  end

  describe 'tags handling' do
    it 'converts string tags to array' do
      aws_account = create(:aws_account, tags: 'tag1,tag2,tag3')
      expect(aws_account.tags).to eq(['tag1', 'tag2', 'tag3'])
    end

    it 'handles array tags' do
      aws_account = create(:aws_account, tags: ['tag1', 'tag2'])
      expect(aws_account.tags).to eq(['tag1', 'tag2'])
    end

    it 'removes empty tags' do
      aws_account = create(:aws_account, tags: 'tag1, , tag2,')
      expect(aws_account.tags).to eq(['tag1', 'tag2'])
    end
  end

  describe 'soft delete' do
    let(:aws_account) { create(:aws_account) }

    it 'marks account as deleted' do
      aws_account.soft_delete!
      expect(aws_account.deleted?).to be true
      expect(aws_account.inactive?).to be true
    end

    it 'restores deleted account' do
      aws_account.soft_delete!
      aws_account.restore!
      expect(aws_account.deleted?).to be false
      expect(aws_account.active?).to be true
    end
  end

  describe 'connection testing' do
    let(:aws_account) { create(:aws_account) }

    it 'updates connection status on successful test' do
      aws_account.test_connection
      expect(aws_account.connection_status).to eq('connected')
      expect(aws_account.last_connection_test_at).to be_present
    end

    it 'handles connection errors' do
      allow(aws_account).to receive(:update!).and_raise(StandardError.new('Connection failed'))
      result = aws_account.test_connection
      expect(result).to be false
      expect(aws_account.connection_status).to eq('error')
      expect(aws_account.connection_error_message).to eq('Connection failed')
    end
  end

  describe 'quota management' do
    let(:aws_account) { create(:aws_account) }
    let(:high_quota_definition) { create(:quota_definition, quota_level: 'high') }
    let(:low_quota_definition) { create(:quota_definition, quota_level: 'low') }

    before do
      create(:account_quota, aws_account: aws_account, quota_definition: high_quota_definition, current_quota: 100)
      create(:account_quota, aws_account: aws_account, quota_definition: low_quota_definition, current_quota: 10)
    end

    it 'identifies high quota accounts' do
      expect(aws_account.has_high_quota?).to be true
    end

    it 'returns available models' do
      expect(aws_account.available_models).to include(high_quota_definition.claude_model_name)
      expect(aws_account.available_models).to include(low_quota_definition.claude_model_name)
    end

    it 'returns model quotas' do
      quotas = aws_account.model_quotas(high_quota_definition.claude_model_name)
      expect(quotas).to be_present
    end
  end

  describe 'display helpers' do
    let(:aws_account) { create(:aws_account) }

    it 'masks access key' do
      aws_account.access_key = 'AKIAIOSFODNN7EXAMPLE'
      expect(aws_account.masked_access_key).to eq('AKIA...MPLE')
    end

    it 'masks secret key' do
      expect(aws_account.masked_secret_key).to eq('••••••••••••••••')
    end

    it 'returns display status' do
      expect(aws_account.display_status).to be_present
    end

    it 'returns display connection status' do
      expect(aws_account.display_connection_status).to be_present
    end
  end

  describe 'auditable configuration' do
    let(:aws_account) { create(:aws_account) }

    it 'filters sensitive data from audit logs' do
      changes = {
        'access_key' => ['old_key', 'new_key'],
        'secret_access_key_encrypted' => ['old_encrypted', 'new_encrypted'],
        'name' => ['old_name', 'new_name']
      }
      
      filtered = aws_account.send(:filter_auditable_changes, changes)
      
      expect(filtered['access_key']).to eq([aws_account.masked_access_key, aws_account.masked_access_key])
      expect(filtered).not_to have_key('secret_access_key_encrypted')
      expect(filtered['name']).to eq(['old_name', 'new_name'])
    end

    it 'includes audit metadata' do
      metadata = aws_account.audit_metadata
      expect(metadata).to include(:account_name, :account_status, :connection_status, :has_high_quota, :total_quotas)
    end
  end
end