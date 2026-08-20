import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "items", "section"];

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
    this.originalOrder = this.itemTargets.map(item => ({
      item,
      parent: item.parentElement,
      nextSibling: item.nextSibling
    }));

    item.classList.add("opacity-50", "rotate-1");

    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", item.dataset.id);
  }

  dragover(event) {
    if (!this.draggedItem || this.reorderPending) {
      return;
    }

    if (event.target === this.insertionIndicator || this.insertionIndicator.contains(event.target)) {
      return;
    }

    const item = event.target.closest("[data-reorder-target='item']");
    const section = event.target.closest("[data-reorder-target='section']");

    if (!item && !section) {
      return;
    }

    if (item === this.draggedItem) {
      return;
    }

    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    if (item) {
      this.positionIndicatorForItem(item, event);
    } else {
      this.positionIndicatorForSection(section, event);
    }
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

    let positions = [];

    if (this.sectionTargets.length === 0) {
      positions = this.itemTargets.map((item, position) => ({
        id: item.dataset.id,
        position
      }));
    } else {
      positions = this.sectionTargets.flatMap(section => {
        const priority = section.dataset.priority;

        return [...section.querySelectorAll("[data-reorder-target='item']")]
          .map((item, position) => ({
            id: item.dataset.id,
            priority,
            position
          }));
      });
    }

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

      this.originalOrder.forEach(({ item, parent, nextSibling }) => {
        parent.insertBefore(item, nextSibling);
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

  positionIndicatorForItem(item, event) {
    const rect = item.getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;

    if (event.clientY < midpoint) {
      item.before(this.insertionIndicator);
    } else {
      item.after(this.insertionIndicator);
    }

    this.insertionIndicator.hidden = false;
  }

  positionIndicatorForSection(section, event) {
    const items = [...section.querySelectorAll("[data-reorder-target='item']")].filter(item => item !== this.draggedItem);

    for (const item of items) {
      const rect = item.getBoundingClientRect();
      const midpoint = rect.top + rect.height / 2;

      if (event.clientY < midpoint) {
        item.before(this.insertionIndicator);
        this.insertionIndicator.hidden = false;

        return;
      }
    }

    const itemsContainer = section.querySelector("[data-reorder-target='items']");

    itemsContainer.appendChild(this.insertionIndicator);
    this.insertionIndicator.hidden = false;
  }
}
