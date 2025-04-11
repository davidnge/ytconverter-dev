require 'shellwords'
require 'timeout'

class ConversionWorker
  include Sidekiq::Worker
  
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
      
      # Set the output path - sanitize to avoid command injection
      output_path = Rails.root.join('storage', 'downloads', "#{video_id}.%(ext)s").to_s
      
      # Get video info using a direct call to yt-dlp
      begin
        # Use yt-dlp to get video info - properly escape the URL
        info_cmd = "yt-dlp -j #{Shellwords.escape(conversion.url)} 2>&1"  # Redirect stderr to stdout to capture all output
        Rails.logger.info("Executing info command: #{info_cmd}")
        
        # Use Ruby's timeout instead of the shell timeout command
        video_info_json = ""
        begin
          Timeout.timeout(30) do  # 30 second timeout
            video_info_json = `#{info_cmd}`
          end
        rescue Timeout::Error
          Rails.logger.error("Info command timed out after 30 seconds")
          return handle_error(conversion, "The request timed out. This video may be too large or unavailable.")
        end
        
        output_status = $?.success?
        Rails.logger.info("yt-dlp info command exit status: #{output_status}")
        
        # Check for various error patterns in the output string itself
        if !output_status || 
           video_info_json.include?("copyright claim") || 
           video_info_json.include?("Video unavailable") || 
           video_info_json.include?("ERROR:") ||
           video_info_json.include?("error")
          
          # Try to extract the actual error message
          error_message = "Failed to fetch video info"
          
          # Look for common error patterns
          if video_info_json.include?("copyright claim")
            error_message = "This video is unavailable due to a copyright claim."
          elsif video_info_json.include?("Video unavailable")
            error_message = "This video is no longer available."
          elsif video_info_json.include?("Private video")
            error_message = "This video is private and cannot be accessed."
          elsif video_info_json.include?("has been removed")
            error_message = "This video has been removed."
          elsif video_info_json.include?("sign in")
            error_message = "This video requires sign-in to access."
          end
          
          Rails.logger.error("Video fetch error: #{error_message}")
          Rails.logger.error("yt-dlp output: #{video_info_json}")
          
          return handle_error(conversion, error_message)
        end
        
        begin
          video_info = JSON.parse(video_info_json)
          Rails.logger.info("Successfully parsed video info JSON")
        rescue JSON::ParserError => e
          Rails.logger.error("JSON parse error: #{e.message}")
          Rails.logger.error("Raw output: #{video_info_json}")
          return handle_error(conversion, "Unable to process video information. Please try a different video.")
        end
        
        # Validate video duration to allow longer videos but with a reasonable limit
        if video_info['duration'] && video_info['duration'] > 7200 # 2 hour limit
          Rails.logger.info("Video too long: #{video_info['duration']} seconds")
          return handle_error(conversion, "Video is too long. Please choose a video under 2 hours.")
        end
        
        # Auto-adjust quality for videos over 1 hour to conserve file size
        original_quality = conversion.quality
        if video_info['duration'] && video_info['duration'] > 3600 && conversion.quality == "320"
          conversion.quality = "192"
          Rails.logger.info("Auto-adjusting quality from #{original_quality} to 192 kbps for long video (#{video_info['duration']} seconds)")
        end
        
        Rails.logger.info("Updating conversion record with title and duration")
        # Update conversion with video info immediately
        conversion.update(
          title: video_info['title'],
          duration: video_info['duration'].to_i,
          quality: conversion.quality # This will save the possibly adjusted quality
        )
      rescue => e
        Rails.logger.error("Video info error: #{e.message}\n#{e.backtrace.join("\n")}")
        return handle_error(conversion, "Failed to fetch video info: #{e.message}")
      end
      
      # Download and convert the video using yt-dlp
      begin
        quality_option = "-f bestaudio --extract-audio --audio-format mp3 --audio-quality #{conversion.quality}"
        output_option = "-o \"#{output_path}\""
        
        # Add progress report
        progress_option = "--progress"
        
        # Properly shell-escape the URL for security
        download_cmd = "yt-dlp #{quality_option} #{output_option} #{progress_option} #{Shellwords.escape(conversion.url)}"
        
        Rails.logger.info("Executing download command: #{download_cmd}")
        
        # Use Open3 to capture output
        require 'open3'
        
        download_output = ""
        download_error = ""
        pid = nil
        
        # Set timeout for the entire download process - 10 minutes
        begin
          Timeout.timeout(600) do  # 10 minute timeout
            Open3.popen3(download_cmd) do |stdin, stdout, stderr, wait_thr|
              pid = wait_thr.pid
              
              # Process is running. Periodically touch the conversion record to prevent timeout issues
              monitor_thread = Thread.new do
                while wait_thr.alive?
                  # Touch the record every 30 seconds to keep it fresh
                  Conversion.where(id: conversion.id).update_all(updated_at: Time.now)
                  
                  # Also check if the conversion has been cancelled or failed elsewhere
                  refreshed_conversion = Conversion.find(conversion.id)
                  if refreshed_conversion.status == 'failed'
                    Process.kill('TERM', pid) rescue nil
                    Thread.exit
                  end
                  
                  sleep 30
                end
              end
              
              # Capture output and error streams with real-time checks for error conditions
              stdout_thread = Thread.new do
                stdout.each_line do |line|
                  download_output += line
                  
                  # Check for copyright issues in real-time
                  if line.include?("copyright claim") || line.include?("Video unavailable")
                    error_message = line.include?("copyright claim") ? 
                      "This video is unavailable due to a copyright claim." : 
                      "This video is no longer available."
                    
                    Rails.logger.error("Real-time error detection: #{error_message}")
                    # Mark as failed and then kill the process
                    handle_error(conversion, error_message)
                    Process.kill('TERM', pid) rescue nil
                    Thread.exit
                  end
                end
              end
              
              stderr_thread = Thread.new do
                stderr.each_line do |line|
                  download_error += line
                  
                  # Check for copyright issues in real-time
                  if line.include?("copyright claim") || line.include?("Video unavailable")
                    error_message = line.include?("copyright claim") ? 
                      "This video is unavailable due to a copyright claim." : 
                      "This video is no longer available."
                    
                    Rails.logger.error("Real-time error detection: #{error_message}")
                    # Mark as failed and then kill the process
                    handle_error(conversion, error_message)
                    Process.kill('TERM', pid) rescue nil
                    Thread.exit
                  end
                end
              end
              
              # Wait for process to complete
              exit_status = wait_thr.value
              monitor_thread.exit if monitor_thread.alive?
              stdout_thread.join
              stderr_thread.join
              
              Rails.logger.info("Download command exit status: #{exit_status.success?}")
              
              # Check for error conditions
              unless exit_status.success?
                error_message = "Failed to download video"
                
                # Check for specific error messages in the output or error
                if download_output.include?("copyright claim") || download_error.include?("copyright claim")
                  error_message = "Could not convert video due to a copyright claim."
                elsif download_output.include?("Video unavailable") || download_error.include?("Video unavailable")
                  error_message = "Video is no longer available."
                elsif download_output.include?("Private video") || download_error.include?("Private video")
                  error_message = "This video is private and cannot be accessed."
                elsif download_output.include?("sign in") || download_error.include?("sign in")
                  error_message = "This video requires sign-in to access."
                end
                
                Rails.logger.error("Download failed: #{error_message}")
                
                return handle_error(conversion, error_message)
              end
            end
          end
        rescue Timeout::Error
          Rails.logger.error("Conversion timed out after 10 minutes")
          # Try to kill the process if it's still running
          Process.kill('TERM', pid) rescue nil
          return handle_error(conversion, "The conversion process timed out. Please try a shorter video.")
        end
        
        # Get the actual file path
        mp3_path = Rails.root.join('storage', 'downloads', "#{video_id}.mp3").to_s
        
        Rails.logger.info("Checking for MP3 file at: #{mp3_path}")
        
        if File.exist?(mp3_path)
          # Check file size - limit to reasonable size
          file_size = File.size(mp3_path)
          Rails.logger.info("MP3 file size: #{file_size} bytes")
          
          if file_size > 200.megabytes
            File.delete(mp3_path)
            Rails.logger.info("Deleted file due to exceeding size limit")
            return handle_error(conversion, "The generated MP3 file exceeds the maximum size limit (200MB). Please try a shorter video or a lower quality setting.")
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
        Rails.logger.error("Conversion error: #{e.message}\n#{e.backtrace.join("\n")}")
        handle_error(conversion, "Download failed: #{e.message}")
      end
    rescue => e
      Rails.logger.error("Unhandled error in ConversionWorker: #{e.message}\n#{e.backtrace.join("\n")}")
      begin
        conversion = Conversion.find(conversion_id) if defined?(conversion_id)
        handle_error(conversion, "An unexpected error occurred: #{e.message}") if conversion
      rescue => nested_error
        Rails.logger.error("Failed to handle error: #{nested_error.message}")
      end
    end
  end
  
  private
  
  def handle_error(conversion, message)
    Rails.logger.error("Setting error for conversion #{conversion.id}: #{message}")
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