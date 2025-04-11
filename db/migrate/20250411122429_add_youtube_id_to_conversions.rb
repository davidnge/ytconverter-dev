class AddYoutubeIdToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :youtube_id, :string
    add_index :conversions, :youtube_id
    
    # Update existing records
    reversible do |dir|
      dir.up do
        # This will run the youtube_id extraction method for all existing records
        execute <<-SQL
          UPDATE conversions
          SET youtube_id = CASE
            WHEN url LIKE '%youtube.com/shorts/%' THEN 
              substr(url, instr(url, 'shorts/') + 7, 11)
            WHEN url LIKE '%youtube.com/watch?v=%' THEN 
              substr(url, instr(url, 'watch?v=') + 8, 11)
            WHEN url LIKE '%youtu.be/%' THEN 
              substr(url, instr(url, 'youtu.be/') + 9, 11)
            ELSE NULL
          END
        SQL
      end
    end
  end
end