import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["display", "editForm", "purchaseForm"];

  edit() {
    this.displayTarget.classList.add("hidden");
    this.editFormTarget.classList.remove("hidden");
  }

  cancelEdit() {
    this.editFormTarget.classList.add("hidden");
    this.displayTarget.classList.remove("hidden");
  }

  purchase() {
    this.displayTarget.classList.add("hidden");
    this.purchaseFormTarget.classList.remove("hidden");
  }

  cancelPurchase() {
    this.purchaseFormTarget.classList.add("hidden");
    this.displayTarget.classList.remove("hidden");
  }
}
