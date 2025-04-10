import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="conversion-status"
export default class extends Controller {
  static targets = [
    "statusText", 
    "progressBar", 
    "details", 
    "title", 
    "duration", 
    "downloadButton", 
    "errorMessage", 
    "errorText"
  ]
  
  static values = {
    id: Number
  }
  
  connect() {
    console.log("Conversion status controller connected");
    console.log("Has progress bar target:", this.hasProgressBarTarget);
    if (this.hasProgressBarTarget) {
      console.log("Initial progress bar width:", this.progressBarTarget.style.width);
      // Force initial width
      this.progressBarTarget.style.width = "0%";
    }
    
    if (this.hasIdValue) {
      this.startPolling();
    }
  }
  
  disconnect() {
    this.stopPolling();
  }
    
    startPolling() {
      // Check immediately when starting
      this.checkStatus();
      
      // Then check every 2 seconds
      this.pollingId = setInterval(() => {
        this.checkStatus();
      }, 2000); // Poll every 2 seconds
      
      // Safety timeout - stop polling after 2 minutes to avoid infinite polling
      this.safetyTimeoutId = setTimeout(() => {
        this.stopPolling();
        console.log("Safety timeout reached - stopping polling");
        // Force one final check
        this.checkStatus();
      }, 120000);
    }
  
  stopPolling() {
    if (this.pollingId) {
      clearInterval(this.pollingId);
      this.pollingId = null;
    }
    
    if (this.safetyTimeoutId) {
      clearTimeout(this.safetyTimeoutId);
      this.safetyTimeoutId = null;
    }
  }
  
  checkStatus() {
    console.log("Checking status...");
    
    // Add a cache-busting parameter to prevent browser caching
    const timestamp = new Date().getTime();
    fetch(`/conversions/${this.idValue}.json?_=${timestamp}`)
      .then(response => response.json())
      .then(data => {
        console.log("Received status data:", data);
        
        // If status is completed, force UI update regardless of previous state
        if (data.status === 'completed') {
          console.log("Conversion completed! Updating UI...");
          this.statusTextTarget.textContent = "Completed";
          this.progressBarTarget.style.width = "100%";
          this.downloadButtonTarget.classList.remove('hidden');
          this.stopPolling(); // Stop polling once completed
        } else {
          // For other statuses, continue with normal update
          this.updateStatus(data);
        }
      })
      .catch(error => console.error('Error:', error));
  }
  
  updateStatus(data) {
  // Update status text
  this.statusTextTarget.textContent = data.status.charAt(0).toUpperCase() + data.status.slice(1);
  
  // Handle different statuses
  if (data.status === 'pending') {
    // For pending, start at a small percentage
    this.animateProgress(15);
  } else if (data.status === 'processing') {
    // For processing, animate to 75%
    this.animateProgress(75);
  } else if (data.status === 'completed') {
    // For completed, jump to 100%
    this.progressBarTarget.style.width = '100%';
    this.downloadButtonTarget.classList.remove('hidden');
    this.stopPolling();
  } else if (data.status === 'failed') {
    // For failed, show error
    this.errorMessageTarget.classList.remove('hidden');
    this.errorTextTarget.textContent = data.error_message || 'An unknown error occurred';
    this.stopPolling();
  }
  
  // Show details if we have a title
  if (data.title) {
    this.detailsTarget.classList.remove('hidden');
    this.titleTarget.textContent = data.title;
    
    if (data.duration) {
      this.durationTarget.textContent = data.duration;
    }
  }
}
  
  animateProgress(targetPercent) {
  // Cancel any existing animation
  if (this.progressInterval) {
    clearInterval(this.progressInterval);
  }
  
  // Set initial width if it's not already set
  const currentWidth = parseInt(this.progressBarTarget.style.width) || 0;
  
  // Calculate how many steps to take
  const distance = targetPercent - currentWidth;
  const steps = 30; // Total steps for animation
  const increment = distance / steps;
  let currentStep = 0;
  
  // Create animation interval
  this.progressInterval = setInterval(() => {
    currentStep++;
    
    // Calculate new width
    const newWidth = currentWidth + (increment * currentStep);
    
    // Apply new width
    this.progressBarTarget.style.width = `${Math.min(newWidth, targetPercent)}%`;
    
    // Stop if we've reached target or max steps
    if (currentStep >= steps || newWidth >= targetPercent) {
      clearInterval(this.progressInterval);
    }
  }, 100); // Update every 100ms
}