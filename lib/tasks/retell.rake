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
        llm_id: ENV["RETELL_ENGINE_ID"]
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
    # RETELL_AGENT_ID=XXXXXX
  end
  desc "Create a Retell AI enging and print its ID"
  task create_engine: :environment do
    api_key = ENV["RETELL_API_KEY"]

    url = URI("https://api.retellai.com/create-retell-llm")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = "{}"
    # request.body = "{\n  \"model\": \"gpt-4.1\",\n  \"s2s_model\": \"gpt-realtime-1.5\",\n  \"model_temperature\": 0,\n  \"model_high_priority\": true,\n  \"tool_call_strict_mode\": true,\n  \"knowledge_base_ids\": [\n    \"<string>\"\n  ],\n  \"kb_config\": {\n    \"top_k\": 3,\n    \"filter_score\": 0.6\n  },\n  \"begin_after_user_silence_ms\": 2000,\n  \"begin_message\": \"Hey I am a virtual assistant calling from Retell Hospital.\",\n  \"general_prompt\": \"You are ...\",\n  \"general_tools\": [\n    {\n      \"type\": \"end_call\",\n      \"name\": \"end_call\",\n      \"description\": \"End the call with user.\"\n    }\n  ],\n  \"states\": [\n    {\n      \"name\": \"information_collection\",\n      \"state_prompt\": \"You will follow the steps below to collect information...\",\n      \"edges\": [\n        {\n          \"destination_state_name\": \"appointment_booking\",\n          \"description\": \"Transition to book an appointment.\"\n        }\n      ],\n      \"tools\": [\n        {\n          \"type\": \"transfer_call\",\n          \"name\": \"transfer_to_support\",\n          \"description\": \"Transfer to the support team.\",\n          \"transfer_destination\": {\n            \"type\": \"predefined\",\n            \"number\": \"16175551212\",\n            \"ignore_e164_validation\": false\n          },\n          \"transfer_option\": {\n            \"type\": \"cold_transfer\",\n            \"show_transferee_as_caller\": false\n          }\n        }\n      ]\n    },\n    {\n      \"name\": \"appointment_booking\",\n      \"state_prompt\": \"You will follow the steps below to book an appointment...\",\n      \"tools\": [\n        {\n          \"type\": \"book_appointment_cal\",\n          \"name\": \"book_appointment\",\n          \"description\": \"Book an annual check up.\",\n          \"cal_api_key\": \"cal_live_xxxxxxxxxxxx\",\n          \"event_type_id\": 60444,\n          \"timezone\": \"America/Los_Angeles\"\n        }\n      ]\n    }\n  ],\n  \"starting_state\": \"information_collection\",\n  \"default_dynamic_variables\": {\n    \"customer_name\": \"John Doe\"\n  },\n  \"mcps\": [\n    {\n      \"name\": \"<string>\",\n      \"url\": \"<string>\",\n      \"headers\": {\n        \"Authorization\": \"Bearer 1234567890\"\n      },\n      \"query_params\": {\n        \"index\": \"1\",\n        \"key\": \"value\"\n      },\n      \"timeout_ms\": 123\n    }\n  ]\n}"

    response = http.request(request)
    puts response.read_body
    # {"llm_id":"XXXXXX","version":0,"model":"gpt-4.1","start_speaker":"agent","kb_config":{"top_k":3,"filter_score":0.6},"last_modification_timestamp":1781012424556,"is_published":false}
  end
end
