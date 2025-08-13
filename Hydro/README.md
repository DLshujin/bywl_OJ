# 编译未来 OJ 平台

> 基于 Hydro OJ 定制的专业信息学奥林匹克竞赛培训平台

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node.js](https://img.shields.io/badge/node.js-22%2B-green)](https://nodejs.org/)
[![MongoDB](https://img.shields.io/badge/MongoDB-7.0-green)](https://www.mongodb.com/)

## 🎯 平台特色

- **🎨 GoC 图形化编程** - 江涛老师独创的编程语言，培养编程思维
- **💻 专业在线 IDE** - 智能错误检测，实时语法高亮，VS Code 风格界面
- **🏆 完整题库系统** - 内置一本通编程启蒙题库 480+ 题目
- **⚡ 高性能评测** - 基于 Go-Judge 的毫秒级代码评测
- **📚 教学管理** - 支持班级管理、作业布置、成绩统计

## 🚀 快速部署

### 系统要求
- **系统**: Debian 12 / Ubuntu 22.04
- **配置**: 2核4GB内存，60GB硬盘
- **权限**: root 用户

### 一键安装
```bash
# 1. 克隆项目
git clone https://github.com/DLshujin/bywl_OJ.git
cd bywl_OJ

# 2. 执行部署脚本
chmod +x deploy.sh
./deploy.sh

# 3. 等待部署完成（15-30分钟）
```

### 访问平台
- **网址**: http://服务器IP:8888
- **管理**: 注册第一个用户自动获得管理员权限
- **功能**: GoC编程、在线IDE、题目练习

## 📚 文档

- **[详细部署指南](./部署文档.md)** - 完整的手动部署步骤
- **[前端定制文档](./前端定制文档.md)** - 界面定制说明

## 🏗️ 技术架构

- **后端**: Node.js 22 + TypeScript + Koa.js
- **数据库**: MongoDB 7.0 + Redis
- **前端**: Nunjucks + CSS3 + Ace Editor
- **评测**: Go-Judge 沙箱
- **部署**: PM2 + Docker (可选)

## 📊 推荐配置

| 用户规模 | CPU | 内存 | 硬盘 | 带宽 |
|---------|-----|------|------|------|
| 30人以下 | 2核 | 4GB | 60GB | 3M |
| 50人以下 | 4核 | 8GB | 100GB | 5M |
| 100人以下 | 8核 | 16GB | 200GB | 10M |

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目基于 [AGPL-3.0](LICENSE) 开源许可证

---

**编译未来 - 让每一行代码都闪闪发光 ✨**