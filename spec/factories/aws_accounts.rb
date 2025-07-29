# frozen_string_literal: true

FactoryBot.define do
  factory :aws_account do
    sequence(:name) { |n| "AWS Account #{n}" }
    sequence(:account_id) { |n| "12345678#{n.to_s.rjust(4, '0')}" }
    access_key { 'AKIAIOSFODNN7EXAMPLE' }
    secret_key { 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY123456789012' }
    region { 'us-east-1' }
    status { :active }
    connection_status { :unknown }
    description { 'Test AWS account for development' }
    tags { ['test', 'development'] }

    trait :inactive do
      status { :inactive }
    end

    trait :sold_out do
      status { :sold_out }
    end

    trait :with_high_quota do
      after(:create) do |aws_account|
        quota_definition = create(:quota_definition, quota_level: 'high')
        create(:account_quota, 
               aws_account: aws_account, 
               quota_definition: quota_definition,
               current_quota: 1000)
      end
    end

    trait :with_low_quota do
      after(:create) do |aws_account|
        quota_definition = create(:quota_definition, quota_level: 'low')
        create(:account_quota, 
               aws_account: aws_account, 
               quota_definition: quota_definition,
               current_quota: 10)
      end
    end

    trait :with_quotas do
      after(:create) do |aws_account|
        high_quota_def = create(:quota_definition, quota_level: 'high', claude_model_name: 'claude-3-sonnet')
        low_quota_def = create(:quota_definition, quota_level: 'low', claude_model_name: 'claude-3-haiku')
        
        create(:account_quota, 
               aws_account: aws_account, 
               quota_definition: high_quota_def,
               current_quota: 1000)
        
        create(:account_quota, 
               aws_account: aws_account, 
               quota_definition: low_quota_def,
               current_quota: 100)
      end
    end

    trait :connected do
      connection_status { :connected }
      last_connection_test_at { 1.hour.ago }
    end

    trait :connection_error do
      connection_status { :error }
      connection_error_message { 'Invalid credentials' }
      last_connection_test_at { 1.hour.ago }
    end

    trait :deleted do
      deleted_at { 1.day.ago }
      status { :inactive }
    end
  end
end