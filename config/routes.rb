Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # 公开页面路由
  root 'home#index'
  
  # 账号展示相关路由（公开访问）
  resources :accounts, only: [:index, :show] do
    collection do
      get :search
      get :filter
    end
    member do
      get :quota_details
    end
  end
  
  # API 路由（用于前端 AJAX 请求）
  namespace :api do
    namespace :v1 do
      resources :accounts, only: [:index, :show] do
        collection do
          get :models  # 获取所有可用模型列表
          get :stats   # 获取统计信息
        end
        member do
          get :quotas  # 获取特定账号的配额信息
        end
      end
    end
  end

  # 管理员路由
  namespace :admin do
    # 认证路由
    get 'login', to: 'sessions#new'
    post 'login', to: 'sessions#create'
    delete 'logout', to: 'sessions#destroy'
    post 'refresh_token', to: 'sessions#refresh'
    
    # 认证后的路由
    authenticate do
      root 'dashboard#index'
      
      # 管理面板
      get 'dashboard', to: 'dashboard#index'
      get 'dashboard/stats', to: 'dashboard#stats'
      
      # AWS账号管理
      resources :aws_accounts do
        member do
          post :test_connection    # 测试连接
          post :refresh_quota      # 刷新配额
          patch :update_status     # 更新状态
          get :quota_history       # 配额历史
        end
        
        collection do
          post :batch_refresh      # 批量刷新
          post :batch_update_status # 批量更新状态
          get :export              # 导出
          post :import             # 导入
        end
        
        # 配额管理子路由
        resources :quotas, except: [:new, :create] do
          member do
            post :refresh
            get :history
          end
        end
      end
      
      # 配额管理（全局）
      resources :quotas, only: [:index, :show] do
        collection do
          post :batch_refresh
          get :models           # 模型列表管理
          get :statistics       # 配额统计
        end
      end
      
      # 刷新任务管理
      resources :refresh_jobs, only: [:index, :show, :create] do
        member do
          post :retry
          delete :cancel
        end
        collection do
          get :active           # 活跃任务
          get :history          # 历史任务
        end
      end
      
      # 审计日志
      resources :audit_logs, only: [:index, :show] do
        collection do
          get :search
          get :export
          delete :cleanup       # 清理旧日志
        end
      end
      
      # 系统配置
      resources :system_configs, except: [:show] do
        collection do
          post :batch_update
          post :reset_defaults
        end
      end
      
      # 管理员账号管理
      resources :admins do
        member do
          patch :reset_password
          patch :unlock_account
          patch :toggle_status
        end
      end
    end
  end
  
  # WebSocket 连接（用于实时更新）
  mount ActionCable.server => '/cable'
  
  # 静态页面
  get 'about', to: 'pages#about'
  get 'contact', to: 'pages#contact'
  get 'privacy', to: 'pages#privacy'
  get 'terms', to: 'pages#terms'
  
  # 错误页面
  match '/404', to: 'errors#not_found', via: :all
  match '/422', to: 'errors#unprocessable_entity', via: :all
  match '/500', to: 'errors#internal_server_error', via: :all
  
  # 捕获所有未匹配的路由
  match '*path', to: 'errors#not_found', via: :all
end

# 自定义路由约束，用于管理员认证
class AdminAuthenticateConstraint
  def matches?(request)
    # 检查JWT token或session
    token = request.headers['Authorization']&.sub(/^Bearer /, '') || 
            request.session[:admin_token]
    
    return false unless token
    
    begin
      JwtService.decode(token)
      true
    rescue JWT::DecodeError
      false
    end
  end
end

# 使用约束
Rails.application.routes.draw do
  # ... existing routes ...
  
  def authenticate(&block)
    constraints AdminAuthenticateConstraint.new do
      instance_eval(&block) if block_given?
    end
  end
end