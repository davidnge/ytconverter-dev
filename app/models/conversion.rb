# app/models/conversion.rb
class Conversion < ApplicationRecord
  validates :url, presence: true, format: { 
    with: %r{\A(https?://)?(www\.)?(youtube\.com/((watch\?v=)|shorts/)|youtu\.be/)}, 
    message: "must be a valid YouTube URL" 
  }
  validates :quality, inclusion: { in: %w[128 192 320] }
  
  # Add a callback to extract and save YouTube ID before saving
  before_save :extract_youtube_id
  
  # Add a scope for finding old conversions
  scope :old, ->(time = 24.hours.ago) { where("created_at < ?", time) }
  
  # Status options: pending, processing, completed, failed
  
  def upload_to_s3
    return unless file_path.present? && File.exist?(file_path)
    
    begin
      # Generate a unique S3 key based on the youtube_id and quality
      s3_key = "mp3s/#{youtube_id}_#{quality}.mp3"
      
      # Create S3 client
      s3_client = Aws::S3::Client.new(
        region: ENV['AWS_REGION'],
        credentials: Aws::Credentials.new(
          ENV['AWS_ACCESS_KEY_ID'],
          ENV['AWS_SECRET_ACCESS_KEY']
        )
      )
      
      # Upload file with appropriate metadata
      File.open(file_path, 'rb') do |file|
        s3_client.put_object(
          bucket: ENV['AWS_BUCKET'],
          key: s3_key,
          body: file,
          content_type: 'audio/mpeg',
          content_disposition: "attachment; filename=\"#{filename}\"",
          acl: 'private' # Set to private since we'll use presigned URLs
        )
      end
      
      # Update the conversion record with the S3 URL
      s3_url = "https://#{ENV['AWS_BUCKET']}.s3.#{ENV['AWS_REGION']}.amazonaws.com/#{s3_key}"
      update(s3_url: s3_url)
      
      # Delete local file after successful upload
      File.delete(file_path)
      Rails.logger.info("File uploaded to S3: #{s3_url}")
      
      return true
    rescue StandardError => e
      Rails.logger.error("S3 upload error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      return false
    end
  end

  # Method to generate a presigned URL for secure downloads
  def presigned_download_url(expires_in = 3600) # 1 hour in seconds
    return nil unless s3_url.present?
    
    begin
      # Extract key from S3 URL
      bucket_name = ENV['AWS_BUCKET']
      s3_key = s3_url.gsub("https://#{bucket_name}.s3.#{ENV['AWS_REGION']}.amazonaws.com/", "")
      
      # Log for debugging
      Rails.logger.info("Generating presigned URL for bucket: #{bucket_name}, key: #{s3_key}")
      
      # Create S3 client
      s3_client = Aws::S3::Client.new(
        region: ENV['AWS_REGION'],
        credentials: Aws::Credentials.new(
          ENV['AWS_ACCESS_KEY_ID'],
          ENV['AWS_SECRET_ACCESS_KEY']
        )
      )
      
      # Generate presigned URL
      presigned_request = Aws::S3::Presigner.new(client: s3_client)
      
      presigned_url = presigned_request.presigned_url(
        :get_object,
        bucket: bucket_name,
        key: s3_key,
        expires_in: expires_in,
        response_content_type: 'audio/mpeg',
        response_content_disposition: "attachment; filename=\"#{filename}\""
      )
      
      Rails.logger.info("Successfully generated presigned URL")
      return presigned_url
    rescue StandardError => e
      Rails.logger.error("Presigned URL error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      return nil
    end
  end
  
  def youtube_id
    self[:youtube_id] || extract_youtube_id_from_url
  end
  
  def extract_youtube_id_from_url
    # Extract YouTube ID from URL (including Shorts)
    if url.include?('youtube.com/shorts/')
      # Handle YouTube Shorts URL format
      regex = %r{youtube\.com/shorts/([^"&?/\s]{11})}
      match = regex.match(url)
    else
      # Handle regular YouTube URL format
      regex = %r{(?:youtube\.com/(?:[^/]+/.+/|(?:v|e(?:mbed)?)/|.*[?&]v=)|youtu\.be/)([^"&?/\s]{11})}
      match = regex.match(url)
    end
    match[1] if match
  end
  
  def formatted_duration
    return nil unless duration
    
    minutes = duration / 60
    seconds = duration % 60
    
    format("%02d:%02d", minutes, seconds)
  end
  
  def filename
    safe_title = title.present? ? title.parameterize[0..30] : youtube_id
    "#{safe_title}-#{quality}kbps.mp3"
  end
  
  # Add method to clean up file
  def cleanup_file
    if file_path.present? && File.exist?(file_path)
      begin
        File.delete(file_path)
        update(file_path: nil)
        return true
      rescue => e
        Rails.logger.error("Failed to delete file #{file_path}: #{e.message}")
        return false
      end
    end
    true
  end
  
  private
  
  def extract_youtube_id
    self.youtube_id = extract_youtube_id_from_url
  end
end