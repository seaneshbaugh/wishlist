import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.highlightNewItem();
  }

  highlightNewItem() {
    const newItem = this.element.querySelector("[data-new-list-item]");

    if (!newItem) {
      return;
    }

    setTimeout(() => {
      newItem.classList.remove("bg-blue-50");
    }, 2500);
  }
}
