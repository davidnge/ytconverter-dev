// app/javascript/controllers/conversion_status_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "statusContainer", 
    "details", 
    "title", 
    "duration", 
    "downloadButton", 
    "errorMessage", 
    "errorText",
    "manualRefresh",
    "processingTip",
    "convertAnotherLink"  // Added target for the Convert Another link
  ]
  
  static values = {
    id: Number,
    pollInterval: { type: Number, default: 3000 },
    maxPollTime: { type: Number, default: 600000 } // 10 minutes in milliseconds
  }
  
  connect() {
    console.log("Conversion status controller connected with ID:", this.idValue);

    console.log("Conversion status controller connected");
    console.log("Has status container target:", this.hasStatusContainerTarget);
    console.log("Has details target:", this.hasDetailsTarget);
    console.log("Has title target:", this.hasTitleTarget);
    console.log("Has duration target:", this.hasDurationTarget);
    console.log("Has download button target:", this.hasDownloadButtonTarget);
    console.log("Has error message target:", this.hasErrorMessageTarget);
    console.log("Has error text target:", this.hasErrorTextTarget);
    console.log("Has processing tip target:", this.hasProcessingTipTarget);
    console.log("Has convert another link target:", this.hasConvertAnotherLinkTarget);
    
    // Check if we need to show an error message immediately
    if (this.hasErrorMessageTarget && !this.errorMessageTarget.classList.contains('hidden')) {
      console.log("Showing pre-existing error message");
    }
    
    if (this.hasIdValue) {
      this.startPolling();
      this.setupManualRefreshTimer();
      // Start tip rotation as soon as we connect, regardless of status
      this.startTipRotation();
    }
  }
  
  disconnect() {
    this.stopPolling();
    this.clearTipRotation();
  }
  
  startPolling() {
    console.log("Starting polling for conversion", this.idValue);
    
    // Check immediately when starting
    this.checkStatus();
    
    // Then check regularly
    this.pollingId = setInterval(() => {
      this.checkStatus();
    }, this.pollIntervalValue);
    
    // Safety timeout to stop polling after max time
    this.safetyTimeoutId = setTimeout(() => {
      console.log("Safety timeout reached, stopping polling");
      this.stopPolling();
      
      // One final check
      this.checkStatus();
    }, this.maxPollTimeValue);
  }
  
  stopPolling() {
    console.log("Stopping polling");
    if (this.pollingId) {
      clearInterval(this.pollingId);
      this.pollingId = null;
    }
    
    if (this.safetyTimeoutId) {
      clearTimeout(this.safetyTimeoutId);
      this.safetyTimeoutId = null;
    }
  }
  
  // In conversion_status_controller.js, update the checkStatus method
  checkStatus() {
    if (!this.hasIdValue) return;
    
    console.log(`${new Date().toISOString()} - Starting status check for ID: ${this.idValue}`);
    
    // Add a cache-busting parameter to prevent browser caching
    const timestamp = new Date().getTime();
    
    fetch(`/conversions/${this.idValue}.json?_=${timestamp}`, {
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      }
    })
      .then(response => {
        console.log(`Status response received, status code: ${response.status}`);
        if (!response.ok) {
          throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        console.log("Raw status response data:", JSON.stringify(data));
        
        // Normalize status to lowercase for consistent comparison
        const status = (data.status || "").toString().toLowerCase().trim();
        console.log(`Normalized status: '${status}'`);
        
        // Debugging for complete status
        if (status === 'completed') {
          console.log("DETECTED COMPLETED STATUS - should update UI now");
        }
        
        // Update UI based on status
        this.updateStatusUI(status, data);
        
        // Stop polling if we've reached a terminal state
        if (status === 'completed' || status === 'failed') {
          console.log(`Terminal status reached: ${status} - stopping polling`);
          this.stopPolling();
        }
      })
      .catch(error => {
        console.error('Error checking status:', error);
      });
  }
  
  updateStatusUI(status, data) {
    // Handle different statuses
    if (status === 'completed') {
      this.handleCompletedStatus(data);
    } 
    else if (status === 'processing') {
      this.handleProcessingStatus();
    }
    else if (status === 'pending') {
      this.handlePendingStatus();
    }
    else if (status === 'failed') {
      this.handleFailedStatus(data);
    }
    else {
      // Fallback for unexpected status
      this.statusContainerTarget.innerHTML = `
        <div class="text-indigo-600 font-medium">
          ${this.capitalizeFirstLetter(status)}
        </div>
      `;
    }
  }
  
  handleCompletedStatus(data) {
    console.log("handleCompletedStatus called with data:", data);
    
    // 1. Update the status container with completed HTML
    console.log("Updating status container HTML for completed status");
    this.statusContainerTarget.innerHTML = `
      <div class="flex items-center text-green-700 font-medium">
        <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
        </svg>
        <span>Conversion completed! Your MP3 file is ready for download.</span>
      </div>
    `;
    
    // 2. Show download button
    if (this.hasDownloadButtonTarget) {
      console.log("Showing download button");
      this.downloadButtonTarget.classList.remove('hidden');
    } else {
      console.error("Download button target not found!");
    }
    
    // 3. Update details if available
    if (this.hasDetailsTarget) {
      console.log("Updating details");
      this.detailsTarget.classList.remove('hidden');
      
      if (data.title && this.hasTitleTarget) {
        console.log("Updating title to:", data.title);
        this.titleTarget.textContent = data.title;
      }
      
      if (data.duration && this.hasDurationTarget) {
        console.log("Updating duration to:", data.duration);
        this.durationTarget.textContent = data.duration;
      }
    } else {
      console.error("Details target not found!");
    }
    
    // Hide manual refresh if it's visible
    if (this.hasManualRefreshTarget) {
      this.manualRefreshTarget.classList.add('hidden');
    }
    
    // Stop tip rotation
    this.clearTipRotation();

    // Ensure "Convert Another" link is visible
    if (this.hasConvertAnotherLinkTarget) {
      this.convertAnotherLinkTarget.classList.remove('hidden');
    }
  }
  
  handleProcessingStatus() {
    console.log("PROCESSING status detected");
    
    // Update the status container with processing HTML
    this.statusContainerTarget.innerHTML = `
      <div>
        <div class="flex items-center text-indigo-600 font-medium">
          <span>Processing your audio file...</span>
          <svg class="animate-spin ml-2 h-4 w-4 text-indigo-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        </div>
        
        <div class="text-sm text-gray-600 mt-2 ml-0 border-l-2 border-indigo-100 pl-4">
          <p class="mb-1">✓ Connected to YouTube</p>
          <p class="mb-1">✓ Extracting audio</p>
          <p class="text-indigo-600 flex items-center">
            Converting to MP3
            <svg class="animate-spin ml-2 h-3 w-3 text-indigo-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
          </p>
          <p class="text-indigo-500 italic mt-2" data-conversion-status-target="processingTip">Long videos may take a moment...</p>
        </div>
      </div>
    `;
    
    // Ensure tip rotation is running
    this.startTipRotation();

    // Make sure "Convert Another" link is visible
    if (this.hasConvertAnotherLinkTarget) {
      this.convertAnotherLinkTarget.classList.remove('hidden');
    }
  }
  
  handlePendingStatus() {
    console.log("PENDING status detected");
    
    // Update the status container with pending HTML
    this.statusContainerTarget.innerHTML = `
      <div class="flex items-center text-indigo-600 font-medium">
        <span>Starting to convert your video...</span>
        <svg class="animate-spin ml-2 h-4 w-4 text-indigo-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      </div>
    `;

    // Ensure "Convert Another" link is visible
    if (this.hasConvertAnotherLinkTarget) {
      this.convertAnotherLinkTarget.classList.remove('hidden');
    }
  }
  
  handleFailedStatus(data) {
    console.log("FAILED status detected");
    
    const errorMessage = data.error_message || "An unknown error occurred. Please try a different video.";

    // Show error message
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.remove('hidden');
      
      if (this.hasErrorTextTarget) {
        this.errorTextTarget.textContent = errorMessage;
      }
    }
    
    // Update the main status container to show the error status
    this.statusContainerTarget.innerHTML = `
      <div class="flex items-start text-red-700 font-medium">
        <svg class="h-5 w-5 mr-2 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <span>Conversion Failed: ${errorMessage}</span>
      </div>
    `;
    
    // Ensure the Convert Another link is always visible on error
    if (this.hasConvertAnotherLinkTarget) {
      this.convertAnotherLinkTarget.classList.remove('hidden');
    }
  }
  
  startTipRotation() {
    // Clear any existing rotation
    this.clearTipRotation();
    
    // Only start if we have the target
    if (!this.hasProcessingTipTarget) return;
    
    // Define some processing tips
    const tips = [
      "Optimizing audio quality...",
      "Applying audio filters...",
      "Encoding with selected bitrate...",
      "Preparing your download...",
      "Almost there...",
      "Finalizing your MP3 file...",
      "Long videos may take a moment...",
      "We're working on your conversion...",
      "Thank you for your patience..."
    ];
    
    let currentTipIndex = 0;
    
    // Show a tip every 8 seconds
    this.tipIntervalId = setInterval(() => {
      if (this.hasProcessingTipTarget) {
        currentTipIndex = (currentTipIndex + 1) % tips.length;
        this.processingTipTarget.textContent = tips[currentTipIndex];
      } else {
        // If the tip element is gone, clear the interval
        this.clearTipRotation();
      }
    }, 8000);
  }
  
  clearTipRotation() {
    if (this.tipIntervalId) {
      clearInterval(this.tipIntervalId);
      this.tipIntervalId = null;
    }
  }
  
  setupManualRefreshTimer() {
    if (this.hasManualRefreshTarget) {
      // Show the manual refresh button after 60 seconds if conversion is still processing
      setTimeout(() => {
        if (!this.manualRefreshTarget.classList.contains('hidden')) {
          return; // Already visible
        }
        
        const statusContent = this.statusContainerTarget.textContent;
        if (statusContent.includes('Processing') || statusContent.includes('Starting')) {
          this.manualRefreshTarget.classList.remove('hidden');
        }
      }, 60000); // 1 minute
    }
  }
  
  capitalizeFirstLetter(string) {
    if (!string) return '';
    return string.charAt(0).toUpperCase() + string.slice(1);
  }
}