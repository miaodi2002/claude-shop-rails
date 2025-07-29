import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  
  connect() {
    this.element.setAttribute("data-dropdown-open", "false")
  }
  
  toggle(event) {
    event.stopPropagation()
    
    if (this.element.getAttribute("data-dropdown-open") === "true") {
      this.hide()
    } else {
      this.show()
    }
  }
  
  show() {
    this.element.setAttribute("data-dropdown-open", "true")
    this.menuTarget.classList.remove("hidden")
  }
  
  hide() {
    this.element.setAttribute("data-dropdown-open", "false")
    this.menuTarget.classList.add("hidden")
  }
}