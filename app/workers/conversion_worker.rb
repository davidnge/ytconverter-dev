
require 'shellwords'

class ConversionWorker
  include Sidekiq::Worker
  
  def perform(conversion_id)
    conversion = Conversion.find(conversion_id)
    conversion.update(status: 'processing')
    
    begin
      # Create directory for downloads if it doesn't exist
      FileUtils.mkdir_p(Rails.root.join('storage', 'downloads'))
      
      # Extract video ID from URL
      video_id = conversion.youtube_id
      return handle_error(conversion, "Invalid YouTube URL") unless video_id
      
      # Set the output path - sanitize to avoid command injection
      output_path = Rails.root.join('storage', 'downloads', "#{video_id}.%(ext)s").to_s
      
      # Get video info using a direct call to yt-dlp
      begin
        # Use yt-dlp to get video info - properly escape the URL
        info_cmd = "yt-dlp -j #{Shellwords.escape(conversion.url)}"
        video_info_json = `#{info_cmd}`
        
        unless $?.success?
          return handle_error(conversion, "Failed to fetch video info: yt-dlp command failed")
        end
        
        video_info = JSON.parse(video_info_json)
        
        # Validate video duration to prevent abuse
        if video_info['duration'] && video_info['duration'] > 3600 # 1 hour limit
          return handle_error(conversion, "Video is too long. Please choose a video under 1 hour.")
        end
        
        conversion.update(
          title: video_info['title'],
          duration: video_info['duration'].to_i
        )
      rescue => e
        return handle_error(conversion, "Failed to fetch video info: #{e.message}")
      end
      
      # Download and convert the video using yt-dlp
      begin
        quality_option = "-f bestaudio --extract-audio --audio-format mp3 --audio-quality #{conversion.quality}"
        output_option = "-o \"#{output_path}\""
        
        # Properly shell-escape the URL for security
        download_cmd = "yt-dlp #{quality_option} #{output_option} #{Shellwords.escape(conversion.url)}"
        system(download_cmd)
        
        unless $?.success?
          return handle_error(conversion, "Download failed: yt-dlp command failed")
        end
        
        # Get the actual file path
        mp3_path = Rails.root.join('storage', 'downloads', "#{video_id}.mp3").to_s
        
        if File.exist?(mp3_path)
          # Check file size - limit to reasonable size (e.g., 100MB)
          if File.size(mp3_path) > 100.megabytes
            File.delete(mp3_path)
            return handle_error(conversion, "Generated file is too large")
          end
          
          conversion.update(
            status: 'completed',
            file_path: mp3_path
          )
        else
          handle_error(conversion, "MP3 file was not created successfully")
        end
      rescue => e
        handle_error(conversion, "Download failed: #{e.message}")
      end
    rescue => e
      handle_error(conversion, e.message)
    end
  end
  
  private
  
  def handle_error(conversion, message)
    conversion.update(
      status: 'failed',
      error_message: message
    )
  end
end


# to remove old files
class CleanupWorker
  include Sidekiq::Worker
  
  def perform
    # Delete files older than 24 hours
    Conversion.old.each do |conversion|
      conversion.cleanup_file
    end
    
    # Log cleanup stats
    Rails.logger.info("CleanupWorker completed: cleaned up old conversion files")
  end
end