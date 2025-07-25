Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Health check for load balancers
  get "health" => "rails/health#show"

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

  # Defines the root path route ("/")
  # root "posts#index"
end
