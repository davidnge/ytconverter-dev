
import { Controller } from "@hotwired/stimulus"

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
      // Force initial width based on status
      const status = this.statusTextTarget.textContent.toLowerCase();
      if (status === 'pending') {
        this.progressBarTarget.style.width = "5%";
      } else if (status === 'processing') {
        this.progressBarTarget.style.width = "40%";
      } else if (status === 'completed') {
        this.progressBarTarget.style.width = "100%";
      }
    }
    
    if (this.hasIdValue) {
      this.startPolling();
    }
  }
  
  disconnect() {
    this.stopPolling();
  }
  
  startPolling() {
    // Simple polling strategy
    console.log("Starting polling for conversion ID:", this.idValue);
    
    // Check immediately when starting
    this.checkStatus();
    
    // Then check every 3 seconds
    this.pollingId = setInterval(() => {
      this.checkStatus();
    }, 3000);
  }
  
  stopPolling() {
    if (this.pollingId) {
      clearInterval(this.pollingId);
      this.pollingId = null;
      console.log("Stopped polling");
    }
  }
  
  checkStatus() {
    console.log("Checking status for ID:", this.idValue);
    
    // Add a cache-busting parameter to prevent browser caching
    const timestamp = new Date().getTime();
    
    fetch(`/conversions/${this.idValue}.json?_=${timestamp}`, {
      headers: {
        'Cache-Control': 'no-cache'
      }
    })
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        console.log("Received status data:", data);
        
        // Update status text
        this.statusTextTarget.textContent = this.capitalizeFirstLetter(data.status);
        
        // Handle different statuses
        if (data.status === 'pending') {
          this.animateProgressTo(15);
        } else if (data.status === 'processing') {
          this.animateProgressTo(75);
        } else if (data.status === 'completed') {
          this.progressBarTarget.style.width = '100%';
          this.downloadButtonTarget.classList.remove('hidden');
          this.stopPolling();
          
          // Update details if available
          if (data.title) {
            this.detailsTarget.classList.remove('hidden');
            this.titleTarget.textContent = data.title;
            
            if (data.duration) {
              this.durationTarget.textContent = data.duration;
            }
          }
        } else if (data.status === 'failed') {
          this.errorMessageTarget.classList.remove('hidden');
          this.errorTextTarget.textContent = data.error_message || 'An unknown error occurred';
          this.stopPolling();
        }
      })
      .catch(error => {
        console.error('Error checking status:', error);
        
        // We'll keep polling despite errors, but log them
        console.log("Continuing to poll despite error");
      });
  }
  
  capitalizeFirstLetter(string) {
    return string.charAt(0).toUpperCase() + string.slice(1);
  }
  
  animateProgressTo(targetPercent) {
    // Get current width
    const currentWidth = parseInt(this.progressBarTarget.style.width) || 0;
    
    // Only animate if target is greater than current
    if (targetPercent > currentWidth) {
      this.progressBarTarget.style.transition = 'width 1s ease-out';
      this.progressBarTarget.style.width = `${targetPercent}%`;
    }
  }
}