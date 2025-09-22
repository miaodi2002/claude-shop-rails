# AWS费用管理功能设计方案

## 概述
基于Rails最佳实践，为Claude Shop添加AWS账号费用管理功能，支持管理员查看最近2周的每日费用数据。

## 功能需求总结

### 用户需求
- **用户权限**: 仅管理员可访问
- **数据范围**: 每个账号最近2周的每日费用
- **费用精度**: USD货币，保留2位小数
- **更新方式**: 手动触发（单账号/批量）
- **错误处理**: 重试1次，显示AWS具体错误信息
- **前端展示**: 柱状图 + 日期范围选择

### 技术需求
- **数据持久化**: 保存所有历史费用数据
- **并行处理**: 批量更新时并行处理账号
- **容错机制**: 个别账号失败不影响其他账号

## 核心功能设计

### 1. 数据模型设计

#### DailyCost Model
```ruby
class DailyCost < ApplicationRecord
  belongs_to :aws_account
  
  # Validations
  validates :date, presence: true, uniqueness: { scope: :aws_account_id }
  validates :cost_amount, presence: true, numericality: { 
    greater_than_or_equal_to: 0,
    precision: 10,
    scale: 2
  }
  validates :currency, presence: true, inclusion: { in: %w[USD] }
  
  # Scopes
  scope :recent_weeks, ->(weeks = 2) { where(date: weeks.weeks.ago..Date.current) }
  scope :by_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :ordered_by_date, -> { order(:date) }
  
  # Display helpers
  def formatted_cost
    "$#{cost_amount.round(2)}"
  end
  
  def self.total_for_period(start_date, end_date)
    by_date_range(start_date, end_date).sum(:cost_amount)
  end
end
```

#### CostSyncLog Model
```ruby
class CostSyncLog < ApplicationRecord
  belongs_to :aws_account, optional: true
  
  # Enums
  enum status: { pending: 0, success: 1, failed: 2, in_progress: 3 }
  enum sync_type: { single_account: 0, batch_all: 1 }
  
  # Validations
  validates :sync_type, presence: true
  validates :aws_account, presence: true, if: :single_account?
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :failed_syncs, -> { where(status: :failed) }
  
  # Display helpers
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
  
  def success_rate
    return 0 if synced_dates_count.zero?
    (synced_dates_count / 14.0 * 100).round(2) # 14 days = 2 weeks
  end
end
```

### 2. AWS Cost Explorer服务层

#### AwsCostExplorerService
```ruby
class AwsCostExplorerService
  include Retryable
  
  MAX_RETRIES = 1
  RETRY_DELAY = 2.seconds
  
  def self.fetch_daily_costs(aws_account, start_date, end_date)
    new(aws_account).fetch_daily_costs(start_date, end_date)
  end
  
  def self.batch_sync_all_accounts
    aws_accounts = AwsAccount.active.includes(:daily_costs)
    
    # 并行处理所有账号
    Parallel.each(aws_accounts, in_threads: 5) do |account|
      CostSyncJob.perform_later(account.id)
    end
  end
  
  def initialize(aws_account)
    @aws_account = aws_account
    @client = setup_cost_explorer_client
  end
  
  def fetch_daily_costs(start_date, end_date)
    with_retry(max_retries: MAX_RETRIES, delay: RETRY_DELAY) do
      response = @client.get_cost_and_usage({
        time_period: {
          start: start_date.strftime('%Y-%m-%d'),
          end: end_date.strftime('%Y-%m-%d')
        },
        granularity: 'DAILY',
        metrics: ['UnblendedCost'],
        group_by: []
      })
      
      parse_cost_response(response)
    end
  rescue Aws::CostExplorer::Errors::ServiceError => e
    raise CostExplorerError, "AWS Cost Explorer Error: #{e.message}"
  end
  
  private
  
  def setup_cost_explorer_client
    Aws::CostExplorer::Client.new(
      access_key_id: @aws_account.access_key,
      secret_access_key: @aws_account.secret_key,
      region: @aws_account.region || 'us-east-1'
    )
  end
  
  def parse_cost_response(response)
    costs = {}
    
    response.results_by_time.each do |result|
      date = Date.parse(result.time_period.start)
      amount = result.total['UnblendedCost']['amount'].to_f
      
      costs[date] = amount
    end
    
    costs
  end
  
  def with_retry(max_retries:, delay:)
    retries = 0
    begin
      yield
    rescue StandardError => e
      if retries < max_retries
        retries += 1
        sleep(delay)
        retry
      else
        raise e
      end
    end
  end
  
  class CostExplorerError < StandardError; end
end
```

### 3. 后台任务设计

#### CostSyncJob
```ruby
class CostSyncJob < ApplicationJob
  queue_as :default
  
  def perform(account_id, date_range = nil)
    @aws_account = AwsAccount.find(account_id)
    @sync_log = create_sync_log
    
    sync_costs(date_range)
    
  rescue StandardError => e
    handle_sync_error(e)
  end
  
  private
  
  def create_sync_log
    CostSyncLog.create!(
      aws_account: @aws_account,
      sync_type: :single_account,
      status: :in_progress,
      started_at: Time.current
    )
  end
  
  def sync_costs(date_range = nil)
    start_date, end_date = determine_date_range(date_range)
    
    @sync_log.update!(started_at: Time.current)
    
    # 获取费用数据
    costs_data = AwsCostExplorerService.fetch_daily_costs(
      @aws_account, start_date, end_date
    )
    
    # 批量更新数据库
    synced_count = 0
    costs_data.each do |date, amount|
      DailyCost.find_or_create_by(
        aws_account: @aws_account,
        date: date
      ) do |daily_cost|
        daily_cost.cost_amount = amount
        daily_cost.currency = 'USD'
      end
      synced_count += 1
    end
    
    @sync_log.update!(
      status: :success,
      completed_at: Time.current,
      synced_dates_count: synced_count
    )
    
  rescue AwsCostExplorerService::CostExplorerError => e
    @sync_log.update!(
      status: :failed,
      completed_at: Time.current,
      error_message: e.message
    )
    raise e
  end
  
  def determine_date_range(date_range)
    if date_range
      [date_range[:start], date_range[:end]]
    else
      [2.weeks.ago.to_date, Date.current]
    end
  end
  
  def handle_sync_error(error)
    @sync_log&.update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error.message
    )
    
    Rails.logger.error "Cost sync failed for account #{@aws_account.id}: #{error.message}"
  end
end
```

#### BatchCostSyncJob
```ruby
class BatchCostSyncJob < ApplicationJob
  queue_as :default
  
  def perform(date_range = nil)
    @sync_log = create_batch_sync_log
    
    aws_accounts = AwsAccount.active
    
    # 并行处理所有账号
    Parallel.each(aws_accounts, in_threads: 5) do |account|
      begin
        CostSyncJob.perform_now(account.id, date_range)
      rescue StandardError => e
        Rails.logger.error "Batch sync failed for account #{account.id}: #{e.message}"
        # 继续处理其他账号，不中断批量操作
      end
    end
    
    @sync_log.update!(
      status: :success,
      completed_at: Time.current
    )
    
  rescue StandardError => e
    @sync_log.update!(
      status: :failed,
      completed_at: Time.current,
      error_message: e.message
    )
  end
  
  private
  
  def create_batch_sync_log
    CostSyncLog.create!(
      sync_type: :batch_all,
      status: :in_progress,
      started_at: Time.current
    )
  end
end
```

### 4. 控制器设计

#### Admin::CostsController
```ruby
class Admin::CostsController < Admin::BaseController
  before_action :set_aws_account, only: [:show, :sync_account, :chart_data]
  
  # GET /admin/costs
  def index
    @aws_accounts = AwsAccount.active.includes(:daily_costs)
                              .page(params[:page])
                              .per(10)
    @recent_sync_logs = CostSyncLog.recent.limit(10)
  end
  
  # GET /admin/costs/:id
  def show
    @daily_costs = @aws_account.daily_costs
                               .recent_weeks(2)
                               .ordered_by_date
    
    @total_cost = @daily_costs.sum(:cost_amount)
    @sync_logs = @aws_account.cost_sync_logs.recent.limit(5)
  end
  
  # POST /admin/costs/:id/sync
  def sync_account
    CostSyncJob.perform_later(@aws_account.id)
    
    redirect_to admin_cost_path(@aws_account),
                notice: "账号 #{@aws_account.name} 的费用同步已开始"
  end
  
  # POST /admin/costs/batch_sync
  def batch_sync
    BatchCostSyncJob.perform_later
    
    redirect_to admin_costs_path,
                notice: "所有账号的费用同步已开始"
  end
  
  # GET /admin/costs/:id/chart_data
  def chart_data
    start_date = params[:start_date]&.to_date || 2.weeks.ago.to_date
    end_date = params[:end_date]&.to_date || Date.current
    
    daily_costs = @aws_account.daily_costs
                              .by_date_range(start_date, end_date)
                              .ordered_by_date
    
    chart_data = daily_costs.map do |cost|
      {
        date: cost.date.strftime('%Y-%m-%d'),
        cost: cost.cost_amount.to_f
      }
    end
    
    render json: {
      data: chart_data,
      total: daily_costs.sum(:cost_amount).to_f,
      currency: 'USD'
    }
  end
  
  # GET /admin/costs/sync_status
  def sync_status
    sync_logs = CostSyncLog.recent.limit(20).includes(:aws_account)
    
    render json: {
      logs: sync_logs.map do |log|
        {
          id: log.id,
          account_name: log.aws_account&.name,
          status: log.status,
          sync_type: log.sync_type,
          error_message: log.error_message,
          created_at: log.created_at.strftime('%Y-%m-%d %H:%M'),
          duration: log.duration&.round(2)
        }
      end
    }
  end
  
  private
  
  def set_aws_account
    @aws_account = AwsAccount.find(params[:id])
  end
end
```

### 5. 前端界面设计

#### 费用管理主页视图
```erb
<!-- app/views/admin/costs/index.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-3xl font-bold text-gray-900">费用管理</h1>
    <%= button_to "同步所有账号费用", 
                  batch_sync_admin_costs_path, 
                  method: :post,
                  class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg",
                  data: { confirm: "确定要同步所有账号的费用数据吗？" } %>
  </div>
  
  <!-- 同步状态面板 -->
  <div class="bg-white rounded-lg shadow mb-6 p-6">
    <h2 class="text-xl font-semibold mb-4">最近同步记录</h2>
    <div id="sync-status" class="space-y-2">
      <!-- 通过JavaScript动态加载 -->
    </div>
  </div>
  
  <!-- 账号费用列表 -->
  <div class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
    <% @aws_accounts.each do |account| %>
      <div class="bg-white rounded-lg shadow p-6">
        <div class="flex justify-between items-start mb-4">
          <div>
            <h3 class="text-lg font-semibold"><%= account.name %></h3>
            <p class="text-sm text-gray-500"><%= account.masked_account_id %></p>
          </div>
          <span class="px-2 py-1 text-xs rounded-full 
                     <%= account.active? ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' %>">
            <%= account.display_status %>
          </span>
        </div>
        
        <% recent_costs = account.daily_costs.recent_weeks(2) %>
        <div class="mb-4">
          <p class="text-2xl font-bold text-gray-900">
            $<%= recent_costs.sum(:cost_amount).round(2) %>
          </p>
          <p class="text-sm text-gray-500">最近2周总费用</p>
        </div>
        
        <div class="flex space-x-2">
          <%= link_to "查看详情", 
                      admin_cost_path(account), 
                      class: "flex-1 bg-gray-100 hover:bg-gray-200 text-center py-2 px-4 rounded-lg text-sm" %>
          <%= button_to "同步费用", 
                        sync_account_admin_cost_path(account), 
                        method: :post,
                        class: "flex-1 bg-blue-500 hover:bg-blue-600 text-white text-center py-2 px-4 rounded-lg text-sm" %>
        </div>
      </div>
    <% end %>
  </div>
  
  <!-- 分页 -->
  <%= paginate @aws_accounts if respond_to?(:paginate) %>
</div>

<script>
// 定期更新同步状态
setInterval(updateSyncStatus, 5000);

function updateSyncStatus() {
  fetch('/admin/costs/sync_status')
    .then(response => response.json())
    .then(data => {
      const container = document.getElementById('sync-status');
      container.innerHTML = data.logs.map(log => `
        <div class="flex justify-between items-center p-3 rounded-lg 
                    ${log.status === 'success' ? 'bg-green-50' : 
                      log.status === 'failed' ? 'bg-red-50' : 'bg-yellow-50'}">
          <div>
            <span class="font-medium">${log.account_name || '批量同步'}</span>
            <span class="text-sm text-gray-500 ml-2">${log.created_at}</span>
          </div>
          <div class="flex items-center">
            <span class="px-2 py-1 text-xs rounded-full
                         ${log.status === 'success' ? 'bg-green-100 text-green-800' :
                           log.status === 'failed' ? 'bg-red-100 text-red-800' : 'bg-yellow-100 text-yellow-800'}">
              ${log.status}
            </span>
            ${log.error_message ? `<span class="ml-2 text-sm text-red-600">${log.error_message}</span>` : ''}
          </div>
        </div>
      `).join('');
    })
    .catch(error => console.error('Error fetching sync status:', error));
}

// 页面加载时立即更新一次
document.addEventListener('DOMContentLoaded', updateSyncStatus);
</script>
```

#### 单账号费用详情视图
```erb
<!-- app/views/admin/costs/show.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <div>
      <h1 class="text-3xl font-bold text-gray-900"><%= @aws_account.name %></h1>
      <p class="text-gray-500"><%= @aws_account.masked_account_id %></p>
    </div>
    <div class="flex space-x-3">
      <%= link_to "返回列表", 
                  admin_costs_path, 
                  class: "bg-gray-100 hover:bg-gray-200 px-4 py-2 rounded-lg" %>
      <%= button_to "同步费用", 
                    sync_account_admin_cost_path(@aws_account), 
                    method: :post,
                    class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg" %>
    </div>
  </div>
  
  <!-- 费用概览 -->
  <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
    <div class="bg-white rounded-lg shadow p-6">
      <h3 class="text-lg font-semibold mb-2">最近2周总费用</h3>
      <p class="text-3xl font-bold text-blue-600">$<%= @total_cost.round(2) %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-6">
      <h3 class="text-lg font-semibold mb-2">日均费用</h3>
      <p class="text-3xl font-bold text-green-600">
        $<%= (@total_cost / 14.0).round(2) %>
      </p>
    </div>
    <div class="bg-white rounded-lg shadow p-6">
      <h3 class="text-lg font-semibold mb-2">最后同步</h3>
      <p class="text-lg">
        <%= @sync_logs.first&.created_at&.strftime('%m-%d %H:%M') || '未同步' %>
      </p>
    </div>
  </div>
  
  <!-- 费用图表 -->
  <div class="bg-white rounded-lg shadow p-6 mb-6">
    <div class="flex justify-between items-center mb-4">
      <h2 class="text-xl font-semibold">每日费用趋势</h2>
      <div class="flex space-x-2">
        <label class="text-sm">开始日期:</label>
        <input type="date" id="start-date" value="<%= 2.weeks.ago.strftime('%Y-%m-%d') %>" 
               class="border rounded px-2 py-1 text-sm">
        <label class="text-sm">结束日期:</label>
        <input type="date" id="end-date" value="<%= Date.current.strftime('%Y-%m-%d') %>" 
               class="border rounded px-2 py-1 text-sm">
        <button onclick="updateChart()" 
                class="bg-blue-500 text-white px-3 py-1 rounded text-sm hover:bg-blue-600">
          更新
        </button>
      </div>
    </div>
    <canvas id="cost-chart" width="800" height="400"></canvas>
  </div>
  
  <!-- 同步记录 -->
  <div class="bg-white rounded-lg shadow p-6">
    <h2 class="text-xl font-semibold mb-4">同步记录</h2>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              同步时间
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              状态
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              同步天数
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              耗时
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              错误信息
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @sync_logs.each do |log| %>
            <tr>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= log.created_at.strftime('%Y-%m-%d %H:%M') %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full
                             <%= log.success? ? 'bg-green-100 text-green-800' :
                                 log.failed? ? 'bg-red-100 text-red-800' : 'bg-yellow-100 text-yellow-800' %>">
                  <%= log.status.humanize %>
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= log.synced_dates_count %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= log.duration&.round(2) %>s
              </td>
              <td class="px-6 py-4 text-sm text-red-600 max-w-xs truncate">
                <%= log.error_message %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
let costChart;

document.addEventListener('DOMContentLoaded', function() {
  initChart();
  loadChartData();
});

function initChart() {
  const ctx = document.getElementById('cost-chart').getContext('2d');
  costChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: [],
      datasets: [{
        label: '每日费用 (USD)',
        data: [],
        backgroundColor: 'rgba(59, 130, 246, 0.5)',
        borderColor: 'rgb(59, 130, 246)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        y: {
          beginAtZero: true,
          ticks: {
            callback: function(value) {
              return '$' + value.toFixed(2);
            }
          }
        }
      },
      plugins: {
        tooltip: {
          callbacks: {
            label: function(context) {
              return 'Cost: $' + context.parsed.y.toFixed(2);
            }
          }
        }
      }
    }
  });
}

function loadChartData() {
  const startDate = document.getElementById('start-date').value;
  const endDate = document.getElementById('end-date').value;
  
  fetch(`/admin/costs/<%= @aws_account.id %>/chart_data?start_date=${startDate}&end_date=${endDate}`)
    .then(response => response.json())
    .then(data => {
      costChart.data.labels = data.data.map(item => item.date);
      costChart.data.datasets[0].data = data.data.map(item => item.cost);
      costChart.update();
      
      // 更新总计显示
      document.querySelector('.text-3xl.font-bold.text-blue-600').textContent = 
        '$' + data.total.toFixed(2);
    })
    .catch(error => {
      console.error('Error loading chart data:', error);
    });
}

function updateChart() {
  loadChartData();
}
</script>
```

## 数据库设计

### 新增表结构

#### daily_costs表
```sql
CREATE TABLE daily_costs (
  id bigint PRIMARY KEY AUTO_INCREMENT,
  aws_account_id bigint NOT NULL,
  date date NOT NULL,
  cost_amount decimal(10,2) NOT NULL DEFAULT 0.00,
  currency varchar(3) NOT NULL DEFAULT 'USD',
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL,
  
  FOREIGN KEY (aws_account_id) REFERENCES aws_accounts(id) ON DELETE CASCADE,
  UNIQUE KEY unique_account_date (aws_account_id, date),
  INDEX idx_date (date),
  INDEX idx_account_date (aws_account_id, date),
  INDEX idx_recent_costs (aws_account_id, date DESC)
);
```

#### cost_sync_logs表
```sql
CREATE TABLE cost_sync_logs (
  id bigint PRIMARY KEY AUTO_INCREMENT,
  aws_account_id bigint NULL,
  status int NOT NULL DEFAULT 0,
  sync_type int NOT NULL DEFAULT 0,
  error_message text NULL,
  synced_dates_count int DEFAULT 0,
  started_at timestamp NULL,
  completed_at timestamp NULL,
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL,
  
  FOREIGN KEY (aws_account_id) REFERENCES aws_accounts(id) ON DELETE SET NULL,
  INDEX idx_status (status),
  INDEX idx_sync_type (sync_type),
  INDEX idx_created_at (created_at DESC),
  INDEX idx_account_status (aws_account_id, status)
);
```

### 迁移文件

#### 创建daily_costs表
```ruby
# db/migrate/xxx_create_daily_costs.rb
class CreateDailyCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :daily_costs do |t|
      t.references :aws_account, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.decimal :cost_amount, precision: 10, scale: 2, null: false, default: 0.00
      t.string :currency, limit: 3, null: false, default: 'USD'
      
      t.timestamps
      
      t.index [:aws_account_id, :date], unique: true, name: 'unique_account_date'
      t.index :date, name: 'idx_date'
      t.index [:aws_account_id, :date], name: 'idx_account_date'
      t.index [:aws_account_id, :date], order: { date: :desc }, name: 'idx_recent_costs'
    end
  end
end
```

#### 创建cost_sync_logs表
```ruby
# db/migrate/xxx_create_cost_sync_logs.rb
class CreateCostSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :cost_sync_logs do |t|
      t.references :aws_account, null: true, foreign_key: { on_delete: :nullify }
      t.integer :status, null: false, default: 0
      t.integer :sync_type, null: false, default: 0
      t.text :error_message
      t.integer :synced_dates_count, default: 0
      t.timestamp :started_at
      t.timestamp :completed_at
      
      t.timestamps
      
      t.index :status, name: 'idx_status'
      t.index :sync_type, name: 'idx_sync_type'
      t.index :created_at, order: :desc, name: 'idx_created_at'
      t.index [:aws_account_id, :status], name: 'idx_account_status'
    end
  end
end
```

## 路由设计

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :admin do
    resources :costs, only: [:index, :show] do
      member do
        post :sync_account
        get :chart_data
      end
      
      collection do
        post :batch_sync
        get :sync_status
      end
    end
  end
end
```

## 依赖更新

### Gemfile添加
```ruby
# AWS Cost Explorer
gem 'aws-sdk-costexplorer'

# 并行处理
gem 'parallel'

# 图表支持（可选）
gem 'chartkick'
```

## 技术实现要点

### Rails最佳实践
1. **Model层**: 
   - ActiveRecord关联和验证
   - 作用域查询优化
   - 数据格式化辅助方法

2. **Service层**: 
   - 业务逻辑封装
   - 错误处理和重试机制
   - AWS API集成

3. **Job层**: 
   - Sidekiq后台任务
   - 并行处理和容错
   - 详细的执行日志

4. **Controller层**: 
   - RESTful API设计
   - 权限控制继承
   - JSON API支持

5. **View层**: 
   - 响应式设计
   - 实时状态更新
   - 交互式图表

### 安全考虑
- 管理员权限验证（继承`Admin::BaseController`）
- AWS凭证安全处理（复用现有的`attr_encrypted`）
- CSRF保护和参数过滤
- SQL注入防护（使用ActiveRecord查询）

### 性能优化
- 数据库索引优化（日期、账号、状态）
- 批量操作并行处理（Parallel gem）
- 前端图表数据异步加载
- 分页和数据分组

### 错误处理
- AWS API异常捕获和重试
- 详细错误日志记录
- 用户友好的错误信息展示
- 批量操作的容错机制

## 开发步骤

### Phase 1: 基础设施
1. 更新Gemfile，添加必要依赖
2. 创建数据库迁移文件
3. 实现基础Model层（DailyCost, CostSyncLog）

### Phase 2: 服务层
4. 实现AwsCostExplorerService
5. 创建Sidekiq后台任务
6. 添加错误处理和重试机制

### Phase 3: 控制器和路由
7. 创建Admin::CostsController
8. 配置路由和权限验证
9. 实现API端点

### Phase 4: 前端界面
10. 实现费用管理主页视图
11. 创建单账号详情页面
12. 集成Chart.js图表功能
13. 添加实时状态更新

### Phase 5: 测试和优化
14. 编写单元测试和集成测试
15. 性能测试和优化
16. 用户体验优化

## 预期效果

### 功能完整性
- ✅ 支持单账号和批量费用同步
- ✅ 实时同步状态监控
- ✅ 交互式费用图表展示
- ✅ 详细的错误信息和日志

### 用户体验
- ✅ 响应式设计，支持移动端
- ✅ 实时状态更新，无需手动刷新
- ✅ 直观的图表展示和数据分析
- ✅ 友好的错误提示和操作引导

### 技术质量
- ✅ 遵循Rails约定和最佳实践
- ✅ 完整的错误处理和容错机制
- ✅ 高性能的数据库查询和索引
- ✅ 可扩展的架构设计

这个设计方案完全基于Rails最佳实践，复用现有架构（认证、审计、后台任务），确保代码一致性和可维护性。