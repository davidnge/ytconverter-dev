import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "statusContainer", 
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
    if (this.hasIdValue) {
      this.startPolling();
    }
    
    // Check if we need to show an error message
    if (this.element.querySelector('[data-conversion-status-target="errorMessage"]')) {
      const errorMsg = this.element.querySelector('[data-conversion-status-target="errorMessage"]');
      if (errorMsg && errorMsg.classList.contains('hidden')) {
        errorMsg.classList.remove('hidden');
      }
    }
  }
  
  disconnect() {
    this.stopPolling();
  }
  
  startPolling() {
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
    }
  }
  
  checkStatus() {
    if (!this.hasIdValue) return;
    
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
        const status = data.status.toLowerCase().trim();
        
        // Handle status changes by replacing content
        this.updateStatusDisplay(status);
        
        // Handle completed state
        if (status === 'completed') {
          if (this.hasDownloadButtonTarget) {
            this.downloadButtonTarget.classList.remove('hidden');
          }
          
          this.stopPolling();
          
          // Update details if available
          if (data.title && this.hasDetailsTarget && this.hasTitleTarget) {
            this.detailsTarget.classList.remove('hidden');
            this.titleTarget.textContent = data.title;
            
            if (data.duration && this.hasDurationTarget) {
              this.durationTarget.textContent = data.duration;
            }
          }
        } 
        // Handle failed state
        else if (status === 'failed') {
          if (this.hasErrorMessageTarget) {
            this.errorMessageTarget.classList.remove('hidden');
            
            if (this.hasErrorTextTarget && data.error_message) {
              this.errorTextTarget.textContent = data.error_message;
            }
          }
          this.stopPolling();
        }
      })
      .catch(error => {
        console.error('Error checking status:', error);
      });
  }
  
  updateStatusDisplay(status) {
    if (!this.hasStatusContainerTarget) return;
    
    // Create the appropriate HTML based on the status
    let statusHTML = '';
    
    if (status === 'pending') {
      statusHTML = `
        <div class="flex items-center text-indigo-600 font-medium">
          <span>Starting to convert your video...</span>
          <svg class="animate-spin ml-2 h-4 w-4 text-indigo-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        </div>
      `;
    } 
    else if (status === 'processing') {
      statusHTML = `
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
            <p class="text-indigo-500 italic mt-2" id="processing-tip">Long videos may take a moment...</p>
          </div>
        </div>
      `;
      
      // Start tip rotation after replacing the content
      setTimeout(() => {
        this.startTipRotation();
      }, 100);
    }
    else if (status === 'completed') {
      statusHTML = `
        <div class="flex items-center text-green-700 font-medium">
          <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          <span>Conversion completed! Your MP3 file is ready for download.</span>
        </div>
      `;
    }
    else {
      // Fallback for any unexpected status
      statusHTML = `<div class="text-indigo-600 font-medium">${this.capitalizeFirstLetter(status)}</div>`;
    }
    
    // Update the container with the new HTML
    this.statusContainerTarget.innerHTML = statusHTML;
  }
  
  startTipRotation() {
    const processingTip = document.getElementById('processing-tip');
    if (!processingTip) return;
    
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
    
    // Clear any existing tip interval
    if (this.tipInterval) {
      clearInterval(this.tipInterval);
    }
    
    // Show a tip every 8 seconds
    this.tipInterval = setInterval(() => {
      if (processingTip) {
        currentTipIndex = (currentTipIndex + 1) % tips.length;
        processingTip.textContent = tips[currentTipIndex];
      } else {
        // If the tip element is gone, clear the interval
        clearInterval(this.tipInterval);
        this.tipInterval = null;
      }
    }, 8000);
  }
  
  capitalizeFirstLetter(string) {
    if (!string) return '';
    return string.charAt(0).toUpperCase() + string.slice(1);
  }
}