#!/usr/bin/env bash
# Exit on error
set -o errexit

# Install system dependencies
apt-get update -qq && apt-get install -y ffmpeg python3-pip

# Install yt-dlp with specific version and make it available globally
python3 -m pip install --upgrade yt-dlp
ln -sf /usr/local/bin/yt-dlp /usr/bin/yt-dlp

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

# Verify yt-dlp installation
echo "==== Testing yt-dlp installation ===="
which yt-dlp || echo "yt-dlp not found in PATH"
yt-dlp --version || echo "Could not get yt-dlp version"