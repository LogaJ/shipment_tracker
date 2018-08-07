source 'https://rubygems.org'
ruby "~>#{File.read('.ruby-version').chomp}"

gem 'rails', '~> 4.2.10'

gem 'addressable', require: 'addressable/uri'
gem 'bootstrap-sass'
gem 'delayed_job_active_record'
gem 'dotenv'
gem 'flag-icon-sass'
gem 'git_clone_url'
gem 'haml-rails'
gem 'has_secure_token'
gem 'honeybadger', '~> 3.3'
gem 'jira-ruby', require: 'jira'
gem 'jquery-rails'
gem 'newrelic_rpm'
gem 'octokit', '4.1.0', require: false
gem 'omniauth-auth0'
gem 'omniauth'
gem 'pg_search'
gem 'pg'
gem 'rack-timeout'
gem 'rugged', '~> 0.27.0'
gem 'sass-rails'
gem 'slack-notifier'
gem 'solid_use_case'
gem 'therubyracer'
gem 'uglifier'
gem 'unicorn-rails'
gem 'unicorn'
gem 'virtus'

group :development do
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'foreman', require: false
  gem 'spring'
  gem 'spring-commands-rspec'
  gem 'guard-rspec', require: false
  gem 'guard-cucumber', require: false
  gem 'mailcatcher'
end

group :development, :test do
  gem 'rspec-rails'
  gem 'rubocop'
  gem 'pry', require: false
end

group :production do
  gem 'rails_12factor'
end

group :test do
  gem 'capybara'
  gem 'cucumber-rails', require: false
  gem 'database_cleaner'
  gem 'factory_bot'
  gem 'rack-test', require: 'rack/test'
  gem 'shoulda-matchers', require: false
  gem 'simplecov', require: false
  gem 'webmock', require: false
end
