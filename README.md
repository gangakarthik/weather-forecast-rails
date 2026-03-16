# Weather Forecast Application

A Ruby on Rails application that accepts an address as input, retrieves weather forecast data from the OpenWeatherMap API, and displays current conditions plus a 5-day forecast. Results are cached by zip code for 30 minutes.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture & Object Decomposition](#architecture--object-decomposition)
- [Design Patterns](#design-patterns)
- [Caching Strategy](#caching-strategy)
- [Setup & Installation](#setup--installation)
- [Running the Application](#running-the-application)
- [Running Tests](#running-tests)
- [Environment Variables](#environment-variables)
- [API Reference](#api-reference)
- [Error Handling](#error-handling)

---

## Features

- Accept any city name or zip code as input address
- Display current temperature in Celsius and Fahrenheit
- Display high / low temperatures
- Display feels like, humidity, wind speed
- Display 5-day extended forecast
- Cache results by zip code for 30 minutes
- Visual indicator showing if result is from cache or live API
- Graceful error handling for invalid addresses

---

## Tech Stack

| Technology | Version | Purpose |
|-----------|---------|---------|
| Ruby | 3.2.2 | Language |
| Rails | 7.1.6 | Web Framework |
| SQLite | 3.x | Database |
| Puma | 6.4.3 | Web Server |
| RSpec | 3.13 | Testing |
| WebMock | 3.x | API Mocking in Tests |
| OpenWeatherMap API | 2.5 | Weather Data |

---

## Architecture & Object Decomposition
```
app/
├── controllers/
│   └── forecasts_controller.rb   # HTTP layer - handles requests/responses
├── services/
│   ├── geocoding_service.rb      # Converts address to location data
│   └── forecast_service.rb       # Fetches weather data with caching
└── views/
    └── forecasts/
        └── index.html.erb        # Displays forecast to user
```

### ForecastsController

Responsibilities:
- Accept address input from user
- Delegate to GeocodingService and ForecastService
- Handle errors and render appropriate responses

Input: HTTP POST with address param
Output: Rendered view with forecast data or error message

### GeocodingService

Responsibilities:
- Convert human-readable address into structured location data
- Detect whether input is a city name or zip code
- Return city, country, zip_code, lat, lon

Input: address (String) e.g. "London" or "10001"
Output: Hash { city:, country:, zip_code:, lat:, lon: } or nil

### ForecastService

Responsibilities:
- Fetch current weather from OpenWeatherMap
- Fetch 5-day forecast from OpenWeatherMap
- Cache results by zip code for 30 minutes
- Convert temperatures from Kelvin to Celsius/Fahrenheit
- Return structured forecast data with cache indicator

Input: location (Hash) from GeocodingService
Output: Hash { current:, forecast:, cached: } or nil

---

## Design Patterns

### Service Object Pattern
Business logic is extracted into dedicated service classes rather than
placed in controllers. Each service has a single `call` method as its
public interface.

Benefits:
- Single Responsibility Principle — each service does one thing only
- Easy to test in isolation using mocks
- Reusable across multiple controllers
- Controllers stay thin and focused on HTTP concerns

### Thin Controller Pattern
The controller delegates all business logic to service objects and
only handles HTTP concerns such as params, rendering and redirecting.


### Single Responsibility Principle
Every class and method has one clearly defined job:

| Class/Method | Single Responsibility |
|-------------|----------------------|
| `GeocodingService` | Address → Location only |
| `ForecastService` | Location → Weather only |
| `ForecastsController` | HTTP request/response only |
| `fetch_from_api` | HTTP call only |
| `parse_current_weather` | Parse current data only |
| `build_daily_forecast` | Build one day summary only |
| `kelvin_to_celsius` | Temperature conversion only |

### Encapsulation
All internal implementation details are kept private. Only the `call`
method is public — callers do not need to know how the service works
internally.


### Code Re-Use
The `fetch_from_api` method is shared by both `fetch_current_weather`
and `fetch_five_day_forecast` to avoid duplication:

---

## Caching Strategy

Results are cached using Rails built-in memory store.

- **Cache Key**: `forecast_{zip_code}` (e.g. `forecast_London-GB`)
- **Cache TTL**: 30 minutes
- **Cache Store**: `:memory_store`
- **Cache Indicator**: UI shows Cached Result or Live Result

Why zip code as cache key?
- User might type "London", "london", "London, UK" — all resolve to same zip
- Ensures same location always hits the same cache entry
- More reliable than using raw address string

---

## Setup & Installation

### Prerequisites
- Ruby 3.2.2
- Rails 7.1.6
- OpenWeatherMap API key (free at openweathermap.org)

### Installation

**1. Clone the repository**
```bash
git clone https://github.com/gangakarthik/weather-forecast-rails.git
cd weather-forecast-rails
```

**2. Install dependencies**
```bash
bundle install
```

**3. Set up environment variables**
```bash
cp .env.example .env
# Edit .env and add your OpenWeatherMap API key
```

**4. Set up database**
```bash
rails db:create
```

**5. Enable caching in development**
```bash
rails dev:cache
```

---

## Running the Application
```bash
rails server
```

Visit **http://localhost:3000**

Enter any city name or zip code to get the weather forecast.

---

## Running Tests

**Run all tests**
```bash
bundle exec rspec
```

**Run specific test files**
```bash
bundle exec rspec spec/services/geocoding_service_spec.rb
bundle exec rspec spec/services/forecast_service_spec.rb
bundle exec rspec spec/requests/forecasts_spec.rb
```

**Test coverage includes:**
- GeocodingService — valid city, zip code, not found, API errors
- ForecastService — cache miss, cache hit, API errors, temperature conversion
- ForecastsController — valid address, empty address, invalid address, cached results

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENWEATHER_API_KEY` | Your OpenWeatherMap API key |

Create a `.env` file in the project root:
```
OPENWEATHER_API_KEY=your_api_key_here
```

---

## API Reference

### OpenWeatherMap APIs Used

**Geocoding API**
```
GET http://api.openweathermap.org/geo/1.0/direct?q={city}&limit=1&appid={key}
GET http://api.openweathermap.org/geo/1.0/zip?zip={zip}&appid={key}
```

**Weather API**
```
GET http://api.openweathermap.org/data/2.5/weather?q={city},{country}&appid={key}
GET http://api.openweathermap.org/data/2.5/forecast?q={city},{country}&appid={key}
```

---

## Error Handling

| Scenario | Response |
|----------|----------|
| Empty address | "Please enter a valid address" |
| City not found | "Could not find '{address}'" |
| No weather data | "Could not fetch forecast for smaller areas" |
| API down | Graceful error message, nil returned |