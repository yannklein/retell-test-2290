require "net/http"
require "json"

class RetellController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:web_call, :transcript]

  def web_call
    agent_id = ENV["RETELL_AGENT_ID"]
    api_key  = ENV["RETELL_API_KEY"]

    if agent_id.blank? || api_key.blank?
      render json: { error: "Missing RETELL_API_KEY or RETELL_AGENT_ID in .env" }, status: :service_unavailable
      return
    end

    chat = Chat.create!(name: "Call – #{Time.current.strftime('%b %d %H:%M')}")

    uri = URI("https://api.retellai.com/v2/create-web-call")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = { agent_id: agent_id }.to_json

    response = http.request(request)
    body = JSON.parse(response.body)

    unless response.code == "201"
      chat.destroy
      render json: { error: body["message"] || "Retell API error" }, status: :bad_gateway
      return
    end

    chat.update!(retell_call_id: body["call_id"])

    render json: { access_token: body["access_token"], chat_id: chat.id }
  end

  def transcript
    chat = Chat.find(params[:chat_id])
    messages = params[:transcript].map do |t|
      { chat_id: chat.id, role: t[:role], content: t[:content], created_at: Time.current, updated_at: Time.current }
    end
    Message.insert_all(messages) if messages.any?
    render json: { ok: true }
  end
end
