# frozen_string_literal: true

class DailyCost < ApplicationRecord
  belongs_to :aws_account
  
  # Validations
  validates :date, presence: true, uniqueness: { scope: :aws_account_id }
  validates :cost_amount, presence: true, numericality: { 
    greater_than_or_equal_to: 0,
    precision: 10,
    scale: 2
  }
  validates :currency, presence: true, inclusion: { in: %w[USD] }
  
  # Scopes
  scope :recent_weeks, ->(weeks = 2) { where(date: weeks.weeks.ago..Date.current) }
  scope :by_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :ordered_by_date, -> { order(:date) }
  
  # Display helpers
  def formatted_cost
    "$#{cost_amount.round(2)}"
  end
  
  def self.total_for_period(start_date, end_date)
    by_date_range(start_date, end_date).sum(:cost_amount)
  end
end