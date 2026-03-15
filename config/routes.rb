Rails.application.routes.draw do
  root "forecasts#index"

  get  "forecast",      to: "forecasts#index",  as: :forecast
  post "forecast",      to: "forecasts#create", as: :create_forecast
end