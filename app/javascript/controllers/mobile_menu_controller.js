import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]
  
  toggle() {
    this.panelTarget.classList.toggle("hidden")
    
    // 切换汉堡菜单图标
    const openIcon = this.element.querySelector("svg:first-child")
    const closeIcon = this.element.querySelector("svg:last-child")
    
    openIcon.classList.toggle("hidden")
    openIcon.classList.toggle("block")
    closeIcon.classList.toggle("hidden")
    closeIcon.classList.toggle("block")
  }
}