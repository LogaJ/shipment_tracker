class CreateEvents < ActiveRecord::Migration
  def change
    create_table :events do |t|
      t.json :details

      t.timestamps null: false
    end
  end
end
