import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.showError = this.showError.bind(this);

    window.addEventListener("flash:error", this.showError);
  }

  disconnect() {
    window.removeEventListener("flash:error", this.showError);
  }

  showError() {
    const notification = document.createElement("div");

    notification.className = "rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 shadow-sm opacity-100 transition-opacity duration-[2500ms]";

    notification.textContent = event.detail.message;

    this.element.appendChild(notification);

    setTimeout(() => {
      notification.classList.remove("opacity-100");
      notification.classList.add("opacity-0");

      notification.addEventListener("transitionend", () => {
        notification.remove();
      }, { once: true });
    }, 5000);
  }
}
