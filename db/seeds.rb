# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
require 'json'

unless ENV.fetch("ACTIVE_RECORD_ENCRYPTION", nil)
  raise StandardError, <<~HELP
    This application will not work without the 'ACTIVE_RECORD_ENCRYPTION' variable set.
    See https://github.com/nickthecook/archyve?tab=readme-ov-file#getting-started for setup instructions.
  HELP
end

default_user = ENV.fetch("USERNAME") { "admin@archyve.io" }
default_password = ENV.fetch("PASSWORD") { "password" }
model_endpoint = ENV.fetch("CHAT_ENDPOINT") { "http://localhost:11434" }

puts "Seeding database with USERNAME '#{default_user}', PASSWORD '********', and endpoint '#{model_endpoint}'..."

User.find_or_create_by!(email: default_user)  do |user|
  user.password = default_password
  user.admin = true
end

default_client = Client.find_by(name: "default")
default_client_id = ENV["DEFAULT_CLIENT_ID"]
default_api_key = ENV["DEFAULT_API_KEY"]

if default_client_id.present? && default_api_key.present?
  if default_client.nil?
    puts("Creating default client based on DEFAULT_CLIENT_ID and DEFAULT_API_KEY...")
    default_client = Client.create!(
      name: "default",
      client_id: default_client_id,
      api_key: default_api_key,
      user: User.first
    )
  elsif default_client.client_id != default_client_id || default_client.api_key != default_api_key
    Rails.info.logger("Updating default client ID and API key based on DEFAULT_CLIENT_ID and DEFAULT_API_KEY...")
    default_client.update!(client_id: default_client_id, api_key: default_api_key)
  else
    puts("Default client already exists with correct client ID and API key.")
  end
else
  puts("DEFAULT_CLIENT_ID and DEFAULT_API_KEY not set; not creating or updating default client.")
end

devel_model_servers = [
  {
    name: "localhost",
    provider: "ollama",
  }
]

devel_model_configs = [
  {
    name: "mistral:instruct",
    model_server: "localhost",
    model: "mistral:instruct",
    temperature: 0.1,
  },
  {
    name: "gemma:7b",
    model_server: "localhost",
    model: "gemma:7b",
    temperature: 0.2,
  },
  {
    name: "all-minilm",
    model_server: "localhost",
    model: "all-minilm",
    embedding: true,
  },
  {
    name: "nomic-embed-text",
    model_server: "localhost",
    model: "nomic-embed-text",
    embedding: true,
  }
]

provisioned_model_servers = JSON.parse(ENV.fetch("PROVISIONED_MODEL_SERVERS") {
  Rails.env == "development" ? JSON.generate(devel_model_servers) : '[]'
})

provisioned_model_configs = JSON.parse(ENV.fetch("PROVISIONED_MODEL_CONFIGS") {
  Rails.env == "development" ? JSON.generate(devel_model_configs) : '[]'
})

provisioned_model_servers.each do |config|
  ModelServer.find_or_create_by!(name: config["name"]) do |ms|
    puts "establishing model server for `#{config["name"]}` ..."
    
    ms.url = config.fetch("url", model_endpoint)
    ms.provider = config.fetch("provider")
    ms.default = config.fetch("default", false)
  end
end

provisioned_model_configs.each do |config|
  server = ModelServer.find_by(name: config.fetch("model_server", "localhost"))

  ModelConfig.find_or_create_by!(name: config["name"], model_server: server) do |mc|
    puts "establishing model configuration for `#{config["name"]}` ..."

    mc.model = config.fetch("model", config["name"])
    mc.temperature = config.fetch("temperature", nil)
    mc.embedding = config.fetch("embedding", false)
  end
end

if Rails.env == "development"
  if default_client
    puts <<~TEXT
      
      To authenticate with the default API client, set these headers:

      Authorization: Bearer #{default_client.api_key}
      X-Client-Id: #{default_client.client_id}

      E.g.:

      curl -v localhost:3300/v1/collections \\
        -H "Accept: application/json" \\
        -H "Authorization: Bearer #{default_client.api_key}" \\
        -H "X-Client-Id: #{default_client.client_id}"
    TEXT
  end
end
