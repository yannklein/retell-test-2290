require "net/http"
require "json"

namespace :retell do
  desc "Create a Retell AI agent and print its ID. Run once, then add RETELL_AGENT_ID to .env"
  task create_agent: :environment do
    api_key = ENV["RETELL_API_KEY"]
    abort "Missing RETELL_API_KEY in .env" if api_key.blank?

    uri = URI("https://api.retellai.com/create-agent")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = {
      agent_name: "Rails Voice Assistant",
      voice_id: "11labs-Adrian",
      response_engine: {
        type: "retell-llm",
        llm_id: "llm_placeholder"
      },
      language: "en-US"
    }.to_json

    response = http.request(request)
    body = JSON.parse(response.body)

    if response.code == "201"
      puts ""
      puts "Agent created successfully!"
      puts "Add this to your .env file:"
      puts ""
      puts "  RETELL_AGENT_ID=#{body['agent_id']}"
      puts ""
    else
      puts "Failed to create agent (HTTP #{response.code})"
      puts body.inspect
    end
  end
end
