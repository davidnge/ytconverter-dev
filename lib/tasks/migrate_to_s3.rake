# lib/tasks/migrate_to_s3.rake

namespace :conversions do
  desc "Migrate existing completed conversions to S3"
  task migrate_to_s3: :environment do
    puts "Starting migration of completed conversions to S3..."
    count = 0
    
    Conversion.where(status: 'completed').where(s3_url: nil).find_each do |conversion|
      if conversion.file_path.present? && File.exist?(conversion.file_path)
        if conversion.upload_to_s3
          count += 1
          puts "Migrated conversion ##{conversion.id} to S3"
        else
          puts "Failed to migrate conversion ##{conversion.id}"
        end
      else
        puts "Skipping conversion ##{conversion.id} - file not found at #{conversion.file_path}"
      end
    end
    
    puts "Completed migration. #{count} files migrated to S3."
  end
end