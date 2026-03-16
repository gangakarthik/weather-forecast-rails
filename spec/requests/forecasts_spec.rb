require 'rails_helper'

RSpec.describe "Forecasts", type: :request do

  let(:api_key)  { "test_api_key" }
  let(:base_url) { "http://api.openweathermap.org" }

  let(:location) do
    {
      city:     "London",
      country:  "GB",
      zip_code: "London-GB",
      lat:      51.5073219,
      lon:      -0.1276474
    }
  end

  let(:forecast_data) do
    {
      current: {
        city:         "London",
        country:      "GB",
        temp_c:       9.3,
        temp_f:       48.8,
        feels_like_c: 5.9,
        feels_like_f: 42.6,
        temp_min_c:   7.9,
        temp_min_f:   46.2,
        temp_max_c:   9.3,
        temp_max_f:   48.8,
        humidity:     87,
        description:  "Moderate rain",
        icon:         "10d",
        wind_speed:   6.8
      },
      forecast: [
        {
          date:        "Monday, Mar 16",
          temp_min_c:  7.9,
          temp_min_f:  46.2,
          temp_max_c:  10.6,
          temp_max_f:  51.1,
          description: "Overcast clouds",
          icon:        "04d"
        }
      ],
      cached: false
    }
  end

  before do
    allow(ENV).to receive(:fetch).with("OPENWEATHER_API_KEY").and_return(api_key)
    Rails.cache.clear
  end

  describe "GET /" do

    it "returns 200 OK" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the search form" do
      get root_path
      expect(response.body).to include("Weather Forecast")
      expect(response.body).to include("Get Forecast")
    end

    it "does not show forecast on first load" do
      get root_path
      expect(response.body).not_to include("Live Result")
      expect(response.body).not_to include("Cached Result")
    end

  end

  describe "POST /forecast" do

    context "with valid address" do

      before do
        allow_any_instance_of(GeocodingService)
          .to receive(:call)
          .and_return(location)

        allow_any_instance_of(ForecastService)
          .to receive(:call)
          .and_return(forecast_data)
      end

      it "returns 200 OK" do
        post create_forecast_path, params: { address: "London" }
        expect(response).to have_http_status(:ok)
      end

      it "displays city name" do
        post create_forecast_path, params: { address: "London" }
        expect(response.body).to include("London")
      end

      it "displays temperature" do
        post create_forecast_path, params: { address: "London" }
        expect(response.body).to include("9.3")
      end

      it "displays Live Result badge" do
        post create_forecast_path, params: { address: "London" }
        expect(response.body).to include("Live Result")
      end

      it "displays weather description" do
        post create_forecast_path, params: { address: "London" }
        expect(response.body).to include("Moderate rain")
      end

    end

    context "with cached result" do

      before do
        allow_any_instance_of(GeocodingService)
          .to receive(:call)
          .and_return(location)

        allow_any_instance_of(ForecastService)
          .to receive(:call)
          .and_return(forecast_data.merge(cached: true))
      end

      it "displays Cached Result badge" do
        post create_forecast_path, params: { address: "London" }
        expect(response.body).to include("Cached Result")
      end

    end

    context "with empty address" do

      it "shows error message" do
        post create_forecast_path, params: { address: "" }
        expect(response.body).to include("Please enter a valid address")
      end

      it "returns 200 OK" do
        post create_forecast_path, params: { address: "" }
        expect(response).to have_http_status(:ok)
      end

    end

    context "with invalid address" do

      before do
        allow_any_instance_of(GeocodingService)
          .to receive(:call)
          .and_return(nil)
      end

      it "shows error message" do
        post create_forecast_path, params: { address: "xyzabc123" }
        expect(response.body).to include("Could not find")
      end

      it "returns 200 OK" do
        post create_forecast_path, params: { address: "xyzabc123" }
        expect(response).to have_http_status(:ok)
      end

    end

    context "when forecast service fails" do

      before do
        allow_any_instance_of(GeocodingService)
          .to receive(:call)
          .and_return(location)

        allow_any_instance_of(ForecastService)
          .to receive(:call)
          .and_return(nil)
      end

      it "shows error message" do
        post create_forecast_path, params: { address: "karthik" }
        expect(response.body).to include("Could not fetch forecast")
      end

      it "returns 200 OK" do
        post create_forecast_path, params: { address: "karthik" }
        expect(response).to have_http_status(:ok)
      end

    end

  end

end