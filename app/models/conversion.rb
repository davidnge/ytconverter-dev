class Conversion < ApplicationRecord
  validates :url, presence: true
  validates :quality, inclusion: { in: %w[128 192 320] }
  
  # Add this line to ensure status is set
  before_create :set_default_status
  
  # Status options: pending, processing, completed, failed
  
  def youtube_id
    # Extract YouTube ID from URL
    regex = %r{(?:youtube\.com/(?:[^/]+/.+/|(?:v|e(?:mbed)?)/|.*[?&]v=)|youtu\.be/)([^"&?/\s]{11})}
    match = regex.match(url)
    match[1] if match
  end
  
  def formatted_duration
    return nil unless duration
    
    minutes = duration / 60
    seconds = duration % 60
    
    format("%02d:%02d", minutes, seconds)
  end
  
  def filename
    "#{title.parameterize[0..30]}-#{quality}kbps.mp3"
  end
  
  private
  
  def set_default_status
    self.status ||= 'pending'
  end
end