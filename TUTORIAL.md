# Building a Voice AI App with Retell AI + Rails

This tutorial walks you through **exactly how this app works**, following the path of a real user interaction from the moment they click "Start Call" to the moment their transcript is saved in the database.

---

## How the App Works — The Big Picture

```
User clicks "Start Call"
        │
        ▼
[Browser] Stimulus controller sends POST /retell/web_call
        │
        ▼
[Rails] RetellController creates a Chat in the DB,
        then calls the Retell API to register a new call
        │
        ▼
[Retell API] Returns an access_token (a one-time key for this call)
        │
        ▼
[Browser] The Retell JS SDK opens a WebRTC audio connection
          using that token — microphone and speaker are now live
        │
        ▼
[During call] SDK fires `update` events with the live transcript
              Stimulus controller appends each line to the screen
        │
        ▼
User clicks "Stop Call"
        │
        ▼
[Browser] SDK fires `call_ended` event
          Stimulus controller POSTs the full transcript to /retell/transcript
        │
        ▼
[Rails] Saves each transcript line as a Message in the DB
```

---

## Part 1 — Setup

### 1.1 Create a Retell account

Go to [retellai.com](https://retellai.com) and sign up. Once inside the dashboard:

- Copy your **API Key** from the dashboard settings.

### 1.2 Create a Voice Agent

In your retellai dashboard, create a new Voice Agent. Select single/multi prompt, blank.
When created, you will find the Agent ID and Engine ID on the top of the page.

Create (or edit) a `.env` file at the root of the project:

```
RETELL_API_KEY=key_xxxxxxxxxxxxxxxxxxxx
RETELL_AGENT_ID=agent_xxxx   # we'll fill this in after step 1.3
RETELL_ENGINE_ID=llm_xxxx
```

The `dotenv-rails` gem (already in the Gemfile) automatically loads this file in development.

## Part 2 — The Database

We extend the existing tables with two new columns.

### 2.1 Generate and run the migrations

```bash
rails generate migration AddRetellCallIdToChats retell_call_id:string
rails generate migration AddRoleToMessages role:string
rails db:migrate
```

### 2.2 What each column does

| Table | Column | Purpose |
|---|---|---|
| `chats` | `retell_call_id` | Stores Retell's internal call ID so you can look up calls on the Retell dashboard |
| `messages` | `role` | Either `"agent"` or `"user"` — lets you display who said what |

---

## Part 3 — The Backend (Rails)

### 3.1 Routes

Add the two API endpoints for the frontend to call:

**`config/routes.rb`**
```ruby
Rails.application.routes.draw do
  # ... existing routes ...

  namespace :retell do
    post "web_call"    # Step 1: browser asks Rails to create a call session
    post "transcript"  # Step 2: browser sends the finished transcript to be saved
  end

  root to: "pages#home"
end
```

`namespace :retell` means the URLs are `/retell/web_call` and `/retell/transcript`, handled by `RetellController`.

### 3.2 The Controller

This is the brain of the backend. It has exactly two jobs.

**`app/controllers/retell_controller.rb`**
```ruby
require "net/http"
require "json"

class RetellController < ApplicationController
  # We skip CSRF protection because these endpoints are called via fetch() in JS.
  # In a real app with authentication, you'd use a token instead.
  skip_before_action :verify_authenticity_token, only: [:web_call, :transcript]

  # POST /retell/web_call
  # Called when the user clicks "Start Call"
  def web_call
    agent_id = ENV["RETELL_AGENT_ID"]
    api_key  = ENV["RETELL_API_KEY"]

    if agent_id.blank? || api_key.blank?
      render json: { error: "Missing RETELL_API_KEY or RETELL_AGENT_ID in .env" }, status: :service_unavailable
      return
    end

    # 1. Create a Chat record in our own DB to track this conversation
    chat = Chat.create!(name: "Call – #{Time.current.strftime('%b %d %H:%M')}")

    # 2. Ask the Retell API to register a new web call session
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
      chat.destroy  # clean up if Retell rejected the request
      render json: { error: body["message"] || "Retell API error" }, status: :bad_gateway
      return
    end

    # 3. Save Retell's call ID onto our Chat
    chat.update!(retell_call_id: body["call_id"])

    # 4. Return the access_token + our chat ID to the browser
    #    The browser needs the token to join the call room via WebRTC
    render json: { access_token: body["access_token"], chat_id: chat.id }
  end

  # POST /retell/transcript
  # Called when the call ends — receives the full conversation and saves it
  def transcript
    chat = Chat.find(params[:chat_id])
    messages = params[:transcript].map do |t|
      {
        chat_id: chat.id,
        role: t[:role],
        content: t[:content],
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    Message.insert_all(messages) if messages.any?
    render json: { ok: true }
  end
end
```

**Key concepts to understand here:**

- `skip_before_action :verify_authenticity_token` — Rails normally protects forms from cross-site attacks using a hidden token. Since our JavaScript `fetch()` calls don't send that token, we disable the check here. Fine for a demo; in production you'd handle this properly with authentication.
- `Net::HTTP` — Ruby's built-in HTTP client. We use it to make server-to-server calls to the Retell API. Your API key stays on the server and is never exposed to the browser.
- `Message.insert_all` — A single SQL `INSERT` for all messages at once, much faster than calling `.save` in a loop.

---

## Part 4 — The Frontend

### 4.1 Load the Retell JavaScript SDK

This app uses **importmap** (no webpack/esbuild). We load the SDK directly from the `esm.sh` CDN, which converts any npm package into a browser-compatible ES module.

**`config/importmap.rb`**
```ruby
pin "retell-client-js-sdk", to: "https://esm.sh/retell-client-js-sdk"
```

That single line is the equivalent of `npm install retell-client-js-sdk` for importmap projects.

### 4.2 The Stimulus Controller

Stimulus is the JavaScript framework this app uses. A **controller** is a JavaScript class that attaches to a DOM element and reacts to events.

**`app/javascript/controllers/voice_controller.js`**
```javascript
import { Controller } from "@hotwired/stimulus"
import { RetellWebClient } from "retell-client-js-sdk"

export default class extends Controller {
  // "targets" are HTML elements this controller can find and manipulate
  static targets = ["startBtn", "stopBtn", "statusBadge", "transcriptPanel"]

  // connect() runs automatically when the controller's element appears on the page
  connect() {
    this.client = new RetellWebClient()  // the Retell SDK instance
    this.chatId = null                   // will hold the DB id of the current call
    this.transcript = []                 // local copy of the conversation so far

    // Register event listeners on the Retell client
    this.client.on("call_started",        () => this.#setStatus("In call", "success"))
    this.client.on("call_ended",          () => this.#onCallEnded())
    this.client.on("agent_start_talking", () => this.#setStatus("Agent speaking…", "primary"))
    this.client.on("agent_stop_talking",  () => this.#setStatus("In call", "success"))
    this.client.on("update",     (update) => this.#onUpdate(update))
    this.client.on("error",      (err)    => this.#setStatus(`Error: ${err.message}`, "danger"))
  }

  // Called when the user clicks "Start Call"
  async startCall() {
    this.#setStatus("Connecting…", "warning")
    this.startBtnTarget.disabled = true
    this.transcript = []
    this.transcriptPanelTarget.innerHTML = ""

    try {
      // 1. Ask our Rails backend to create a call session and give us an access_token
      const res  = await fetch("/retell/web_call", {
        method: "POST",
        headers: { "Content-Type": "application/json" }
      })
      const data = await res.json()

      if (!res.ok) throw new Error(data.error || "Failed to create call")

      // 2. Remember which Chat in the DB this call belongs to
      this.chatId = data.chat_id

      // 3. Use the token to start the actual WebRTC audio call
      await this.client.startCall({ accessToken: data.access_token })

      this.stopBtnTarget.disabled = false
    } catch (err) {
      this.#setStatus(`Error: ${err.message}`, "danger")
      this.startBtnTarget.disabled = false
    }
  }

  // Called when the user clicks "Stop Call"
  stopCall() {
    this.client.stopCall()  // triggers "call_ended" event asynchronously
    this.stopBtnTarget.disabled  = true
    this.startBtnTarget.disabled = false
  }

  // --- Private methods (the # prefix makes them private in modern JS) ---

  // Receives live transcript updates from the Retell SDK
  #onUpdate(update) {
    if (!update.transcript) return
    this.transcript = update.transcript  // keep a local copy for saving later

    // Re-render the transcript panel
    this.transcriptPanelTarget.innerHTML = update.transcript
      .map(t => `
        <div class="mb-1">
          <strong class="${t.role === 'agent' ? 'text-primary' : 'text-dark'}">
            ${t.role === 'agent' ? 'Agent' : 'You'}:
          </strong>
          ${t.content}
        </div>`)
      .join("")

    // Auto-scroll to the bottom as new lines appear
    this.transcriptPanelTarget.scrollTop = this.transcriptPanelTarget.scrollHeight
  }

  // Runs after the call has ended
  async #onCallEnded() {
    this.#setStatus("Saving…", "secondary")

    if (this.chatId && this.transcript.length > 0) {
      // Send the full transcript to Rails to save in the DB
      await fetch("/retell/transcript", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: this.chatId, transcript: this.transcript })
      })
    }

    this.#setStatus("Call ended — saved", "secondary")
    this.startBtnTarget.disabled = false
    this.stopBtnTarget.disabled  = true
  }

  // Update the status badge text and Bootstrap colour
  #setStatus(text, color) {
    this.statusBadgeTarget.textContent = text
    this.statusBadgeTarget.className   = `badge bg-${color} ms-2`
  }
}
```

**Key concepts:**

- `static targets` — declares which HTML elements this controller needs to find. Stimulus wires them up automatically via `data-voice-target="..."` attributes in the HTML.
- `connect()` — like a constructor; called once when the page loads. Good place to create the SDK instance and attach event listeners.
- `async/await` — modern JavaScript for working with asynchronous operations (network requests) without callback hell.
- Private methods (`#name`) — JavaScript's built-in way to keep helper methods internal to the class.

### 4.3 The Home Page View

**`app/views/pages/home.html.erb`**
```erb
<div class="container py-5" data-controller="voice">
  <div class="row justify-content-center">
    <div class="col-lg-7">

      <h1 class="mb-1">Voice Assistant</h1>
      <p class="text-muted mb-4">Click <strong>Start Call</strong> and speak.</p>

      <%# Controls %>
      <div class="d-flex align-items-center gap-2 mb-4">
        <button class="btn btn-success"
                data-voice-target="startBtn"
                data-action="click->voice#startCall">
          Start Call
        </button>
        <button class="btn btn-danger"
                data-voice-target="stopBtn"
                data-action="click->voice#stopCall"
                disabled>
          Stop Call
        </button>
        <span class="badge bg-secondary ms-2" data-voice-target="statusBadge">Idle</span>
      </div>

      <%# Transcript panel %>
      <div class="card">
        <div class="card-header">
          <span class="fw-semibold">Live Transcript</span>
        </div>
        <div class="card-body"
             data-voice-target="transcriptPanel"
             style="min-height: 280px; max-height: 420px; overflow-y: auto;">
          <p class="text-muted fst-italic">Transcript will appear here once the call starts…</p>
        </div>
      </div>

      <%# Past conversations link %>
      <div class="mt-3 text-end">
        <%= link_to "View past conversations →", chats_path, class: "text-decoration-none text-muted small" %>
      </div>

    </div>
  </div>
</div>
```

**How Stimulus data attributes work:**

| Attribute | What it does |
|---|---|
| `data-controller="voice"` | Tells Stimulus to attach `voice_controller.js` to this element |
| `data-voice-target="startBtn"` | Makes this element accessible as `this.startBtnTarget` in the controller |
| `data-action="click->voice#startCall"` | Calls `startCall()` on the `voice` controller when clicked |

---

## Part 5 — Putting It All Together

### Running the app for the first time

```bash
# 1. Add your API key to .env.

# 2. Make sure migrations are up to date
rails db:migrate

# 3. Start the server
rails s

# 4. Visit http://localhost:3000
# Click "Start Call", allow mic access, start speaking!
```

### Verifying that transcripts are saved

After a call, check the database:

```bash
rails console
```

```ruby
# See the latest call session
Chat.last
# => #<Chat id: 1, name: "Call – Jun 09 14:32", retell_call_id: "call_abc123", ...>

# See all messages from that call
Chat.last.messages.pluck(:role, :content)
# => [["agent", "Hello! How can I help you today?"], ["user", "I wanted to ask about..."]]
```

---

## Part 6 — The Full Request-Response Flow (annotated)

Here is every step in sequence when a user clicks "Start Call":

```
1. User clicks the "Start Call" button
   └─ HTML: data-action="click->voice#startCall"
   └─ Stimulus calls startCall() in voice_controller.js

2. voice_controller.js sends:
   POST /retell/web_call
   (no body needed)

3. Rails routes this to RetellController#web_call
   └─ Creates: Chat(name: "Call – Jun 09 14:32")
   └─ Sends to Retell API:
      POST https://api.retellai.com/v2/create-web-call
      { agent_id: "agent_abc123" }
   └─ Retell responds:
      { call_id: "call_xyz", access_token: "tok_..." }
   └─ Saves call_id on the Chat record
   └─ Responds to browser:
      { access_token: "tok_...", chat_id: 1 }

4. voice_controller.js receives { access_token, chat_id }
   └─ Saves chat_id locally (needed later to save the transcript)
   └─ Calls: retellWebClient.startCall({ accessToken: "tok_..." })
   └─ The SDK opens a WebRTC connection to Retell's servers
   └─ Your microphone and speaker are now live

5. During the call:
   └─ Retell SDK fires "update" events with growing transcript
   └─ #onUpdate() re-renders the transcript panel on every update

6. User clicks "Stop Call"
   └─ retellWebClient.stopCall() is called
   └─ SDK fires "call_ended" event

7. #onCallEnded() runs:
   └─ Sends to our Rails backend:
      POST /retell/transcript
      { chat_id: 1, transcript: [{role: "agent", content: "Hello!"}, ...] }
   └─ Rails saves each line as a Message record
   └─ Status badge updates to "Call ended — saved"
```

---

## Common Issues

| Problem | Fix |
|---|---|
| "Missing RETELL_API_KEY" error | Check your `.env` file has the key, restart the server |
| Mic not working | Browser needs to be on `localhost` or `https` for WebRTC |
| "Failed to create call" | Check that `RETELL_AGENT_ID` is set correctly in `.env` |
| Transcript not saving | Open the browser console and Rails logs for error messages |
| `llm_placeholder` error from Retell | Log into the Retell dashboard and create a real LLM, then update the rake task with the real `llm_id` |
