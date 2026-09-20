import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => {
      this.element.classList.remove("opacity-100");
      this.element.classList.add("opacity-0");

      this.element.addEventListener("transitionend", () => {
        this.element.remove();
      }, { once: true });
    }, 5000);
  }

  disconnect() {
    clearTimeout(this.timeout);
  }
}
