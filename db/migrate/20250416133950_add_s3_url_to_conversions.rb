class AddS3UrlToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :s3_url, :string
  end
end
