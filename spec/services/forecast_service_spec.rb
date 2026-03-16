require 'rails_helper'

RSpec.describe ForecastService do

  let(:api_key)  { "test_api_key" }
  let(:base_url) { "http://api.openweathermap.org/data/2.5" }

  let(:location) do
    {
      city:     "London",
      country:  "GB",
      zip_code: "London-GB",
      lat:      51.5073219,
      lon:      -0.1276474
    }
  end

  let(:current_weather_response) do
    {
      "name" => "London",
      "cod"  => 200,
      "sys"  => { "country" => "GB" },
      "main" => {
        "temp"       => 282.49,
        "feels_like" => 279.3,
        "temp_min"   => 281.0,
        "temp_max"   => 283.15,
        "humidity"   => 87
      },
      "weather" => [
        {
          "main"        => "Rain",
          "description" => "moderate rain",
          "icon"        => "10d"
        }
      ],
      "wind" => { "speed" => 6.8 }
    }.to_json
  end

  let(:forecast_response) do
    {
      "list" => [
        {
          "dt_txt" => "2026-03-16 12:00:00",
          "main"   => {
            "temp"     => 282.49,
            "temp_min" => 281.0,
            "temp_max" => 283.15
          },
          "weather" => [
            {
              "description" => "moderate rain",
              "icon"        => "10d"
            }
          ]
        },
        {
          "dt_txt" => "2026-03-17 12:00:00",
          "main"   => {
            "temp"     => 285.0,
            "temp_min" => 283.0,
            "temp_max" => 287.0
          },
          "weather" => [
            {
              "description" => "clear sky",
              "icon"        => "01d"
            }
          ]
        }
      ],
      "city" => {
        "name"    => "London",
        "country" => "GB"
      }
    }.to_json
  end

  before do
    allow(ENV).to receive(:fetch).with("OPENWEATHER_API_KEY").and_return(api_key)
    Rails.cache.clear
  end

  describe '#call' do

    context 'when cache is empty (cache miss)' do

      before do
        stub_request(:get, "#{base_url}/weather")
          .with(query: hash_including(q: "London,GB"))
          .to_return(status: 200, body: current_weather_response)

        stub_request(:get, "#{base_url}/forecast")
          .with(query: hash_including(q: "London,GB"))
          .to_return(status: 200, body: forecast_response)
      end

      it 'returns forecast data with cached: false' do
        result = ForecastService.new(location).call
        expect(result).not_to be_nil
        expect(result[:cached]).to eq(false)
      end

      it 'returns current weather data' do
        result = ForecastService.new(location).call
        expect(result[:current]).not_to be_nil
        expect(result[:current][:city]).to eq("London")
        expect(result[:current][:country]).to eq("GB")
      end

      it 'converts temperature from Kelvin to Celsius' do
        result = ForecastService.new(location).call
        expect(result[:current][:temp_c]).to eq(9.3)
      end

      it 'converts temperature from Kelvin to Fahrenheit' do
        result = ForecastService.new(location).call
        expect(result[:current][:temp_f]).to eq(48.8)
      end

      it 'returns humidity' do
        result = ForecastService.new(location).call
        expect(result[:current][:humidity]).to eq(87)
      end

      it 'returns weather description capitalized' do
        result = ForecastService.new(location).call
        expect(result[:current][:description]).to eq("Moderate rain")
      end

      it 'returns forecast array' do
        result = ForecastService.new(location).call
        expect(result[:forecast]).to be_an(Array)
        expect(result[:forecast]).not_to be_empty
      end

      it 'stores result in cache' do
        ForecastService.new(location).call
        cached = Rails.cache.read("forecast_London-GB")
        expect(cached).not_to be_nil
      end

    end

    context 'when cache has data (cache hit)' do

      let(:cached_data) do
        {
          current:  { city: "London", temp_c: 9.3 },
          forecast: []
        }
      end

      before do
        Rails.cache.write("forecast_London-GB", cached_data, expires_in: 30.minutes)
      end

      it 'returns cached data with cached: true' do
        result = ForecastService.new(location).call
        expect(result[:cached]).to eq(true)
      end

      it 'does not make any API calls when cache hit' do
        ForecastService.new(location).call
        expect(a_request(:get, "#{base_url}/weather")).not_to have_been_made
        expect(a_request(:get, "#{base_url}/forecast")).not_to have_been_made
      end

      it 'returns correct data from cache' do
        result = ForecastService.new(location).call
        expect(result[:current][:city]).to eq("London")
        expect(result[:current][:temp_c]).to eq(9.3)
      end

    end

    context 'when API returns error' do

      it 'returns nil when current weather API fails' do
        stub_request(:get, "#{base_url}/weather")
          .with(query: hash_including(q: "London,GB"))
          .to_return(status: 500)

        stub_request(:get, "#{base_url}/forecast")
          .with(query: hash_including(q: "London,GB"))
          .to_return(status: 200, body: forecast_response)

        result = ForecastService.new(location).call
        expect(result).to be_nil
      end

      it 'returns nil when API is unreachable' do
        stub_request(:get, "#{base_url}/weather")
          .with(query: hash_including(q: "London,GB"))
          .to_raise(StandardError.new("connection refused"))

        stub_request(:get, "#{base_url}/forecast")
          .with(query: hash_including(q: "London,GB"))
          .to_raise(StandardError.new("connection refused"))

        result = ForecastService.new(location).call
        expect(result).to be_nil
      end

    end

  end

end