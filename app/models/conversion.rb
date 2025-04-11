# app/models/conversion.rb
class Conversion < ApplicationRecord
  validates :url, presence: true, format: { 
    with: %r{\A(https?://)?(www\.)?(youtube\.com/((watch\?v=)|shorts/)|youtu\.be/)}, 
    message: "must be a valid YouTube URL" 
  }
  validates :quality, inclusion: { in: %w[128 192 320] }
  
  # Add a scope for finding old conversions
  scope :old, ->(time = 24.hours.ago) { where("created_at < ?", time) }
  
  # Status options: pending, processing, completed, failed
  
  def youtube_id
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
end