require 'rails_helper'

RSpec.describe GeocodingService do

  let(:api_key)  { "test_api_key" }
  let(:base_url) { "http://api.openweathermap.org/geo/1.0" }

  before do
    allow(ENV).to receive(:fetch).with("OPENWEATHER_API_KEY").and_return(api_key)
  end

  describe '#call' do

    context 'when input is a city name' do

      let(:london_response) do
        [{
          "name"    => "London",
          "country" => "GB",
          "lat"     => 51.5073219,
          "lon"     => -0.1276474,
          "state"   => "England"
        }].to_json
      end

      it 'returns location data for a valid city' do
        stub_request(:get, "#{base_url}/direct")
          .with(query: hash_including(q: "London"))
          .to_return(status: 200, body: london_response)

        result = GeocodingService.new("London").call

        expect(result).not_to be_nil
        expect(result[:city]).to eq("London")
        expect(result[:country]).to eq("GB")
        expect(result[:lat]).to eq(51.5073219)
        expect(result[:lon]).to eq(-0.1276474)
      end

      it 'returns a zip_code as cache key' do
        stub_request(:get, "#{base_url}/direct")
          .with(query: hash_including(q: "London"))
          .to_return(status: 200, body: london_response)

        result = GeocodingService.new("London").call

        expect(result[:zip_code]).to eq("London-GB")
      end

      it 'returns nil when city is not found' do
        stub_request(:get, "#{base_url}/direct")
          .with(query: hash_including(q: "xyzabc123"))
          .to_return(status: 200, body: [].to_json)

        result = GeocodingService.new("xyzabc123").call

        expect(result).to be_nil
      end

      it 'returns nil when API returns error' do
        stub_request(:get, "#{base_url}/direct")
          .with(query: hash_including(q: "London"))
          .to_return(status: 500)

        result = GeocodingService.new("London").call

        expect(result).to be_nil
      end

      it 'returns nil when API is unreachable' do
        stub_request(:get, "#{base_url}/direct")
          .with(query: hash_including(q: "London"))
          .to_raise(StandardError.new("connection refused"))

        result = GeocodingService.new("London").call

        expect(result).to be_nil
      end

    end

    context 'when input is a zip code' do

      let(:zip_response) do
        {
          "name"    => "New York",
          "country" => "US",
          "zip"     => "10001",
          "lat"     => 40.7484,
          "lon"     => -73.9967
        }.to_json
      end

      it 'returns location data for a valid US zip code' do
        stub_request(:get, "#{base_url}/zip")
          .with(query: hash_including(zip: "10001"))
          .to_return(status: 200, body: zip_response)

        result = GeocodingService.new("10001").call

        expect(result).not_to be_nil
        expect(result[:city]).to eq("New York")
        expect(result[:country]).to eq("US")
        expect(result[:zip_code]).to eq("10001")
      end

      it 'returns nil when zip code is not found' do
        stub_request(:get, "#{base_url}/zip")
          .with(query: hash_including(zip: "99999"))
          .to_return(status: 404, body: { cod: "404" }.to_json)

        result = GeocodingService.new("99999").call

        expect(result).to be_nil
      end

    end

    context 'when input is blank' do

      it 'returns nil for empty string' do
        stub_request(:get, "#{base_url}/direct")
          .with(query: hash_including(q: ""))
          .to_return(status: 200, body: [].to_json)

        result = GeocodingService.new("").call

        expect(result).to be_nil
      end

    end

  end

end