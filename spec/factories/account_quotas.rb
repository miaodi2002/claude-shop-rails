# frozen_string_literal: true

FactoryBot.define do
  factory :account_quota do
    association :aws_account
    association :quota_definition
    current_quota { 100.0 }
    quota_level { 'unknown' }
    is_adjustable { false }
    sync_status { 'pending' }

    trait :high_level do
      quota_level { 'high' }
      current_quota { 1000.0 }
    end

    trait :low_level do
      quota_level { 'low' }
      current_quota { 10.0 }
    end

    trait :synced do
      sync_status { 'completed' }
      last_sync_at { 1.hour.ago }
    end

    trait :sync_failed do
      sync_status { 'failed' }
      sync_error { 'Connection timeout' }
      last_sync_at { 1.hour.ago }
    end

    trait :adjustable do
      is_adjustable { true }
    end

    trait :zero_quota do
      current_quota { 0.0 }
    end
  end
end