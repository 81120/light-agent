(() => {
  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute("content")

  const Hooks = {
    ChatComposerShortcut: {
      mounted() {
        this.onKeyDown = event => {
          if (event.key !== "Enter") return
          if (!event.metaKey && !event.ctrlKey) return

          event.preventDefault()

          const form = this.el.form || document.getElementById("session-chat-form")
          if (!form) return

          if (typeof form.requestSubmit === "function") {
            form.requestSubmit()
            return
          }

          form.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}))
        }

        this.clearInput = () => {
          this.el.value = ""
          this.el.dispatchEvent(new Event("input", {bubbles: true}))
        }

        this.chatClearRef = this.handleEvent("chat_clear_input", this.clearInput)
        this.el.addEventListener("keydown", this.onKeyDown)
      },

      destroyed() {
        this.el.removeEventListener("keydown", this.onKeyDown)
        if (this.chatClearRef) this.removeHandleEvent(this.chatClearRef)
      }
    },

    CopyHistoryItem: {
      mounted() {
        this.originalLabel = this.el.textContent

        this.onClick = async () => {
          const contentEl = this.el.closest(".history-main")?.querySelector(".history-content")
          const content = contentEl?.textContent ?? ""
          if (!content.trim()) return

          const copied = await this.copyText(content)
          if (!copied) return

          this.el.textContent = "Copied"
          this.el.classList.add("copied")

          clearTimeout(this.resetTimer)
          this.resetTimer = setTimeout(() => {
            this.el.textContent = this.originalLabel
            this.el.classList.remove("copied")
          }, 1200)
        }

        this.el.addEventListener("click", this.onClick)
      },

      destroyed() {
        this.el.removeEventListener("click", this.onClick)
        clearTimeout(this.resetTimer)
      },

      async copyText(text) {
        try {
          if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(text)
            return true
          }
        } catch (_error) {}

        const temp = document.createElement("textarea")
        temp.value = text
        temp.setAttribute("readonly", "")
        temp.style.position = "fixed"
        temp.style.opacity = "0"
        document.body.appendChild(temp)
        temp.select()
        const ok = document.execCommand("copy")
        document.body.removeChild(temp)
        return ok
      }
    }
  }

  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: {_csrf_token: csrfToken},
    hooks: Hooks
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
})()
