import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "menu"];

  connect() {
    this.close();
  }

  toggle() {
    const hidden = this.menuTarget.classList.toggle("hidden");

    this.buttonTarget.setAttribute("aria-expanded", String(!hidden));
  }

  close(event) {
    const menuHadFocus = this.menuTarget.contains(document.activeElement);

    this.menuTarget.classList.add("hidden");
    this.buttonTarget.setAttribute("aria-expanded", "false");

    if (event?.type === "keydown" && menuHadFocus) {
      this.buttonTarget.focus();
    }
  }
}
