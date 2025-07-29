class AddWarningStatusToQuotas < ActiveRecord::Migration[8.0]
  def up
    # The warning status (value 3) is already added to the enum in the model
    # This migration is a placeholder since enum changes don't require schema changes
    # when using integer enums, but it documents the change
    
    # If any existing records need to be updated, do it here
    say "Adding warning status support to quotas - enum updated in model"
  end
  
  def down
    # Revert any warning status records back to failed if rolling back
    execute "UPDATE quotas SET update_status = 1 WHERE update_status = 3"
  end
end
