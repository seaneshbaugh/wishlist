Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  devise_for :users, skip: %i[sessions passwords registrations confirmations unlocks]

  devise_scope :user do
    get "/login" => "devise/sessions#new", as: :new_user_session
    post "/login" => "devise/sessions#create", as: :user_session
    delete "/logout" => "devise/sessions#destroy", as: :destroy_user_session

    post "/update-password" => "devise/passwords#create", as: :user_password
    get "/reset-password" => "devise/passwords#new", as: :new_user_password
    get "/update-password" => "devise/passwords#edit", as: :edit_user_password
    put "/update-password" => "devise/passwords#update"

    post "/register" => "registrations#create", as: :user_registration
    get "/register" => "devise/registrations#new", as: :new_user_registration

    post "/confirm-registration" => "devise/confirmations#create", as: :user_confirmation
    get "/resend-confirmation" => "devise/confirmations#new", as: :new_user_confirmation
    get "/confirm-registration" => "confirmations#show"

    post "/unlock-account" => "devise/unlocks#create", as: :user_unlock
    get "/resend-unlock" => "devise/unlocks#new", as: :new_user_unlock
    get "/unlock-account" => "devise/unlocks#show"

    authenticated do
      resource :account, only: %i[show edit update destroy] do
        get "confirm-delete" => "accounts#confirm_delete", as: :confirm_delete
      end

      resources :lists do
        collection do
          patch "reorder" => "lists#reorder", as: :reorder, constraints: ->(request) { request.format.json? }
        end

        resources :list_items, only: %i[create update destroy] do
          collection do
            patch "reorder" => "list_items#reorder", as: :reorder, constraints: ->(request) { request.format.json? }
          end
        end
      end

      resources :users, only: %i[index show] do
        resources :lists, only: %i[index show]
      end

      root to: "lists#index", as: :authenticated_root
    end
  end

  root to: "devise/sessions#new"
end
