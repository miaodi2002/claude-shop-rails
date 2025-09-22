# Claude Shop 项目 - Claude Code 配置

## 📋 项目上下文记忆

### 项目基本信息
- **项目**: Claude Shop - AWS账号配额管理系统
- **技术栈**: Rails 8.0 + MySQL + Tailwind CSS

### 核心文件结构
```
claude-shop-rails/
├── CLAUDE.md                 # 本配置文件
├── PRD.md                   # 产品需求文档
├── app/                     # Rails应用代码
├── config/                  # 配置文件
└── db/                      # 数据库相关
```
---

## 🗄️ 数据库查询手册

### 数据库连接
使用Docker连接到MySQL数据库：
```bash
docker exec claude_shop_mysql mysql -u root -p'claude_shop_root_2024' claude_shop_development

