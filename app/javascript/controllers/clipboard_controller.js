import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["link", "status"];

  async copy() {
    clearTimeout(this.timeout);

    try {
      await navigator.clipboard.writeText(this.linkTarget.getAttribute("href"));

      this.statusTarget.textContent = "Copied!";
    } catch {
      this.statusTarget.textContent = "Unable to copy. Please copy the link manually.";
    }

    this.timeout = setTimeout(() => {
      this.statusTarget.textContent = "";
    }, 4000);
  }

  disconnect() {
    clearTimeout(this.timeout);
  }
}
