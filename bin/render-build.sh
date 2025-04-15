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
bundle exec rake db:migrate

# Ensure storage directories exist
mkdir -p storage/downloads
chmod -R 777 storage