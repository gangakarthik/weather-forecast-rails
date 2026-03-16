require "net/http"
require "json"
require "uri"

# =============================================================================
# GeocodingService
#
# Responsibility:
#   Converts a human-readable address into structured location data
#   including city name, country, zip code, and coordinates using
#   the OpenWeatherMap Geocoding API.
#
# Design Pattern: Service Object
#   - Single Responsibility: only handles address -> location conversion
#   - Keeps controllers thin and focused on HTTP concerns
#   - Independently testable in isolation
#
# Object Decomposition:
#   Input:
#     - address (String): raw address input from the user
#       e.g. "London, UK" or "New York" or "10001"
#
#   Output:
#     - Hash: { city:, country:, zip_code:, lat:, lon: }
#     - nil:  if address cannot be resolved
#
# API Used: OpenWeatherMap Geocoding API
#   - Direct geocoding: /geo/1.0/direct?q={city}&appid={key}
#   - Zip geocoding:    /geo/1.0/zip?zip={zip},{country}&appid={key}
#
# Usage:
#   GeocodingService.new("London").call
#   => { city: "London", country: "GB", zip_code: "London-GB", ... }
# =============================================================================
class GeocodingService

  # Base URL for OpenWeatherMap Geocoding API
  GEOCODING_BASE_URL = "http://api.openweathermap.org/geo/1.0".freeze

  # Maximum number of results to request from API
  MAX_RESULTS = 1

  # Initializes the service with the raw address input
  #
  # @param address [String] the address entered by the user
  def initialize(address)
    @address = address.to_s.strip
    @api_key = ENV.fetch("OPENWEATHER_API_KEY")
  end

  # Main entry point for the service
  #
  # Automatically detects if the input looks like a zip code
  # or a city name and routes to the appropriate API endpoint.
  #
  # @return [Hash, nil] location data or nil if not found
  # @example
  #   GeocodingService.new("London").call
  #   => { city: "London", country: "GB", zip_code: "London-GB", lat: 51.5, lon: -0.1 }
  def call
    if looks_like_zip_code?(@address)
      fetch_by_zip_code(@address)
    else
      fetch_by_city_name(@address)
    end
  end

  private

  # Determines if the input looks like a zip code
  #
  # Supports two formats:
  #   - US zip codes: 4-6 digit numbers (e.g. "10001")
  #   - UK postcodes: alphanumeric prefix (e.g. "E1", "SW1")
  #
  # @param address [String] the input to check
  # @return [Boolean] true if input looks like a zip code
  def looks_like_zip_code?(address)
    address.match?(/\A[\d]{4,6}\z/) ||           # US zip: 10001
    address.match?(/\A[A-Z]{1,2}\d[A-Z\d]?\z/i)  # UK postcode prefix: E1, SW1
  end

  # Fetches location data using city name via direct geocoding API
  #
  # Endpoint: GET /geo/1.0/direct?q={city}&limit=1&appid={key}
  #
  # @param city [String] city name e.g. "London, UK"
  # @return [Hash, nil] location data or nil on failure
  def fetch_by_city_name(city)
    uri       = URI("#{GEOCODING_BASE_URL}/direct")
    uri.query = URI.encode_www_form(
      q:     city,
      limit: MAX_RESULTS,
      appid: @api_key
    )

    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    return nil if data.empty?

    build_location(data.first)
  rescue StandardError => e
    Rails.logger.error("GeocodingService#fetch_by_city_name error: #{e.message}")
    nil
  end

  # Fetches location data using zip code via zip geocoding API
  #
  # Endpoint: GET /geo/1.0/zip?zip={zip}&appid={key}
  #
  # @param zip [String] zip code e.g. "10001" or "E1"
  # @return [Hash, nil] location data or nil on failure
  def fetch_by_zip_code(zip)
    uri       = URI("#{GEOCODING_BASE_URL}/zip")
    uri.query = URI.encode_www_form(
      zip:   zip,
      appid: @api_key
    )

    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    return nil if data.empty?

    {
      city:     data["name"],
      country:  data["country"],
      zip_code: data["zip"],
      lat:      data["lat"],
      lon:      data["lon"]
    }
  rescue StandardError => e
    Rails.logger.error("GeocodingService#fetch_by_zip_code error: #{e.message}")
    nil
  end

  # Builds a clean location hash from raw API response
  #
  # @param raw [Hash] raw location data from OpenWeatherMap API
  # @return [Hash] structured location hash
  def build_location(raw)
    {
      city:     raw["name"],
      country:  raw["country"],
      zip_code: build_zip_code(raw),
      lat:      raw["lat"],
      lon:      raw["lon"]
    }
  end

  # Builds a unique cache key from available location data
  #
  # Uses zip code if available, otherwise falls back to
  # "CityName-CountryCode" format (e.g. "London-GB")
  #
  # @param raw [Hash] raw location data
  # @return [String] unique location identifier used as cache key
  def build_zip_code(raw)
    raw["zip"] || "#{raw["name"]}-#{raw["country"]}"
  end
end