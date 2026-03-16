require "net/http"
require "json"
require "uri"

class GeocodingService

  GEOCODING_BASE_URL  = "http://api.openweathermap.org/geo/1.0".freeze
  MAX_RESULTS         = 1

  def initialize(address)
    @address = address.to_s.strip
    @api_key = ENV.fetch("OPENWEATHER_API_KEY")
  end

  def call
    if looks_like_zip_code?(@address)
      fetch_by_zip_code(@address)
    else
      fetch_by_city_name(@address)
    end
  end

  private

  def looks_like_zip_code?(address)
    address.match?(/\A[\d]{4,6}\z/) ||  address.match?(/\A[A-Z]{1,2}\d[A-Z\d]?\z/i)
  end

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

  def build_location(raw)
    {
      city:     raw["name"],
      country:  raw["country"],
      zip_code: build_zip_code(raw),
      lat:      raw["lat"],
      lon:      raw["lon"]
    }
  end

  def build_zip_code(raw)
    raw["zip"] || "#{raw["name"]}-#{raw["country"]}"
  end
end