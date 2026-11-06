// LiveView needs only its client and Phoenix's socket, both served from the deps (no build step).
window.addEventListener("DOMContentLoaded", () => {
  const token = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: {_csrf_token: token}
  })
  liveSocket.connect()
  window.liveSocket = liveSocket
})
