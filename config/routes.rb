Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  
  require 'sidekiq/web'
  
  # Mount Sidekiq Web UI with authentication
  mount Sidekiq::Web => '/sidekiq', constraints: AdminConstraint

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Health check for load balancers
  get "health" => "rails/health#show"

  # Admin routes
  namespace :admin do
    root 'dashboard#index'
    get 'dashboard', to: 'dashboard#index'
    
    # Authentication routes
    get 'login', to: 'sessions#new'
    post 'login', to: 'sessions#create'
    delete 'logout', to: 'sessions#destroy'
    
    resources :aws_accounts do
      member do
        patch :activate
        patch :deactivate
        post :refresh_quota
        get 'account_quotas', to: 'account_quotas#account_quotas', as: :account_quotas
        post 'account_quotas/refresh', to: 'account_quotas#refresh_account_quotas', as: :refresh_account_quotas
      end
      collection do
        post :bulk_refresh
        get :export
      end
    end
    
    resources :account_quotas do
      member do
        post :refresh
      end
      collection do
        post :bulk_refresh
        get :statistics
        get :export
      end
    end
    
    resources :audit_logs, only: [:index, :show] do
      collection do
        get :export
      end
    end
    
    resources :settings, only: [:index, :update] do
      collection do
        post :test_aws_connection
        post :clear_cache
      end
    end
    
    resources :admin_users, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        patch :activate
        patch :deactivate
        patch :unlock
      end
    end
    
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

  # API routes
  namespace :api do
    namespace :v1 do
      # Authentication routes
      scope :auth do
        post :login, to: 'auth#login'
        post :logout, to: 'auth#logout'
        post :refresh, to: 'auth#refresh'
        get :me, to: 'auth#me'
        put :password, to: 'auth#change_password'
        post :check_token, to: 'auth#check_token'
      end
      
      # Future API routes will be added here
      # resources :aws_accounts
      # resources :quotas
      # resources :admins
      # resources :audit_logs
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Public routes (前台展示)
  namespace :public do
    root 'home#index'
    resources :accounts, only: [:index, :show] do
      collection do
        get :search
        get :filter
      end
    end
  end

  # Defines the root path route ("/")
  root "public/home#index"
end
