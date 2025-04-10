Rails.application.routes.draw do
  root 'conversions#index'
  
  resources :conversions, only: [:index, :create, :show] do
    member do
      get :download
      get :status # Add this line
    end
  end
  
  # For Sidekiq Web UI (optional, should be protected in production)
  require 'sidekiq/web'
  mount Sidekiq::Web => '/sidekiq'
end