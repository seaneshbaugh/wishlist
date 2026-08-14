import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.showInfo = this.showInfo.bind(this);
    this.showSuccess =this.showSuccess.bind(this);
    this.showError = this.showError.bind(this);

    window.addEventListener("flash:info", this.showInfo);
    window.addEventListener("flash:success", this.showSuccess);
    window.addEventListener("flash:error", this.showError);
  }

  disconnect() {
    window.removeEventListener("flash:info", this.showInfo);
    window.removeEventListener("flash:success", this.showSuccess);
    window.removeEventListener("flash:error", this.showError);
  }

  showInfo(event) {
    this.showMessage(event.detail.message, "border-indigo-200 bg-indigo-50");
  }

  showSuccess(event) {
    this.showMessage(event.detail.message, "border-green-200 bg-green-50");
  }

  showError(event) {
    this.showMessage(event.detail.message, "border-red-200 bg-red-50");
  }

  showMessage(message, classNames) {
    const notification = document.createElement("div");

    notification.className = `rounded-lg border ${classNames} px-4 py-3 text-sm text-red-700 shadow-sm opacity-100 transition-opacity duration-[2500ms]`;

    notification.textContent = message;

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
