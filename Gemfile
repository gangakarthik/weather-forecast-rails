source "https://rubygems.org"

ruby "3.2.2"

gem "rails", "~> 7.1.5"
gem "sprockets-rails"
gem "sqlite3", ">= 1.4"
gem "puma", "6.4.3"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# Pinned for Ruby 3.2.2 Windows compatibility
gem "date", "3.3.3"
gem "psych", "~> 4.0"
gem "stringio", "3.0.4"
gem "erb", "~> 2.2"
gem "cgi", "0.3.6"
gem "minitest", "~> 5.18"
gem "irb", "~> 1.6"
gem "prism", "1.9.0"
gem "io-console", "0.6.0"

gem "dotenv-rails", groups: [:development, :test]

group :development do
  gem "web-console"
end

group :development, :test do
  gem "rspec-rails"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "webmock"
  gem "factory_bot_rails"
end