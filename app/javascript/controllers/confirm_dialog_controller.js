import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "message", "confirmButton"]
  static values = { 
    message: String,
    confirmUrl: String,
    confirmMethod: String
  }

  connect() {
    // 确保对话框初始时是隐藏的
    if (this.hasDialogTarget) {
      this.dialogTarget.classList.add("hidden")
    }
  }

  open(event) {
    event.preventDefault()
    
    // 从触发元素获取确认信息
    const triggerElement = event.currentTarget
    this.messageValue = triggerElement.dataset.confirmMessage || "确定要执行此操作吗？"
    this.confirmUrlValue = triggerElement.href || triggerElement.dataset.confirmUrl
    this.confirmMethodValue = triggerElement.dataset.turboMethod || "delete"
    
    // 更新对话框中的消息
    if (this.hasMessageTarget) {
      this.messageTarget.textContent = this.messageValue
    }
    
    // 显示对话框
    this.dialogTarget.classList.remove("hidden")
    
    // 聚焦到确认按钮
    if (this.hasConfirmButtonTarget) {
      this.confirmButtonTarget.focus()
    }
  }

  confirm() {
    // 创建一个表单来执行删除操作
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.confirmUrlValue
    form.style.display = "none"
    
    // 添加 CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const csrfInput = document.createElement("input")
      csrfInput.type = "hidden"
      csrfInput.name = "authenticity_token"
      csrfInput.value = csrfToken
      form.appendChild(csrfInput)
    }
    
    // 添加 method 字段用于 Rails 的 method override
    if (this.confirmMethodValue.toLowerCase() !== "post") {
      const methodInput = document.createElement("input")
      methodInput.type = "hidden"
      methodInput.name = "_method"
      methodInput.value = this.confirmMethodValue
      form.appendChild(methodInput)
    }
    
    // 添加表单到文档并提交
    document.body.appendChild(form)
    form.submit()
  }

  cancel() {
    this.dialogTarget.classList.add("hidden")
  }

  // 点击背景关闭对话框
  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) {
      this.cancel()
    }
  }

  // ESC 键关闭对话框
  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.cancel()
    }
  }
}