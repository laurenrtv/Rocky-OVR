class ChangeDjLimits < ActiveRecord::Migration
  def change
    change_column :delayed_jobs, :handler, :text, limit: 16.megabytes - 1
    change_column :delayed_jobs, :last_error, :text, limit: 16.megabytes - 1    
  end
end
