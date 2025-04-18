# lib/tasks/s3_cleanup.rake
namespace :s3 do
  desc "Clean up old files from development S3 bucket"
  task cleanup: :environment do
    next unless Rails.env.development?
    
    s3_client = Aws::S3::Client.new(
      region: ENV['AWS_REGION'],
      credentials: Aws::Credentials.new(
        ENV['AWS_ACCESS_KEY_ID'],
        ENV['AWS_SECRET_ACCESS_KEY']
      )
    )
    
    # List objects older than 1 day
    resp = s3_client.list_objects_v2(
      bucket: ENV['AWS_BUCKET'],
      prefix: 'mp3s/'
    )
    
    objects_to_delete = resp.contents.select do |object|
      object.last_modified < 1.day.ago
    end
    
    if objects_to_delete.any?
      s3_client.delete_objects(
        bucket: ENV['AWS_BUCKET'],
        delete: {
          objects: objects_to_delete.map { |obj| { key: obj.key } }
        }
      )
      puts "Deleted #{objects_to_delete.size} objects from the development S3 bucket"
    else
      puts "No old objects found to delete"
    end
  end
end