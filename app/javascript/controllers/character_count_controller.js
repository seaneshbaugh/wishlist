import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["field", "counter"];

  static values = {
    max: Number
  };

  connect() {
    this.update();
  }

  update() {
    const length = this.fieldTarget.value.length;

    this.counterTarget.textContent = length;

    this.counterTarget.classList.toggle(
      "text-amber-600",
      length >= 0.9 * this.maxValue && length < this.maxValue
    );

    this.counterTarget.classList.toggle(
      "text-red-600",
      length >= this.maxValue
    );
  }
}
