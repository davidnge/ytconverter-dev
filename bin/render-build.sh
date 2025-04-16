## This build script is not being used. Ignore.

#!/usr/bin/env bash
# Exit on error
set -o errexit
# Print commands as they execute
set -x

echo "Starting build process for YouTube to MP3 converter"
echo "Current working directory: $(pwd)"

# Install system dependencies
apt-get update -qq 
apt-get install -y ffmpeg python3-pip curl

# Create bin/tools directory and make sure it persists
echo "Creating bin/tools directory"
mkdir -p bin/tools
touch bin/tools/README.md
echo "This directory contains tools needed for the application" > bin/tools/README.md

# Download yt-dlp directly to the project's bin/tools directory
echo "Downloading yt-dlp binary to project directory"
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o bin/tools/yt-dlp
chmod a+rx bin/tools/yt-dlp

echo "Verify yt-dlp was downloaded:"
ls -la bin/tools/yt-dlp

echo "Testing yt-dlp functionality"
./bin/tools/yt-dlp --version || echo "yt-dlp execution failed"

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

# Final verification of directory structure
echo "Final directory structure:"
find bin -type f | sort