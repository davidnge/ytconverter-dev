class CreateConversions < ActiveRecord::Migration[8.0]
  def change
    create_table :conversions do |t|
      t.string :url
      t.string :title
      t.integer :duration
      t.string :status
      t.string :quality
      t.string :file_path
      t.string :error_message

      t.timestamps
    end
  end
end
