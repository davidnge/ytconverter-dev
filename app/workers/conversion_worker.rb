require 'shellwords'

class ConversionWorker
  include Sidekiq::Worker
  sidekiq_options retry: 1  # Reduce retries for faster failure detection
  
  def perform(conversion_id)
    begin
      Rails.logger.info("Starting conversion for ID: #{conversion_id}")
      conversion = Conversion.find(conversion_id)
      conversion.update(status: 'processing')
      
      Rails.logger.info("Processing conversion with URL: #{conversion.url}")
      
      # Create directory for downloads if it doesn't exist
      FileUtils.mkdir_p(Rails.root.join('storage', 'downloads'))
      
      # Extract video ID from URL
      video_id = conversion.youtube_id
      Rails.logger.info("Extracted video ID: #{video_id}")
      return handle_error(conversion, "Invalid YouTube URL") unless video_id
      
      # Check for existing processed file with same video and quality - only if the column exists
      if ActiveRecord::Base.connection.column_exists?(:conversions, :youtube_id)
        begin
          existing_conversion = Conversion.where(status: 'completed', 
                                               youtube_id: video_id, 
                                               quality: conversion.quality)
                                         .where('created_at > ?', 12.hours.ago)
                                         .first
                      
          if existing_conversion && File.exist?(existing_conversion.file_path)
            # Efficiently reuse existing conversion
            Rails.logger.info("Reusing existing conversion: #{existing_conversion.id}")
            conversion.update(
              status: 'completed',
              title: existing_conversion.title,
              duration: existing_conversion.duration,
              file_path: existing_conversion.file_path
            )
            return
          end
        rescue => e
          # If any error occurs here, just log it and continue with normal processing
          Rails.logger.error("Error checking for existing conversion: #{e.message}")
        end
      end
      
      # Set the output path - sanitize to avoid command injection
      output_path = Rails.root.join('storage', 'downloads', "#{video_id}.%(ext)s").to_s
      
      begin
        # Use streamlined yt-dlp info command with optimizations 
        # This is more reliable than combining commands - improves total speed by a lot
        info_cmd = "yt-dlp -j --skip-download --geo-bypass #{Shellwords.escape(conversion.url)} 2>&1"
        Rails.logger.info("Executing info command: #{info_cmd}")
        
        video_info_json = `#{info_cmd}`
        output_status = $?.success?
        
        Rails.logger.info("yt-dlp info command exit status: #{output_status}")
        
        # Check for various error patterns
        if !output_status || 
           video_info_json.include?("copyright claim") || 
           video_info_json.include?("Video unavailable") || 
           video_info_json.include?("ERROR:") ||
           video_info_json.include?("error")
          
          error_message = "Unable to convert this video. It may be unavailable, private, or subject to copyright restrictions."
          Rails.logger.error("Video fetch error: #{error_message}")
          return handle_error(conversion, error_message)
        end
        
        begin
          # Skip any warnings or preceding text if present (only take valid JSON)
          json_start = video_info_json.index('{')
          if json_start && json_start > 0
            video_info_json = video_info_json[json_start..-1]
          end
          
          video_info = JSON.parse(video_info_json)
          Rails.logger.info("Successfully parsed video info JSON")
        rescue JSON::ParserError => e
          Rails.logger.error("JSON parse error: #{e.message}")
          return handle_error(conversion, "Unable to process video information. Please try a different video.")
        end
        
        # Validate video duration
        if video_info['duration'] && video_info['duration'] > 7200 # 2 hour limit
          Rails.logger.info("Video too long: #{video_info['duration']} seconds")
          return handle_error(conversion, "Video is too long. Please choose a video under 2 hours.")
        end
        
        # Auto-adjust quality for longer videos
        original_quality = conversion.quality
        if video_info['duration'] && video_info['duration'] > 3600 && conversion.quality == "320"
          conversion.quality = "192" 
          Rails.logger.info("Auto-adjusting quality from #{original_quality} to 192 kbps for long video (#{video_info['duration']} seconds)")
        end
        
        # Update conversion with video info immediately
        conversion.update(
          title: video_info['title'],
          duration: video_info['duration'].to_i,
          quality: conversion.quality # This will save the possibly adjusted quality
        )
      rescue => e
        Rails.logger.error("Video info error: #{e.message}")
        return handle_error(conversion, "Failed to fetch video info. Please try a different video.")
      end
      
      # Download and convert the video using yt-dlp - separate for better reliability
      begin
        # Optimize yt-dlp configuration for faster performance - but keep it simple
        quality_option = "-f bestaudio --extract-audio --audio-format mp3 --audio-quality #{conversion.quality}"
        output_option = "-o \"#{output_path}\""
        progress_option = "--progress"
        
        # Add minimal optimizations that are known to work reliably
        optimization_options = "--geo-bypass"
        
        # Properly shell-escape the URL for security
        download_cmd = "yt-dlp #{quality_option} #{output_option} #{progress_option} #{optimization_options} #{Shellwords.escape(conversion.url)}"
        
        Rails.logger.info("Executing download command: #{download_cmd}")
        
        # Use system to run the command directly - it should work reliably in all environments
        system_result = system(download_cmd)
        
        Rails.logger.info("Download command result: #{system_result}")
        
        # Check for success
        unless system_result
          error_message = "Unable to convert this video. It may be unavailable, private, or subject to copyright restrictions."
          Rails.logger.error("Download failed: #{error_message}")
          return handle_error(conversion, error_message)
        end
      rescue => e
        Rails.logger.error("Conversion error: #{e.message}")
        handle_error(conversion, "Download failed. Please try a different video.")
      end
      
      # Get the actual file path
      mp3_path = Rails.root.join('storage', 'downloads', "#{video_id}.mp3").to_s
      
      Rails.logger.info("Checking for MP3 file at: #{mp3_path}")
      
      # Wait a moment for the file to be fully written
      sleep(1)
      
      if File.exist?(mp3_path)
        # Check file size - limit to reasonable size
        file_size = File.size(mp3_path)
        Rails.logger.info("MP3 file size: #{file_size} bytes")
        
        if file_size > 200.megabytes
          File.delete(mp3_path)
          Rails.logger.info("Deleted file due to exceeding size limit")
          return handle_error(conversion, "The generated MP3 file exceeds the maximum size limit (200MB). Please try a shorter video or a lower quality setting.")
        end
        
        # Check if file is empty or too small
        if file_size < 1000
          File.delete(mp3_path)
          Rails.logger.error("File is too small or empty (#{file_size} bytes)")
          return handle_error(conversion, "The generated MP3 file is invalid. Please try a different video.")
        end
        
        # Successfully completed - update the record
        conversion.update(
          status: 'completed',
          file_path: mp3_path
        )
        
        Rails.logger.info("Conversion completed successfully: #{mp3_path}")
        
        # Touch again to ensure the record is fresh
        conversion.touch
      else
        Rails.logger.error("MP3 file was not created at: #{mp3_path}")
        handle_error(conversion, "MP3 file was not created successfully. Please try a different video.")
      end
    rescue => e
      Rails.logger.error("Unhandled error in ConversionWorker: #{e.message}")
      begin
        conversion = Conversion.find(conversion_id) if defined?(conversion_id)
        handle_error(conversion, "An unexpected error occurred. Please try a different video.") if conversion
      rescue => nested_error
        Rails.logger.error("Failed to handle error: #{nested_error.message}")
      end
    end
  end
  
  private
  
  def handle_error(conversion, message)
    Rails.logger.error("Setting error for conversion #{conversion.id}: #{message}")
    
    # Make sure to clear any existing title, duration data to prevent showing old conversion details
    conversion.update(
      status: 'failed',
      error_message: message,
      title: nil,
      duration: nil,
      file_path: nil
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