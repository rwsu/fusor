Rails.application.routes.draw do

  get 'r/#/deployments', :to => 'fusor_ui/placeholders#index'
  get 'r/#/deployments/new/start', :to => 'fusor_ui/placeholders#new', :as => :new_fusor_deployment
  get 'r', :to => 'fusor_ui/placeholders#r'

end
