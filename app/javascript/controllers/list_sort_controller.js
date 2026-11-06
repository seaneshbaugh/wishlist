import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["select"];
  static values = { order: String };

  connect() {
    // A cached page may retain the selection made just before leaving it.
    this.selectTarget.value = this.orderValue;
  }

  submit() {
    // Omit the parameter for Priority so the default view has its ordinary URL.
    this.selectTarget.disabled = this.selectTarget.value === "";

    this.element.requestSubmit();

    this.selectTarget.disabled = false;
  }
}
