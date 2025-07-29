source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.9'

# Rails 8.0
gem 'rails', '~> 8.0.0'

# Database
gem 'mysql2', '~> 0.5'

# Web server
gem 'puma', '~> 6.0'

# Assets and Frontend
gem 'sprockets-rails'
gem 'importmap-rails'
gem 'stimulus-rails'
gem 'turbo-rails'
gem 'tailwindcss-rails'

# JSON APIs
gem 'jbuilder'

# Authentication & Authorization
gem 'bcrypt', '~> 3.1.7'
gem 'jwt'

# AWS Integration
gem 'aws-sdk-core'
gem 'aws-sdk-bedrock'
gem 'aws-sdk-servicequotas'

# Encryption
gem 'attr_encrypted'

# Background Jobs
gem 'sidekiq'

# Caching
gem 'redis', '~> 5.0'

# Pagination
gem 'kaminari'

# View Components
gem 'view_component'

# Configuration
gem 'dotenv-rails'

# Monitoring
gem 'bootsnap', require: false

# Security
gem 'rack-cors'

# Time zones
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

group :development, :test do
  gem 'debug', platforms: %i[ mri mingw x64_mingw ]
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rubocop-rails', require: false
  gem 'brakeman', require: false
end

group :development do
  gem 'web-console'
  gem 'listen', '~> 3.3'
  gem 'spring'
  gem 'annotate'
end

group :test do
  gem 'capybara'
  gem 'selenium-webdriver'
  gem 'shoulda-matchers'
  gem 'database_cleaner-active_record'
end

group :production do
  # Production gems
end
