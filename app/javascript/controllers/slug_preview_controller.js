import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["name", "slug"];

  connect() {
    this.update();
  }

  update() {
    const slug = this.slugify(this.nameTarget.value);

    this.slugTarget.textContent = slug.length === 0 ? "your-list-name" : slug;
  }

  slugify(text) {
    return text
      .trim()
      .replace(/\s+/g, " ")
      .toLowerCase()
      .replace(/[^\w\s-]/g, "")
      .replace(/\s+/g, "-")
      .replace(/-+/g, "-");
  }
}
