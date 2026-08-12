import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"];

  static values = {
    url: String
  };

  connect() {
    this.draggedItem = null;
    this.originalOrder = null;
    this.reorderPending = false;
    this.insertionIndicator = document.createElement("div");

    this.insertionIndicator.className = "mx-10 h-1.5 bg-blue-500 rounded-full";

    this.insertionIndicator.hidden = true;

    this.element.appendChild(this.insertionIndicator);
  }

  dragstart(event) {
    if (this.reorderPending) {
      event.preventDefault();

      return;
    }

    const item = event.target.closest("[data-reorder-target='item']");
    const handle = event.target.closest("[data-reorder-handle]");

    if (!item || !handle) {
      event.preventDefault();

      return;
    }

    this.draggedItem = item;
    this.originalOrder = [...this.itemTargets];

    item.classList.add("opacity-50", "rotate-1");

    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", item.dataset.id);
  }

  dragover(event) {
    event.preventDefault();

    const item = event.target.closest("[data-reorder-target='item']");

    if (!item || item === this.draggedItem) {
      return;
    }

    event.dataTransfer.dropEffect = "move";

    const rect = item.getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;

    if (event.clientY < midpoint) {
      item.before(this.insertionIndicator);
    } else {
      item.after(this.insertionIndicator);
    }

    this.insertionIndicator.hidden = false;
  }

  dragenter(event) {
  }

  dragleave(event) {
  }

  async drop(event) {
    event.preventDefault();

    if (!this.draggedItem || this.insertionIndicator.hidden) {
      return;
    }

    this.insertionIndicator.before(this.draggedItem);

    const positions = this.itemTargets.map((item, index) => ({
      id: item.dataset.id,
      position: index
    }));

    const csrfToken = document.querySelector("meta[name='csrf-token']").content;

    this.reorderPending = true;

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ positions })
      });

      if (!response.ok) {
        const body = await response.json();


        throw new Error(body.error || "Unable to reorder lists.");
      }
    } catch(error) {
      console.error(error);

      this.originalOrder.forEach(item => {
        this.element.appendChild(item);
      });

      this.originalOrder = null;

      window.dispatchEvent(
        new CustomEvent("flash:error", {
          detail: {
            message: error.message
          }
        })
      );
    } finally {
      this.reorderPending = false;
    }
  }

  dragend(event) {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("opacity-50", "rotate-1");
    }

    this.insertionIndicator.hidden = true;

    this.draggedItem = null;
  }
}
