import { Controller } from "@hotwired/stimulus"
import { RetellWebClient } from "retell-client-js-sdk"

export default class extends Controller {
  static targets = ["startBtn", "stopBtn", "statusBadge", "transcriptPanel"]

  connect() {
    this.client = new RetellWebClient()
    this.chatId = null
    this.transcript = []

    this.client.on("call_started", () => this.#setStatus("In call", "success"))
    this.client.on("call_ended",   () => this.#onCallEnded())
    this.client.on("agent_start_talking", () => this.#setStatus("Agent speaking…", "primary"))
    this.client.on("agent_stop_talking",  () => this.#setStatus("In call", "success"))
    this.client.on("update", (update) => this.#onUpdate(update))
    this.client.on("error",  (err)    => this.#setStatus(`Error: ${err.message}`, "danger"))
  }

  async startCall() {
    this.#setStatus("Connecting…", "warning")
    this.startBtnTarget.disabled = true
    this.transcript = []
    this.transcriptPanelTarget.innerHTML = ""

    try {
      const res  = await fetch("/retell/web_call", { method: "POST", headers: { "Content-Type": "application/json" } })
      const data = await res.json()

      if (!res.ok) throw new Error(data.error || "Failed to create call")

      this.chatId = data.chat_id
      await this.client.startCall({ accessToken: data.access_token })

      this.stopBtnTarget.disabled = false
    } catch (err) {
      this.#setStatus(`Error: ${err.message}`, "danger")
      this.startBtnTarget.disabled = false
    }
  }

  stopCall() {
    this.client.stopCall()
    this.stopBtnTarget.disabled = true
    this.startBtnTarget.disabled = false
  }

  // private

  #onUpdate(update) {
    if (!update.transcript) return
    this.transcript = update.transcript
    this.transcriptPanelTarget.innerHTML = update.transcript
      .map(t => `<div class="mb-1"><strong class="${t.role === 'agent' ? 'text-primary' : 'text-dark'}">${t.role === 'agent' ? 'Agent' : 'You'}:</strong> ${t.content}</div>`)
      .join("")
    this.transcriptPanelTarget.scrollTop = this.transcriptPanelTarget.scrollHeight
  }

  async #onCallEnded() {
    this.#setStatus("Saving…", "secondary")
    if (this.chatId && this.transcript.length > 0) {
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

  #setStatus(text, color) {
    this.statusBadgeTarget.textContent = text
    this.statusBadgeTarget.className   = `badge bg-${color} ms-2`
  }
}
