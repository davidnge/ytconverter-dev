# YouTube API configuration
Yt.configure do |config|
  # No API key is required for simple information retrieval
  # but if you have one, you can configure it here:
  # config.api_key = ENV['YOUTUBE_API_KEY']
end

schedule_file = "config/schedule.yml"

if File.exist?(schedule_file) && Sidekiq.server?
  Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
end