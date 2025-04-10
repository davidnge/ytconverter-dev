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
      
      # Set the output path
      output_path = Rails.root.join('storage', 'downloads', "#{video_id}.%(ext)s").to_s
      
      # Get video info using a direct call to yt-dlp
      begin
        # Use yt-dlp to get video info
        info_cmd = "yt-dlp -j #{conversion.url}"
        video_info_json = `#{info_cmd}`
        
        unless $?.success?
          return handle_error(conversion, "Failed to fetch video info: yt-dlp command failed")
        end
        
        video_info = JSON.parse(video_info_json)
        
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
        
        download_cmd = "yt-dlp #{quality_option} #{output_option} #{conversion.url}"
        system(download_cmd)
        
        unless $?.success?
          return handle_error(conversion, "Download failed: yt-dlp command failed")
        end
        
        # Get the actual file path
        mp3_path = Rails.root.join('storage', 'downloads', "#{video_id}.mp3").to_s
        
        if File.exist?(mp3_path)
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