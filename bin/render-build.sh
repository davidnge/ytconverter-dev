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

# Database commands for PostgreSQL
RAILS_ENV=production bundle exec rails db:create || true
RAILS_ENV=production bundle exec rails db:schema:load || true
RAILS_ENV=production bundle exec rails db:migrate || true

# Ensure storage directories exist
mkdir -p storage/downloads
chmod -R 777 storage