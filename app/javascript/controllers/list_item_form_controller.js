import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["container", "form"];

  connect() {
    this.submitting = false;
  }

  async submit(event) {
    event.preventDefault();

    if (this.submitting) {
      return;
    }

    console.log(this.formTarget.action);

    const csrfToken = document.querySelector("meta[name='csrf-token']").content;

    this.submitting = true;

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        headers: {
          "Accept": "text/html",
          "X-CSRF-Token": csrfToken
        },
        body: new FormData(this.formTarget)
      });

      const html = await response.text();

      if (!response.ok) {
        this.replaceForm(html);

        return;
      }

      this.element.dispatchEvent(
        new CustomEvent("list-item:created", {
          bubbles: true,
          detail: {
            html
          }
        })
      );

      this.element.dispatchEvent(
        new CustomEvent("flash:success", {
          bubbles: true,
          detail: {
            message: "Item added."
          }
        })
      );

      this.formTarget.reset();
    } catch(error) {
      console.error(error);

      window.dispatchEvent(
        new CustomEvent("flash:error", {
          detail: {
            message: "Unable to add the item. Please try again."
          }
        })
      );
    } finally {
      this.submitting = false;
    }
  }

  replaceForm(html) {
    const fragment = document.createRange().createContextualFragment(html);

    this.element.replaceChildren(fragment);
  }
}
