import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.reset = this.reset.bind(this);
    this.element.addEventListener("turbo:submit-end", this.reset);
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.reset);
  }

  reset(event) {
    if (event.detail.success) {
      this.element.reset();
    }
  }
}
