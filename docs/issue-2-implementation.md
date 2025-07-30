# Issue #2 实现说明 - AWS账号删除确认对话框

## 实现概述
为 AWS 账号删除功能添加了自定义的确认对话框，替代了浏览器默认的 confirm 对话框，提升了用户体验。

## 实现细节

### 1. 创建 Stimulus Controller
- 文件：`app/javascript/controllers/confirm_dialog_controller.js`
- 功能：
  - 管理对话框的显示/隐藏
  - 处理确认和取消操作
  - 支持 ESC 键和背景点击关闭
  - 动态设置确认消息内容
  - 通过表单提交执行删除操作

### 2. 创建确认对话框组件
- 文件：`app/views/shared/_confirm_dialog.html.erb`
- 特性：
  - 使用 Tailwind CSS 样式
  - 响应式设计
  - 警告图标和清晰的视觉提示
  - 动态消息内容显示

### 3. 更新视图文件
- `app/views/admin/aws_accounts/index.html.erb`
  - 更新删除链接，使用 Stimulus action
  - 添加确认对话框渲染
  
- `app/views/admin/aws_accounts/show.html.erb`
  - 新增删除按钮
  - 添加确认对话框渲染

## 使用方法

删除链接现在使用以下格式：
```erb
<%= link_to admin_aws_account_path(account), 
    data: { 
      action: "click->confirm-dialog#open",
      confirm_message: "确定要删除账号 #{account.account_name} 吗？此操作不可撤销。",
      turbo_method: :delete
    },
    class: "text-red-600 hover:text-red-900 text-sm font-medium" do %>
  删除
<% end %>
```

## 测试步骤

1. 启动 Rails 服务器：`bin/rails server`
2. 访问 AWS 账号列表页面：`/admin/aws_accounts`
3. 点击任意账号的"删除"链接
4. 确认弹出自定义对话框
5. 测试"确认删除"和"取消"按钮
6. 测试 ESC 键关闭功能
7. 测试点击背景关闭功能

## 注意事项

- 需要确保 Ruby 版本 >= 3.1.0（Rails 8 要求）
- 确保 Stimulus 框架正确加载
- 删除操作会记录到审计日志中
- 删除是不可逆操作，数据将永久删除

## 相关文件

- Controller: `app/controllers/admin/aws_accounts_controller.rb#destroy`
- JavaScript: `app/javascript/controllers/confirm_dialog_controller.js`
- 共享组件: `app/views/shared/_confirm_dialog.html.erb`
- 视图文件: 
  - `app/views/admin/aws_accounts/index.html.erb`
  - `app/views/admin/aws_accounts/show.html.erb`