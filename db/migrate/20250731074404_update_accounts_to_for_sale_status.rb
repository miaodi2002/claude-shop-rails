class UpdateAccountsToForSaleStatus < ActiveRecord::Migration[8.0]
  def up
    # Update some existing active accounts to for_sale status for testing
    AwsAccount.where(status: 'active').limit(3).update_all(status: 4) # for_sale = 4
  end

  def down
    # Revert for_sale accounts back to active
    AwsAccount.where(status: 4).update_all(status: 0) # active = 0
  end
end
