// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("turbo:load", () => {
  const button = document.getElementById("mobile-menu-button");
  const menu = document.getElementById("mobile-menu");

  if (!button || !menu) {
    return;
  }

  button.addEventListener("click", () => {
    menu.classList.toggle("hidden");
  });
});
