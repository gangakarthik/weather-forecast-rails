require "net/http"
require "json"
require "uri"

class ForecastService

  WEATHER_API_BASE_URL = "http://api.openweathermap.org/data/2.5".freeze
  CACHE_EXPIRY         = 30.minutes
  KELVIN_TO_CELSIUS    = 273.15
  FORECAST_DAYS        = 5

  def initialize(location)
    @location = location
    @api_key  = ENV.fetch("OPENWEATHER_API_KEY")
    @zip_code = location[:zip_code]
    @city     = location[:city]
    @country  = location[:country]
  end

  def call
    cached_data = Rails.cache.read(cache_key)

    if cached_data
      cached_data.merge(cached: true)
    else
      fresh_data = fetch_forecast_data
      return nil if fresh_data.nil?
      Rails.cache.write(cache_key, fresh_data, expires_in: CACHE_EXPIRY)
      fresh_data.merge(cached: false)
    end
  end

  private

  def cache_key
    "forecast_#{@zip_code}"
  end

  def fetch_forecast_data
    current_data  = fetch_current_weather
    forecast_data = fetch_five_day_forecast

    current = parse_current_weather(current_data)
    return nil if current.nil?

    {
      current:  current,
      forecast: parse_five_day_forecast(forecast_data)
    }
  end

  def fetch_current_weather
    uri       = URI("#{WEATHER_API_BASE_URL}/weather")
    uri.query = URI.encode_www_form(
      q:     "#{@city},#{@country}",
      appid: @api_key
    )

    fetch_from_api(uri)
  end

  def fetch_five_day_forecast
    uri       = URI("#{WEATHER_API_BASE_URL}/forecast")
    uri.query = URI.encode_www_form(
      q:     "#{@city},#{@country}",
      appid: @api_key
    )

    fetch_from_api(uri)
  end

  def fetch_from_api(uri)
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("ForecastService error: #{e.message}")
    nil
  end

  def parse_current_weather(data)
    return nil if data.nil?
    return nil if data["cod"] && data["cod"] != 200

    temp_k       = data.dig("main", "temp")
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

  def parse_five_day_forecast(data)
    return [] if data.nil?

    grouped = data["list"].group_by do |entry|
      entry["dt_txt"].split(" ").first
    end

    grouped.first(FORECAST_DAYS).map do |date, entries|
      build_daily_forecast(date, entries)
    end
  end

  def build_daily_forecast(date, entries)
    temps    = entries.map { |e| e.dig("main", "temp") }
    min_temp = temps.min
    max_temp = temps.max

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

  def kelvin_to_celsius(kelvin)
    return nil if kelvin.nil?
    (kelvin - KELVIN_TO_CELSIUS).round(1)
  end

  def kelvin_to_fahrenheit(kelvin)
    return nil if kelvin.nil?
    ((kelvin - KELVIN_TO_CELSIUS) * 9.0 / 5.0 + 32).round(1)
  end
end