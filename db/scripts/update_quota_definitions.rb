#!/usr/bin/env ruby
# Update quota definitions with correct AWS Console default values

# Load Rails environment
require_relative '../config/environment' unless defined?(Rails)

puts '=' * 60
puts 'Updating QuotaDefinition default values to match AWS Console'
puts '=' * 60

# Correct default values from AWS Console (from service file)
correct_definitions = [
  { quota_code: 'L-254CACF4', claude_model_name: 'Claude 3.5 Sonnet', model_version: 'V1', quota_type: 'requests_per_minute', quota_name: 'On-demand model inference requests per minute for Anthropic Claude 3.5 Sonnet', call_type: 'On-demand', default_value: 50 },
  { quota_code: 'L-A50569E5', claude_model_name: 'Claude 3.5 Sonnet', model_version: 'V1', quota_type: 'tokens_per_minute', quota_name: 'On-demand model inference tokens per minute for Anthropic Claude 3.5 Sonnet', call_type: 'On-demand', default_value: 400000 },
  { quota_code: 'L-79E773B3', claude_model_name: 'Claude 3.5 Sonnet', model_version: 'V2', quota_type: 'requests_per_minute', quota_name: 'On-demand model inference requests per minute for Anthropic Claude 3.5 Sonnet V2', call_type: 'On-demand', default_value: 50 },
  { quota_code: 'L-AD41C330', claude_model_name: 'Claude 3.5 Sonnet', model_version: 'V2', quota_type: 'tokens_per_minute', quota_name: 'On-demand model inference tokens per minute for Anthropic Claude 3.5 Sonnet V2', call_type: 'On-demand', default_value: 400000 },
  { quota_code: 'L-3D8CC480', claude_model_name: 'Claude 3.7 Sonnet', model_version: 'V1', quota_type: 'requests_per_minute', quota_name: 'Cross-region model inference requests per minute for Anthropic Claude 3.7 Sonnet V1', call_type: 'Cross-region', default_value: 250 },
  { quota_code: 'L-6E888CC2', claude_model_name: 'Claude 3.7 Sonnet', model_version: 'V1', quota_type: 'tokens_per_minute', quota_name: 'Cross-region model inference tokens per minute for Anthropic Claude 3.7 Sonnet V1', call_type: 'Cross-region', default_value: 1000000 },
  { quota_code: 'L-9EB71894', claude_model_name: 'Claude 3.7 Sonnet', model_version: 'V1', quota_type: 'tokens_per_day', quota_name: 'Model invocation max tokens per day for Anthropic Claude 3.7 Sonnet V1 (doubled for cross-region calls)', call_type: 'Cross-region', default_value: 720000000 },
  { quota_code: 'L-559DCC33', claude_model_name: 'Claude 4 Sonnet', model_version: 'V1', quota_type: 'requests_per_minute', quota_name: 'Cross-region model inference requests per minute for Anthropic Claude Sonnet 4 V1', call_type: 'Cross-region', default_value: 200 },
  { quota_code: 'L-59759B4A', claude_model_name: 'Claude 4 Sonnet', model_version: 'V1', quota_type: 'tokens_per_minute', quota_name: 'Cross-region model inference tokens per minute for Anthropic Claude Sonnet 4 V1', call_type: 'Cross-region', default_value: 200000 },
  { quota_code: 'L-22F701C5', claude_model_name: 'Claude 4 Sonnet', model_version: 'V1', quota_type: 'tokens_per_day', quota_name: 'Model invocation max tokens per day for Anthropic Claude Sonnet 4 V1 (doubled for cross-region calls)', call_type: 'Cross-region', default_value: 144000000 }
]

updated_count = 0
error_count = 0

puts "\nAnalyzing current database state vs correct values..."
puts "-" * 60

correct_definitions.each do |correct_def|
  db_record = QuotaDefinition.find_by(quota_code: correct_def[:quota_code])
  
  if db_record
    old_default = db_record.default_value.to_i
    new_default = correct_def[:default_value]
    
    puts "#{correct_def[:quota_code]}: #{correct_def[:claude_model_name]} #{correct_def[:model_version]} - #{correct_def[:quota_type]}"
    puts "  Current DB: #{old_default}"
    puts "  Should be:  #{new_default}"
    
    if old_default == new_default
      puts "  Status: ✅ Already correct"
    else
      puts "  Status: 🔄 Updating..."
      
      # Update the record with all correct values
      if db_record.update(correct_def)
        puts "  Result: ✅ Successfully updated!"
        updated_count += 1
      else
        puts "  Result: ❌ Failed to update: #{db_record.errors.full_messages.join(', ')}"
        error_count += 1
      end
    end
  else
    puts "#{correct_def[:quota_code]}: New record needed"
    puts "  Status: 🆕 Creating new record..."
    
    # Create new record
    new_record = QuotaDefinition.new(correct_def)
    if new_record.save
      puts "  Result: ✅ Successfully created!"
      updated_count += 1
    else
      puts "  Result: ❌ Failed to create: #{new_record.errors.full_messages.join(', ')}"
      error_count += 1
    end
  end
  
  puts ""
end

puts "=" * 60
puts "Update Summary:"
puts "  Total records processed: #{correct_definitions.count}"
puts "  Successfully updated/created: #{updated_count}"
puts "  Errors: #{error_count}"
puts "=" * 60

if error_count == 0
  puts "🎉 All quota definitions have been successfully updated with correct AWS Console values!"
else
  puts "⚠️  Some updates failed. Please check the errors above."
end

puts "\nValidating updated values..."
puts "-" * 30

# Validate all records now have correct values
all_correct = true
correct_definitions.each do |correct_def|
  db_record = QuotaDefinition.find_by(quota_code: correct_def[:quota_code])
  if db_record && db_record.default_value.to_i == correct_def[:default_value]
    puts "✅ #{correct_def[:quota_code]}: #{db_record.default_value.to_i}"
  else
    puts "❌ #{correct_def[:quota_code]}: Expected #{correct_def[:default_value]}, got #{db_record&.default_value&.to_i || 'nil'}"
    all_correct = false
  end
end

puts "\n" + "=" * 60
if all_correct
  puts "🎉 All quota definitions are now correct!"
else
  puts "⚠️  Some quota definitions still have incorrect values."
end
puts "=" * 60