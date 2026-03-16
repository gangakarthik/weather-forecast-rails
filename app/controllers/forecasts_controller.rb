# =============================================================================
# ForecastsController
# Responsibility:
#   Handles HTTP requests for weather forecast lookups.
#   Orchestrates GeocodingService and ForecastService to fulfill requests.
#
# Design Pattern: Thin Controller
#   - Controller only handles HTTP concerns (params, rendering, redirecting)
#   - All business logic is delegated to Service Objects
#   - Each private method has a single, clearly named responsibility
#   - Follows Single Responsibility Principle
#
# Actions:
#   - index  (GET)  : displays the address search form
#   - create (POST) : processes address input and displays forecast
#
# Object Decomposition:
#   - @address  (String): sanitized address input from user
#   - @location (Hash):   { city:, country:, zip_code:, lat:, lon: }
#                         output from GeocodingService
#   - @forecast (Hash):   { current:, forecast:, cached: }
#                         output from ForecastService
# Flow:
#   POST /forecast
#     1. Extract and sanitize address from params
#     2. Geocode address -> get location + zip code (GeocodingService)
#     3. Fetch forecast using location, with caching (ForecastService)
#     4. Render results or show appropriate error message
# =============================================================================
class ForecastsController < ApplicationController

  # GET /
  # GET /forecast
  # Displays the address search form.
  # @forecast is nil on first load so only the form is shown.
  def index
    @forecast = nil
  end

  # POST /forecast
  # Processes the address input and fetches forecast data.
  # Renders the index view with forecast data or an error message.
  def create
    @address = extract_address(params)

    # Validate that address is not blank
    if @address.blank?
      flash.now[:alert] = "Please enter a valid address."
      render :index and return
    end

    # Convert address to structured location data
    @location = geocode_address(@address)

    if @location.nil?
      flash.now[:alert] = "Could not find '#{@address}'. Please enter a specific city name (e.g. 'Karachi', 'London', 'New York', 'Hyderabad')."
      render :index and return
    end

    # Fetch forecast using location (caching handled by ForecastService)
    @forecast = fetch_forecast(@location)

    if @forecast.nil?
      flash.now[:alert] = "Could not fetch forecast for smaller areas. Please try again."
      render :index and return
    end

    render :index
  end

  private

  # Extracts and sanitizes the address from request parameters
  # @param params [ActionController::Parameters] request parameters
  # @return [String] sanitized address string
  def extract_address(params)
    params[:address].to_s.strip
  end

  # Points address geocoding to GeocodingService
  # Separating this into its own method makes the controller
  # @param address [String] sanitized address input
  # @return [Hash, nil] location data or nil if address not found
  def geocode_address(address)
    GeocodingService.new(address).call
  end

  # Points forecast to ForecastService
  # ForecastService handles caching internally
  #
  # @param location [Hash] location data from GeocodingService
  # @return [Hash, nil] forecast data with cache indicator, or nil on failure
  def fetch_forecast(location)
    ForecastService.new(location).call
  end
end