import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["container"];

  refresh(event) {
    this.containerTarget.innerHTML = event.detail.html;

    const newItem = this.containerTarget.querySelector("[data-new-list-item]");

    if (!newItem) {
      return;
    }

    setTimeout(() => {
      newItem.classList.remove("bg-blue-50");
    }, 2500);
  }
}
