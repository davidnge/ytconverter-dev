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
      
      # Main single-pass conversion approach
      begin
        # Fast but still reliable options
        quality_option = "--extract-audio --audio-format mp3 --audio-quality #{conversion.quality}"
        output_option = "-o \"#{output_path}\""
        format_option = "-f bestaudio"
        
        # Speed optimizations that don't sacrifice reliability
        speed_options = "--geo-bypass --no-playlist --concurrent-fragments 8"
        
        # Combined command for downloading and extracting in a single pass
        download_cmd = "yt-dlp #{format_option} #{quality_option} #{output_option} #{speed_options} #{Shellwords.escape(conversion.url)} 2>&1"
        
        Rails.logger.info("Executing optimized command: #{download_cmd}")
        
        # Execute and capture output
        download_output = `#{download_cmd}`
        download_status = $?.success?
        
        # Check for errors in output
        if !download_status || 
           download_output.include?("copyright claim") || 
           download_output.include?("Video unavailable") || 
           download_output.include?("ERROR:") ||
           download_output.include?("error") ||
           download_output.include?("not available")
          
          # Try to extract a more specific error message for the user
          error_message = if download_output.include?("copyright claim")
            "This video cannot be converted due to copyright restrictions."
          elsif download_output.include?("Video unavailable") || download_output.include?("not available")
            "This video is unavailable or has been removed."
          elsif download_output.include?("This video is private")
            "This video is private and cannot be accessed."
          elsif download_output.include?("sign in")
            "This video requires a sign-in to access."
          else
            "Unable to convert this video. It may be unavailable, private, or subject to copyright restrictions."
          end
          
          Rails.logger.error("Download failed: #{error_message}")
          return handle_error(conversion, error_message)
        end
        
        # Extract duration and title from output if possible
        begin
          # Try to get the title from the output
          title_match = download_output.match(/\[download\]\s+[^\n]+?of\s+[^\n]+?\s+"([^"]+)"/)
          title = title_match ? title_match[1] : nil
          
          # Try to get duration from output - this is a bit trickier
          duration_match = download_output.match(/Duration:\s+(\d+):(\d+)/)
          duration = nil
          if duration_match
            minutes = duration_match[1].to_i
            seconds = duration_match[2].to_i
            duration = minutes * 60 + seconds
          end
          
          # Update metadata if we found anything
          updates = {}
          updates[:title] = title if title
          updates[:duration] = duration if duration
          
          conversion.update(updates) unless updates.empty?
        rescue => e
          Rails.logger.warn("Non-critical error parsing output: #{e.message}")
          # Continue anyway, this is just metadata
        end
      rescue => e
        Rails.logger.error("Conversion error: #{e.message}")
        return handle_error(conversion, "Download failed: #{e.message.to_s.truncate(100)}. Please try a different video.")
      end
      
      # Get the actual file path
      mp3_path = Rails.root.join('storage', 'downloads', "#{video_id}.mp3").to_s
      
      Rails.logger.info("Checking for MP3 file at: #{mp3_path}")
      
      # Wait for file to be fully written
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
        
        # If we still don't have a title, try to get it from ID3 tags
        if conversion.title.blank?
          begin
            require 'open3'
            # Use ffprobe to get metadata - fast and usually pre-installed
            ffprobe_cmd = "ffprobe -v quiet -print_format json -show_format \"#{mp3_path}\""
            metadata_json, status = Open3.capture2(ffprobe_cmd)
            
            if status.success?
              metadata = JSON.parse(metadata_json)
              if metadata && metadata['format'] && metadata['format']['tags']
                # Get title from ID3 tags
                tags = metadata['format']['tags']
                title = tags['title'] || tags['TITLE']
                # Get duration from format info
                duration = metadata['format']['duration'].to_f.round if metadata['format']['duration']
                
                # Update if we found anything
                updates = {}
                updates[:title] = title if title
                updates[:duration] = duration if duration && conversion.duration.nil?
                
                conversion.update(updates) unless updates.empty?
              end
            end
          rescue => e
            Rails.logger.warn("Non-critical error getting metadata: #{e.message}")
            # Continue anyway, this is just optional metadata
          end
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
        if defined?(download_output)
          Rails.logger.error("Download output: #{download_output.truncate(500)}")
        end
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
    # IMPORTANT: Always ensure status is exactly 'failed' in lowercase for consistent detection
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