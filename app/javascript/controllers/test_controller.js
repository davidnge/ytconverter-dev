// app/javascript/controllers/test_controller.js
import { Controller } from "@hotwired/stimulus"

/**
export default class extends Controller {
  connect() {
    console.log("Test controller connected!");
    document.body.style.border = "5px solid green";
  }
}

**/

export default class extends Controller {
  static targets = []
  
  connect() {
    document.body.style.border = "5px solid red"
    console.log("Test controller connected!")
  }
}