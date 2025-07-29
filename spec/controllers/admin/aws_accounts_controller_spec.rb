# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::AwsAccountsController, type: :controller do
  let(:admin_user) { create(:admin_user) }
  let(:aws_account) { create(:aws_account) }

  before do
    # Mock authentication
    allow(controller).to receive(:current_admin).and_return(admin_user)
    allow(controller).to receive(:authenticate_admin!).and_return(true)
  end

  describe 'GET #index' do
    let!(:active_account) { create(:aws_account, status: :active) }
    let!(:inactive_account) { create(:aws_account, status: :inactive) }

    it 'returns successful response' do
      get :index
      expect(response).to be_successful
      expect(assigns(:aws_accounts)).to include(active_account, inactive_account)
    end

    it 'filters by status' do
      get :index, params: { status: 'active' }
      expect(assigns(:aws_accounts)).to include(active_account)
      expect(assigns(:aws_accounts)).not_to include(inactive_account)
    end

    it 'filters by search term' do
      get :index, params: { search: active_account.name }
      expect(assigns(:aws_accounts)).to include(active_account)
    end

    it 'returns JSON response' do
      get :index, format: :json
      expect(response).to be_successful
      expect(response.content_type).to include('application/json')
    end
  end

  describe 'GET #show' do
    it 'returns successful response' do
      get :show, params: { id: aws_account.id }
      expect(response).to be_successful
      expect(assigns(:aws_account)).to eq(aws_account)
    end

    it 'loads account quotas' do
      quota_definition = create(:quota_definition)
      account_quota = create(:account_quota, aws_account: aws_account, quota_definition: quota_definition)
      
      get :show, params: { id: aws_account.id }
      expect(assigns(:account_quotas)).to include(account_quota)
    end

    it 'redirects if account not found' do
      get :show, params: { id: 'nonexistent' }
      expect(response).to redirect_to(admin_aws_accounts_path)
      expect(flash[:alert]).to eq('账号不存在')
    end
  end

  describe 'GET #new' do
    it 'returns successful response' do
      get :new
      expect(response).to be_successful
      expect(assigns(:aws_account)).to be_a_new(AwsAccount)
    end
  end

  describe 'GET #edit' do
    it 'returns successful response' do
      get :edit, params: { id: aws_account.id }
      expect(response).to be_successful
      expect(assigns(:aws_account)).to eq(aws_account)
    end
  end

  describe 'POST #create' do
    let(:valid_attributes) do
      {
        name: 'Test Account',
        account_id: '123456789012',
        access_key: 'AKIAIOSFODNN7EXAMPLE',
        secret_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'us-east-1',
        description: 'Test description'
      }
    end

    context 'with valid parameters' do
      it 'creates new AWS account' do
        expect {
          post :create, params: { aws_account: valid_attributes }
        }.to change(AwsAccount, :count).by(1)
      end

      it 'redirects to account show page' do
        post :create, params: { aws_account: valid_attributes }
        expect(response).to redirect_to(admin_aws_account_path(AwsAccount.last))
        expect(flash[:notice]).to include('创建成功')
      end

      it 'creates audit log' do
        expect {
          post :create, params: { aws_account: valid_attributes }
        }.to change(AuditLog, :count).by(1)
      end

      it 'queues refresh job for active accounts' do
        expect(RefreshQuotaJob).to receive(:perform_later)
        post :create, params: { aws_account: valid_attributes.merge(status: 'active') }
      end
    end

    context 'with invalid parameters' do
      let(:invalid_attributes) { { name: '', account_id: 'invalid' } }

      it 'does not create AWS account' do
        expect {
          post :create, params: { aws_account: invalid_attributes }
        }.not_to change(AwsAccount, :count)
      end

      it 'renders new template' do
        post :create, params: { aws_account: invalid_attributes }
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH #update' do
    let(:update_attributes) { { name: 'Updated Name', description: 'Updated description' } }

    context 'with valid parameters' do
      it 'updates AWS account' do
        patch :update, params: { id: aws_account.id, aws_account: update_attributes }
        aws_account.reload
        expect(aws_account.name).to eq('Updated Name')
        expect(aws_account.description).to eq('Updated description')
      end

      it 'redirects to account show page' do
        patch :update, params: { id: aws_account.id, aws_account: update_attributes }
        expect(response).to redirect_to(admin_aws_account_path(aws_account))
        expect(flash[:notice]).to include('更新成功')
      end

      it 'creates audit log' do
        expect {
          patch :update, params: { id: aws_account.id, aws_account: update_attributes }
        }.to change(AuditLog, :count).by(1)
      end

      it 'handles status changes' do
        expect(controller).to receive(:handle_status_change)
        patch :update, params: { id: aws_account.id, aws_account: { status: 'inactive' } }
      end
    end

    context 'with invalid parameters' do
      let(:invalid_attributes) { { name: '', account_id: 'invalid' } }

      it 'does not update AWS account' do
        original_name = aws_account.name
        patch :update, params: { id: aws_account.id, aws_account: invalid_attributes }
        aws_account.reload
        expect(aws_account.name).to eq(original_name)
      end

      it 'renders edit template' do
        patch :update, params: { id: aws_account.id, aws_account: invalid_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE #destroy' do
    it 'destroys AWS account' do
      aws_account # Create the account
      expect {
        delete :destroy, params: { id: aws_account.id }
      }.to change(AwsAccount, :count).by(-1)
    end

    it 'redirects to index page' do
      delete :destroy, params: { id: aws_account.id }
      expect(response).to redirect_to(admin_aws_accounts_path)
      expect(flash[:notice]).to include('删除成功')
    end

    it 'creates audit log' do
      aws_account # Create the account
      expect {
        delete :destroy, params: { id: aws_account.id }
      }.to change(AuditLog, :count).by(1)
    end
  end

  describe 'PATCH #activate' do
    let!(:inactive_account) { create(:aws_account, status: :inactive) }

    it 'activates AWS account' do
      patch :activate, params: { id: inactive_account.id }
      inactive_account.reload
      expect(inactive_account.active?).to be true
    end

    it 'queues refresh job' do
      expect(RefreshQuotaJob).to receive(:perform_later).with(inactive_account.id)
      patch :activate, params: { id: inactive_account.id }
    end

    it 'creates audit log' do
      expect {
        patch :activate, params: { id: inactive_account.id }
      }.to change(AuditLog, :count).by(1)
    end
  end

  describe 'PATCH #deactivate' do
    let!(:active_account) { create(:aws_account, status: :active) }

    it 'deactivates AWS account' do
      patch :deactivate, params: { id: active_account.id }
      active_account.reload
      expect(active_account.inactive?).to be true
    end

    it 'creates audit log' do
      expect {
        patch :deactivate, params: { id: active_account.id }
      }.to change(AuditLog, :count).by(1)
    end
  end

  describe 'POST #refresh_quota' do
    it 'queues refresh job' do
      expect(RefreshQuotaJob).to receive(:perform_later).with(aws_account.id, { job_type: :manual })
      post :refresh_quota, params: { id: aws_account.id }
    end

    it 'redirects with notice' do
      post :refresh_quota, params: { id: aws_account.id }
      expect(response).to redirect_to(admin_aws_account_path(aws_account))
      expect(flash[:notice]).to include('配额刷新任务已启动')
    end

    it 'creates audit log' do
      expect {
        post :refresh_quota, params: { id: aws_account.id }
      }.to change(AuditLog, :count).by(1)
    end
  end

  describe 'POST #bulk_refresh' do
    let!(:accounts) { create_list(:aws_account, 3, status: :active) }

    it 'creates bulk refresh job' do
      account_ids = accounts.map(&:id).map(&:to_s)
      expect {
        post :bulk_refresh, params: { account_ids: account_ids }
      }.to change(RefreshJob, :count).by(1)
    end

    it 'queues bulk refresh job' do
      account_ids = accounts.map(&:id).map(&:to_s)
      expect(BulkRefreshJob).to receive(:perform_later)
      post :bulk_refresh, params: { account_ids: account_ids }
    end

    it 'handles empty account selection' do
      post :bulk_refresh, params: { account_ids: [''] }
      expect(response).to redirect_to(admin_aws_accounts_path)
      expect(flash[:alert]).to eq('请选择要刷新的账号')
    end
  end

  describe 'GET #export' do
    let!(:accounts) { create_list(:aws_account, 2) }

    it 'exports CSV' do
      get :export, format: :csv
      expect(response).to be_successful
      expect(response.content_type).to include('text/csv')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    it 'exports JSON' do
      get :export, format: :json
      expect(response).to be_successful
      expect(response.content_type).to include('application/json')
      
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('accounts')
      expect(json_response).to have_key('exported_at')
      expect(json_response).to have_key('total_count')
    end
  end

  describe 'private methods' do
    describe '#filtered_accounts' do
      let!(:test_account) { create(:aws_account, name: 'test account', region: 'us-east-1') }
      let!(:other_account) { create(:aws_account, name: 'other account', region: 'us-west-2') }

      it 'filters by search term' do
        controller.params = { search: 'test' }
        filtered = controller.send(:filtered_accounts)
        expect(filtered).to include(test_account)
        expect(filtered).not_to include(other_account)
      end

      it 'filters by region' do
        controller.params = { region: 'us-east-1' }
        filtered = controller.send(:filtered_accounts)
        expect(filtered).to include(test_account)
        expect(filtered).not_to include(other_account)
      end
    end

    describe '#aws_account_params' do
      it 'permits required parameters' do
        params = ActionController::Parameters.new({
          aws_account: {
            name: 'Test',
            account_id: '123456789012',
            access_key: 'AKIATEST',
            secret_key: 'secret',
            region: 'us-east-1',
            status: 'active',
            description: 'Test',
            tags: 'tag1,tag2'
          }
        })
        
        controller.params = params
        permitted = controller.send(:aws_account_params)
        
        expect(permitted).to include(:name, :account_id, :access_key, :secret_key, :region, :status, :description, :tags)
      end
    end
  end
end