FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "key_#{n}" }
    sequence(:value) { |n| "value_#{n}" }
    user { nil }
  end
end
