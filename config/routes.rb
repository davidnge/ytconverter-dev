require 'sidekiq/web'

Rails.application.routes.draw do
  
  #homepage
  root 'conversions#index'

  # new route for YouTube to MP3
  get 'youtube-to-mp3', to: 'conversions#index'


  get "static_pages/contact"
  get "static_pages/copyright_claims"
  get "static_pages/privacy_policy"
  get "static_pages/terms_of_use"
  

  # Static pages
  get 'contact', to: 'static_pages#contact'
  get 'copyright-claims', to: 'static_pages#copyright_claims'
  get 'privacy-policy', to: 'static_pages#privacy_policy'
  get 'terms-of-use', to: 'static_pages#terms_of_use'
  
  resources :conversions, only: [:index, :create, :show] do
    member do
      get :download
      get :status
    end
  end
  
  # Protect Sidekiq Web UI
  if Rails.env.production?
    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      # Replace with actual environment variables in production
      ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])) &
      ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"]))
    end
  end
  
  mount Sidekiq::Web => '/sidekiq'
end