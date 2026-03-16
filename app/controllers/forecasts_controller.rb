class ForecastsController < ApplicationController

  def index
    @forecast = nil
  end

  def create
    @address = extract_address(params)

    if @address.blank?
      flash.now[:alert] = "Please enter a valid address."
      render :index and return
    end

    @location = geocode_address(@address)

    if @location.nil?
      flash.now[:alert] = "Could not find '#{@address}'. Please enter a specific city name (e.g. 'Karachi', 'London', 'New York', 'Hyderabad')."
      render :index and return
    end

    @forecast = fetch_forecast(@location)

    if @forecast.nil?
      flash.now[:alert] = "Could not fetch forecast for smaller areas. Please try again."
      render :index and return
    end

    render :index
  end

  private

  def extract_address(params)
    params[:address].to_s.strip
  end

  def geocode_address(address)
    GeocodingService.new(address).call
  end

  def fetch_forecast(location)
    ForecastService.new(location).call
  end
end