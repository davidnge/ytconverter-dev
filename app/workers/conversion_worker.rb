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
      
      # Setup cookie option if environment variable exists
      cookie_option = ""
      if ENV['YOUTUBE_COOKIES'].present?
        begin
          # Create a temporary cookie file
          cookie_file = Tempfile.new(['youtube_cookies', '.txt'])
          cookie_data = ENV['YOUTUBE_COOKIES']
          
          # Ensure proper cookie format (Netscape format)
          if !cookie_data.start_with?("# HTTP Cookie File") && !cookie_data.start_with?("# Netscape HTTP Cookie File")
            cookie_file.puts("# Netscape HTTP Cookie File")
            
            # If it looks like JSON, try to parse and convert
            if cookie_data.strip.start_with?('{') || cookie_data.strip.start_with?('[')
              begin
                require 'json'
                cookies_json = JSON.parse(cookie_data)
                
                # Process cookies based on structure
                if cookies_json.is_a?(Array)
                  cookies_json.each do |cookie|
                    # Only process YouTube domains
                    next unless cookie['domain'] && cookie['domain'].include?('youtube')
                    
                    domain = cookie['domain']
                    flag = domain.start_with?('.') ? "TRUE" : "FALSE"
                    path = cookie['path'] || '/'
                    secure = cookie['secure'] ? "TRUE" : "FALSE"
                    expiry = cookie['expirationDate'] || (Time.now.to_i + 2592000) # 30 days
                    name = cookie['name']
                    value = cookie['value']
                    
                    cookie_file.puts("#{domain}\t#{flag}\t#{path}\t#{secure}\t#{expiry}\t#{name}\t#{value}")
                  end
                end
              rescue => e
                # If JSON parsing fails, just use the raw cookie data
                Rails.logger.warn("Failed to parse JSON cookies: #{e.message}")
                cookie_file.write(cookie_data)
              end
            else
              # Not JSON, so write directly
              cookie_file.write(cookie_data)
            end
          else
            # Already in Netscape format
            cookie_file.write(cookie_data)
          end
          
          cookie_file.close
          cookie_option = "--cookies #{Shellwords.escape(cookie_file.path)}"
          Rails.logger.info("Using YouTube cookies from environment variable")
        rescue => e
          Rails.logger.error("Error setting up cookie file: #{e.message}")
          # Continue without cookies if there's an error
        end
      end
      
      # SUPER-OPTIMIZED DOWNLOAD APPROACH
      begin
        # Build the optimal yt-dlp command using carefully selected options
        # Format selection is critical - directly request audio formats 
        format_option = "-f 251/140/250/249/bestaudio[ext=webm]/m4a"
        
        # Quality settings for output - add --embed-metadata to preserve title in the MP3
        quality_option = "--extract-audio --audio-format mp3 --audio-quality #{conversion.quality} --embed-metadata"
        output_option = "-o \"#{output_path}\""
        
        # Combine our optimizations with your existing ones
        # Note: Added --no-warnings to reduce log spam
        speed_options = "--no-playlist --no-check-certificates --geo-bypass --quiet -N 16 --no-simulate --no-progress --no-part --no-mtime --no-cache-dir --no-call-home --no-warnings"
        
        # yt-dlp in bin/tools
        ytdlp_path = Rails.root.join('bin', 'tools', 'yt-dlp').to_s
        download_cmd = "#{ytdlp_path} #{format_option} #{quality_option} #{output_option} #{speed_options} #{cookie_option} #{Shellwords.escape(conversion.url)} 2>&1"
        
        Rails.logger.info("Executing ultra-optimized command with cookie authentication")
        
        # Execute with increased timeout - simply increase the timeout to 10 minutes (600 seconds)
        require 'timeout'
        download_output = ""
        
        begin
          # Increase timeout from 120 seconds to 600 seconds (10 minutes)
          Timeout.timeout(600) do
            download_output = `#{download_cmd}`
          end
          download_status = $?.success?
        rescue Timeout::Error
          Rails.logger.error("Command timed out after 600 seconds")
          return handle_error(conversion, "Conversion timed out. Please try a different video.")
        end
        
        # Handle authentication errors specifically
        if download_output.include?("Sign in to confirm you're not a bot") || download_output.include?("Please sign in")
          Rails.logger.error("YouTube authentication error detected, retrying with rate limits")
          
          # Try again with rate limiting to avoid detection
          rate_limit_option = "--sleep-requests 1 --sleep-interval 5 --max-sleep-interval 10"
          retry_cmd = "#{ytdlp_path} #{format_option} #{quality_option} #{output_option} #{speed_options} #{rate_limit_option} #{cookie_option} #{Shellwords.escape(conversion.url)} 2>&1"
          
          begin
            Timeout.timeout(600) do
              download_output = `#{retry_cmd}`
            end
            download_status = $?.success?
          rescue Timeout::Error
            Rails.logger.error("Retry command timed out")
            return handle_error(conversion, "Authentication error. Please try a different video.")
          end
        end
        
        # Check for error conditions
        if !download_status || 
           download_output.include?("copyright claim") || 
           download_output.include?("Video unavailable") || 
           download_output.include?("ERROR:") ||
           download_output.include?("error")
          
          error_message = if download_output.include?("copyright claim")
            "This video cannot be converted due to copyright restrictions."
          elsif download_output.include?("Video unavailable")
            "This video is unavailable or has been removed."
          elsif download_output.include?("Private video")
            "This video is private and cannot be accessed."
          else
            "Unable to convert this video. Please try a different one."
          end
          
          Rails.logger.error("Download failed: #{error_message}")
          Rails.logger.debug("Download output: #{download_output.truncate(500)}")
          return handle_error(conversion, error_message)
        end
        
        # Try to extract video title from download output
        youtube_title = nil
        if download_output =~ /\[download\] Destination: (.+?)$/
          youtube_title = $1.strip.gsub(/\.\w+$/, '')  # Strip file extension
        end
        Rails.logger.info("Extracted title from output: #{youtube_title}") if youtube_title
      rescue => e
        Rails.logger.error("Conversion error: #{e.message}")
        return handle_error(conversion, "Download failed. Please try a different video.")
      ensure
        # Clean up temporary cookie file if one was created
        cookie_file.unlink if defined?(cookie_file) && cookie_file && !cookie_file.closed?
      end
      
      # Check for the MP3 file
      mp3_path = Rails.root.join('storage', 'downloads', "#{video_id}.mp3").to_s
      
      Rails.logger.info("Checking for MP3 file at: #{mp3_path}")
      
      if File.exist?(mp3_path)
        # Check file size
        file_size = File.size(mp3_path)
        Rails.logger.info("MP3 file size: #{file_size} bytes")
        
        if file_size > 200.megabytes
          File.delete(mp3_path)
          Rails.logger.info("Deleted file due to exceeding size limit")
          return handle_error(conversion, "The generated MP3 file exceeds the maximum size limit (200MB). Please try a shorter video or a lower quality setting.")
        end
        
        if file_size < 1000
          File.delete(mp3_path)
          Rails.logger.error("File is too small or empty (#{file_size} bytes)")
          return handle_error(conversion, "The generated MP3 file is invalid. Please try a different video.")
        end
        
        # Get title and duration using ffprobe - fast and reliable
        title = nil
        duration = nil
        
        begin
          require 'open3'
          ffprobe_cmd = "ffprobe -v quiet -print_format json -show_format \"#{mp3_path}\""
          metadata_json, status = Open3.capture2(ffprobe_cmd)
          
          if status.success?
            metadata = JSON.parse(metadata_json)
            if metadata && metadata['format']
              # Get title from tags
              if metadata['format']['tags']
                title = metadata['format']['tags']['title'] 
              end
              
              # Get duration directly
              duration = metadata['format']['duration'].to_f.round if metadata['format']['duration']
            end
          end
        rescue => e
          Rails.logger.warn("Non-critical error reading metadata: #{e.message}")
          # Continue anyway - this is just for metadata
        end
        
        # Update title info if available
        updates = {}
        updates[:title] = title || youtube_title || video_id
        updates[:duration] = duration if duration
        
        # Mark as completed and save metadata
        updates[:status] = 'completed'
        updates[:file_path] = mp3_path
        
        conversion.update(updates)
        
        Rails.logger.info("Conversion completed successfully: #{mp3_path}")
      else
        Rails.logger.error("MP3 file was not created at: #{mp3_path}")
        return handle_error(conversion, "MP3 file was not created successfully. Please try a different video.")
      end
    rescue => e
      Rails.logger.error("Unhandled error in ConversionWorker: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      
      begin
        conversion = Conversion.find(conversion_id) if defined?(conversion_id)
        message = "An unexpected error occurred: #{e.message.to_s.truncate(100)}. Please try a different video."
        handle_error(conversion, message) if conversion
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
    
    # Force a reload to ensure database has the updated state
    conversion.reload
    
    # Log the state after update to help with debugging
    Rails.logger.info("Conversion #{conversion.id} error state set: status=#{conversion.status}, message=#{conversion.error_message}")
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