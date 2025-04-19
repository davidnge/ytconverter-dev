// app/javascript/application.js
console.log('Application.js loading...');

// Import Turbo first
import "@hotwired/turbo-rails"

// Then controllers
import "controllers"

// Access Stimulus after importing controllers
document.addEventListener('DOMContentLoaded', () => {
  console.log('DOM loaded, looking for controllers...');
  
  // Check if Stimulus is defined in the window
  if (window.Stimulus) {
    console.log("Stimulus found on window object!");
    console.log("Available Stimulus controllers:", Object.keys(window.Stimulus.controllers || {}));
  } else {
    console.error("Stimulus not found on window object!");
  }
  
  // Check for elements with controller attributes
  document.querySelectorAll('[data-controller]').forEach(element => {
    console.log(`Found element with controller: ${element.getAttribute('data-controller')}`);
  });
});