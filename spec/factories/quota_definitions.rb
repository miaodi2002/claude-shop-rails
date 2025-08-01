# frozen_string_literal: true

FactoryBot.define do
  factory :quota_definition do
    sequence(:quota_code) { |n| "QUOTA_#{n}" }
    claude_model_name { 'claude-3-sonnet V1' }
    quota_type { 'tokens_per_minute' }
    quota_name { 'Claude 3 Sonnet Token Rate Limit' }
    call_type { 'sync' }
    default_value { 100 }
    is_active { true }

    trait :high_level do
      quota_level { 'high' }
      default_value { 1000 }
    end

    trait :low_level do
      quota_level { 'low' }
      default_value { 10 }
    end

    trait :haiku do
      claude_model_name { 'claude-3-haiku V1' }
      quota_name { 'Claude 3 Haiku Token Rate Limit' }
    end

    trait :sonnet do
      claude_model_name { 'claude-3-sonnet V1' }
      quota_name { 'Claude 3 Sonnet Token Rate Limit' }
    end

    trait :inactive do
      is_active { false }
    end
  end
end