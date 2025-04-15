#!/usr/bin/env bash
# Exit on error
set -o errexit

# Install system dependencies
apt-get update -qq && apt-get install -y ffmpeg python3-pip

# Install yt-dlp
pip3 install yt-dlp

# Build commands
bundle install
bundle exec rake assets:precompile

# Database commands - focus on primary schema
RAILS_ENV=production bundle exec rails db:create:primary || true
RAILS_ENV=production bundle exec rails db:schema:load:primary || true
RAILS_ENV=production bundle exec rails db:migrate:primary || true

# Create the other databases if needed
RAILS_ENV=production bundle exec rails db:create:cache || true
RAILS_ENV=production bundle exec rails db:create:queue || true
RAILS_ENV=production bundle exec rails db:create:cable || true

# Ensure storage directories exist
mkdir -p storage/downloads
chmod -R 777 storage