require "net/http"
require "json"
require "uri"

# =============================================================================
# ForecastService
#
# Responsibility:
#   Fetches current weather and 5-day forecast data for a given location
#   from the OpenWeatherMap API. Implements 30-minute caching by zip code
#   to minimize API calls and improve response times.
#
# Design Pattern: Service Object
#   - Single Responsibility: only handles weather data fetching and caching
#   - Keeps controllers thin and focused on HTTP concerns
#   - Independently testable in isolation
#
# Object Decomposition:
#   Input:
#     - location (Hash): { city:, country:, zip_code:, lat:, lon: }
#       Output from GeocodingService
#
#   Output:
#     - Hash: {
#         current:  { temp_c:, temp_f:, feels_like_c:, feels_like_f:,
#                     temp_min_c:, temp_max_c:, humidity:, description:,
#                     icon:, wind_speed:, city:, country: },
#         forecast: [ { date:, temp_min_c:, temp_max_c:, description:, icon: } ],
#         cached:   true/false
#       }
#     - nil: if weather data cannot be fetched
#
# Caching Strategy:
#   - Cache Key:   "forecast_#{zip_code}" (e.g. "forecast_London-GB")
#   - Cache TTL:   30 minutes
#   - Cache Store: Rails.cache (memory_store in development/test)
#   - Cache Hit:   Returns cached data with cached: true
#   - Cache Miss:  Fetches from API, stores in cache, returns with cached: false
#
# APIs Used:
#   - Current weather:  /data/2.5/weather?q={city},{country}&appid={key}
#   - 5-day forecast:   /data/2.5/forecast?q={city},{country}&appid={key}
#
# Usage:
#   location = { city: "London", country: "GB", zip_code: "London-GB" }
#   ForecastService.new(location).call
#   => { current: {...}, forecast: [...], cached: false }
# =============================================================================
class ForecastService

  # Base URL for OpenWeatherMap Weather API
  WEATHER_API_BASE_URL = "http://api.openweathermap.org/data/2.5".freeze

  # Cache expiry time — 30 minutes as per requirements
  CACHE_EXPIRY = 30.minutes

  # Kelvin to Celsius conversion constant
  KELVIN_TO_CELSIUS = 273.15

  # Number of days to show in extended forecast
  FORECAST_DAYS = 5

  # Initializes the service with location data from GeocodingService
  #
  # @param location [Hash] location data { city:, country:, zip_code:, lat:, lon: }
  def initialize(location)
    @location = location
    @api_key  = ENV.fetch("OPENWEATHER_API_KEY")
    @zip_code = location[:zip_code]
    @city     = location[:city]
    @country  = location[:country]
  end

  # Main entry point for the service
  #
  # Implements cache-aside pattern:
  #   1. Check cache for existing data
  #   2. If cache hit, return cached data with cached: true
  #   3. If cache miss, fetch from API, store in cache, return with cached: false
  #
  # @return [Hash, nil] forecast data with cache indicator, or nil on failure
  def call
    cached_data = Rails.cache.read(cache_key)

    if cached_data
      # Cache hit — return cached data with indicator
      cached_data.merge(cached: true)
    else
      # Cache miss — fetch fresh data from API
      fresh_data = fetch_forecast_data
      return nil if fresh_data.nil?

      # Store in cache for subsequent requests
      Rails.cache.write(cache_key, fresh_data, expires_in: CACHE_EXPIRY)
      fresh_data.merge(cached: false)
    end
  end

  private

  # Builds the cache key using zip code as unique location identifier
  #
  # Using zip code ensures that "London", "london", "London, UK"
  # all resolve to the same cache entry "forecast_London-GB"
  #
  # @return [String] cache key e.g. "forecast_London-GB"
  def cache_key
    "forecast_#{@zip_code}"
  end

  # Orchestrates fetching and parsing of both current weather and forecast
  #
  # @return [Hash, nil] combined weather data or nil if current weather fails
  def fetch_forecast_data
    current_data  = fetch_current_weather
    forecast_data = fetch_five_day_forecast

    # Parse current weather — return nil if it fails
    # (current weather is required, forecast is bonus)
    current = parse_current_weather(current_data)
    return nil if current.nil?

    {
      current:  current,
      forecast: parse_five_day_forecast(forecast_data)
    }
  end

  # Fetches real-time current weather from OpenWeatherMap
  #
  # Uses /data/2.5/weather endpoint which provides actual current
  # conditions rather than the forecast endpoint's 3-hour intervals
  #
  # @return [Hash, nil] raw API response or nil on failure
  def fetch_current_weather
    uri       = URI("#{WEATHER_API_BASE_URL}/weather")
    uri.query = URI.encode_www_form(
      q:     "#{@city},#{@country}",
      appid: @api_key
    )

    fetch_from_api(uri)
  end

  # Fetches 5-day / 3-hour interval forecast from OpenWeatherMap
  #
  # Returns 40 entries (5 days x 8 entries per day) starting from now
  #
  # @return [Hash, nil] raw API response or nil on failure
  def fetch_five_day_forecast
    uri       = URI("#{WEATHER_API_BASE_URL}/forecast")
    uri.query = URI.encode_www_form(
      q:     "#{@city},#{@country}",
      appid: @api_key
    )

    fetch_from_api(uri)
  end

  # Makes HTTP GET request to the given URI
  #
  # Shared by both fetch_current_weather and fetch_five_day_forecast
  # to avoid code duplication (Code Re-Use principle)
  #
  # @param uri [URI] fully constructed URI with query params
  # @return [Hash, nil] parsed JSON response or nil on failure
  def fetch_from_api(uri)
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("ForecastService#fetch_from_api error: #{e.message}")
    nil
  end

  # Parses raw current weather API response into a clean structured hash
  #
  # Converts temperatures from Kelvin (API default) to both
  # Celsius and Fahrenheit for display flexibility
  #
  # @param data [Hash] raw API response from /data/2.5/weather
  # @return [Hash, nil] structured current weather hash or nil if data invalid
  def parse_current_weather(data)
    return nil if data.nil?

    # Validate API response code
    return nil if data["cod"] && data["cod"] != 200

    # Temperature is required — return nil if missing
    temp_k = data.dig("main", "temp")
    return nil if temp_k.nil?

    feels_like_k = data.dig("main", "feels_like")
    temp_min_k   = data.dig("main", "temp_min")
    temp_max_k   = data.dig("main", "temp_max")

    {
      city:         data["name"],
      country:      data.dig("sys", "country"),
      temp_c:       kelvin_to_celsius(temp_k),
      temp_f:       kelvin_to_fahrenheit(temp_k),
      feels_like_c: kelvin_to_celsius(feels_like_k),
      feels_like_f: kelvin_to_fahrenheit(feels_like_k),
      temp_min_c:   kelvin_to_celsius(temp_min_k),
      temp_min_f:   kelvin_to_fahrenheit(temp_min_k),
      temp_max_c:   kelvin_to_celsius(temp_max_k),
      temp_max_f:   kelvin_to_fahrenheit(temp_max_k),
      humidity:     data.dig("main", "humidity"),
      description:  data.dig("weather", 0, "description")&.capitalize,
      icon:         data.dig("weather", 0, "icon"),
      wind_speed:   data.dig("wind", "speed")
    }
  end

  # Parses raw 5-day forecast API response into a clean array of daily summaries
  #
  # The API returns 40 entries at 3-hour intervals. This method:
  #   1. Groups entries by date
  #   2. Takes only FORECAST_DAYS days
  #   3. Builds a daily summary for each day
  #
  # @param data [Hash] raw API response from /data/2.5/forecast
  # @return [Array<Hash>] array of daily forecast hashes
  def parse_five_day_forecast(data)
    return [] if data.nil?

    # Group all 3-hour entries by their date (e.g. "2026-03-16")
    grouped = data["list"].group_by do |entry|
      entry["dt_txt"].split(" ").first
    end

    # Take only FORECAST_DAYS days and build a summary for each
    grouped.first(FORECAST_DAYS).map do |date, entries|
      build_daily_forecast(date, entries)
    end
  end

  # Builds a single day's forecast summary from multiple 3-hour entries
  #
  # Finds the minimum and maximum temperature across all entries for the day.
  # Uses the midday (12:00) entry for weather description as it is most
  # representative of daytime conditions.
  #
  # @param date [String] date string e.g. "2026-03-16"
  # @param entries [Array<Hash>] all 3-hour forecast entries for this date
  # @return [Hash] daily forecast summary
  def build_daily_forecast(date, entries)
    # Extract all temperatures for the day to find min/max
    temps    = entries.map { |e| e.dig("main", "temp") }
    min_temp = temps.min
    max_temp = temps.max

    # Use midday entry for description — most representative of the day
    # Falls back to first available entry if no midday entry exists
    midday = entries.find { |e| e["dt_txt"].include?("12:00:00") } || entries.first
    desc   = midday.dig("weather", 0, "description")&.capitalize
    icon   = midday.dig("weather", 0, "icon")

    {
      date:        Date.parse(date).strftime("%A, %b %d"),
      temp_min_c:  kelvin_to_celsius(min_temp),
      temp_min_f:  kelvin_to_fahrenheit(min_temp),
      temp_max_c:  kelvin_to_celsius(max_temp),
      temp_max_f:  kelvin_to_fahrenheit(max_temp),
      description: desc,
      icon:        icon
    }
  end

  # Converts temperature from Kelvin to Celsius
  #
  # Formula: Celsius = Kelvin - 273.15
  #
  # @param kelvin [Float] temperature in Kelvin
  # @return [Float, nil] temperature in Celsius rounded to 1 decimal, or nil
  def kelvin_to_celsius(kelvin)
    return nil if kelvin.nil?
    (kelvin - KELVIN_TO_CELSIUS).round(1)
  end

  # Converts temperature from Kelvin to Fahrenheit
  #
  # Formula: Fahrenheit = (Kelvin - 273.15) * 9/5 + 32
  #
  # @param kelvin [Float] temperature in Kelvin
  # @return [Float, nil] temperature in Fahrenheit rounded to 1 decimal, or nil
  def kelvin_to_fahrenheit(kelvin)
    return nil if kelvin.nil?
    ((kelvin - KELVIN_TO_CELSIUS) * 9.0 / 5.0 + 32).round(1)
  end
end