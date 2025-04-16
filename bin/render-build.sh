#!/usr/bin/env bash
# Exit on error
set -o errexit

# Install system dependencies
apt-get update -qq 
apt-get install -y ffmpeg python3-pip

# Install yt-dlp via apt
# Try to add PPA if available (this might fail on some systems, but we continue anyway)
add-apt-repository -y ppa:tomtomtom/yt-dlp || echo "Could not add PPA, continuing with default repos"
apt-get update -qq
apt-get install -y yt-dlp || echo "yt-dlp not found in repositories, trying alternate method"

# Fallback method: If apt installation fails, try direct download of the binary
if ! command -v yt-dlp &> /dev/null; then
    echo "Installing yt-dlp binary directly"
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    chmod a+rx /usr/local/bin/yt-dlp
fi

# Verify yt-dlp is installed and working
yt-dlp --version || echo "Warning: yt-dlp installation may have issues"

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