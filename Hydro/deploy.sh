#!/bin/bash

# 编译未来 OJ 平台 - 一键部署脚本
# 适用于 Debian 12 / Ubuntu 22.04
# 作者: 编译未来团队

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行，请使用 sudo ./deploy.sh"
    fi
}

# 检查系统版本
check_system() {
    log_info "检查系统版本..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "debian" ]] && [[ "$VERSION_ID" == "12" ]]; then
            log_success "检测到 Debian 12，支持的系统版本"
        elif [[ "$ID" == "ubuntu" ]] && [[ "$VERSION_ID" == "22.04" ]]; then
            log_success "检测到 Ubuntu 22.04，支持的系统版本"
        else
            log_warning "检测到 $PRETTY_NAME，未测试的系统版本，继续安装可能会有问题"
            read -p "是否继续安装? (y/N): " continue_install
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                log_error "用户取消安装"
            fi
        fi
    else
        log_error "无法检测系统版本"
    fi
}

# 第一阶段：环境准备
install_prerequisites() {
    log_info "第一阶段：安装系统依赖..."
    
    # 更新系统
    log_info "更新系统包..."
    apt update && apt upgrade -y
    
    # 安装基础工具
    log_info "安装基础开发工具..."
    apt install -y curl wget git build-essential python3 python3-pip \
        software-properties-common gnupg2 apt-transport-https ca-certificates \
        lsb-release unzip vim htop net-tools
    
    log_success "系统依赖安装完成"
}

# 安装 Node.js
install_nodejs() {
    log_info "安装 Node.js 22..."
    
    # 检查是否已安装
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ "$NODE_VERSION" -ge 18 ]]; then
            log_success "Node.js 已安装，版本: $(node --version)"
            return
        fi
    fi
    
    # 安装 Node.js 22
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    
    # 安装全局包
    npm install -g yarn pm2
    
    # 验证安装
    log_success "Node.js 安装完成，版本: $(node --version)"
    log_success "Yarn 安装完成，版本: $(yarn --version)"
    log_success "PM2 安装完成，版本: $(pm2 --version)"
}

# 安装 MongoDB
install_mongodb() {
    log_info "安装 MongoDB 7.0..."
    
    # 检查是否已安装
    if systemctl is-active --quiet mongod; then
        log_success "MongoDB 已安装并运行"
        return
    fi
    
    # 导入 MongoDB 公钥
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    
    # 添加 MongoDB 源
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | \
        tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    
    # 安装 MongoDB
    apt update && apt install -y mongodb-org
    
    # 启动服务
    systemctl start mongod
    systemctl enable mongod
    
    # 验证安装
    if systemctl is-active --quiet mongod; then
        log_success "MongoDB 安装完成并启动成功"
    else
        log_error "MongoDB 启动失败"
    fi
}

# 安装 Redis
install_redis() {
    log_info "安装 Redis..."
    
    if systemctl is-active --quiet redis-server; then
        log_success "Redis 已安装并运行"
        return
    fi
    
    apt install -y redis-server
    systemctl start redis-server
    systemctl enable redis-server
    
    log_success "Redis 安装完成"
}

# 安装评测环境
install_judge() {
    log_info "第二阶段：安装评测环境..."
    
    # 下载 go-judge
    if [[ ! -f /usr/bin/sandbox ]]; then
        log_info "下载 Go-Judge 沙箱..."
        wget https://github.com/criyle/go-judge/releases/latest/download/go-judge_1.8.8_linux_amd64 \
            -O /usr/bin/sandbox
        chmod +x /usr/bin/sandbox
        log_success "Go-Judge 下载完成"
    else
        log_success "Go-Judge 已存在"
    fi
    
    # 验证安装
    /usr/bin/sandbox --version && log_success "Go-Judge 安装验证成功"
}

# 配置系统用户
setup_users() {
    log_info "配置系统用户..."
    
    # 创建 judge 用户
    if ! id "judge" &>/dev/null; then
        useradd -m -s /bin/bash judge
        echo "judge:judge123" | chpasswd
        log_success "创建 judge 用户成功"
    else
        log_success "judge 用户已存在"
    fi
    
    # 创建配置目录
    mkdir -p ~/.hydro
    su - judge -c "mkdir -p ~/.hydro"
}

# 部署应用
deploy_application() {
    log_info "第三阶段：部署应用..."
    
    # 安装依赖
    log_info "安装项目依赖..."
    yarn install
    
    # 构建项目
    log_info "构建 TypeScript..."
    yarn build
    
    log_info "构建前端 UI..."
    yarn build:ui:production
    
    log_success "应用构建完成"
}

# 配置服务
configure_services() {
    log_info "第四阶段：配置服务..."
    
    # 数据库配置
    cat > ~/.hydro/config.json << 'EOF'
{
  "host": "127.0.0.1",
  "port": 27017,
  "name": "hydro",
  "username": "",
  "password": ""
}
EOF
    
    # 沙箱配置
    cp install/docker/judge/mount.yaml ~/.hydro/ 2>/dev/null || log_warning "沙箱配置文件不存在，跳过"
    
    # 创建沙箱启动脚本
    cat > ~/.hydro/start_sandbox.sh << 'EOF'
#!/bin/bash
cd /root/.hydro
exec /usr/bin/sandbox -mount-conf mount.yaml
EOF
    chmod +x ~/.hydro/start_sandbox.sh
    
    # 评测服务配置
    cat > ~/.hydro/judge.yaml << 'EOF'
hosts:
  localhost:
    type: hydro
    server_url: http://127.0.0.1:8888
    uname: judge
    password: judge123
    detail: full
sandbox_host: http://127.0.0.1:5050
EOF
    
    # 复制配置到 judge 用户
    cp ~/.hydro/judge.yaml /home/judge/.hydro/
    chown judge:judge /home/judge/.hydro/judge.yaml
    
    log_success "服务配置完成"
}

# 启动服务
start_services() {
    log_info "第五阶段：启动服务..."
    
    # 停止可能存在的服务
    pm2 delete all 2>/dev/null || true
    
    # 启动 Hydro 主服务
    log_info "启动 Hydro 主服务..."
    pm2 start packages/hydrooj/bin/hydrooj.js --name hydro-main
    
    # 等待主服务启动
    sleep 10
    
    # 启动沙箱服务
    log_info "启动沙箱服务..."
    pm2 start ~/.hydro/start_sandbox.sh --name hydro-sandbox
    
    # 启动评测服务
    log_info "启动评测服务..."
    pm2 start packages/hydrojudge/bin/hydrojudge.js --name hydro-judge
    
    # 保存 PM2 配置
    pm2 save
    pm2 startup
    
    log_success "服务启动完成"
}

# 创建数据库用户
setup_database() {
    log_info "配置数据库用户..."
    
    # 等待服务完全启动
    sleep 15
    
    # 创建 judge 用户的脚本
    cat > /tmp/create_judge_user.js << 'EOF'
db.user.insertOne({
  _id: 3,
  mail: 'judge@hydro.local',
  mailLower: 'judge@hydro.local',
  uname: 'judge',
  unameLower: 'judge',
  hash: "judge123",
  salt: "",
  hashType: 'sha256',
  regat: new Date(),
  ip: ['127.0.0.1'],
  loginat: new Date(),
  loginip: '127.0.0.1',
  priv: 1,
  avatar: 'gravatar:judge@hydro.local'
})
EOF
    
    # 执行数据库脚本
    node packages/hydrooj/bin/hydrooj.js db < /tmp/create_judge_user.js
    rm /tmp/create_judge_user.js
    
    # 重启服务应用配置
    pm2 restart all
    
    log_success "数据库配置完成"
}

# 安装题库插件
install_plugins() {
    log_info "第六阶段：安装题库插件..."
    
    # 安装 hydroac-client 插件
    node packages/hydrooj/bin/hydrooj.js install https://hydro.ac/hydroac-client.zip || log_warning "插件安装可能失败，可后续手动安装"
    
    # 手动添加插件
    node packages/hydrooj/bin/hydrooj.js addon add '/root/.hydro/addons/hydroac-client' || log_warning "插件添加可能失败"
    
    # 重启主服务
    pm2 restart hydro-main
    
    log_success "插件安装完成"
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."
    
    # 检查服务状态
    pm2 status
    
    # 检查端口监听
    if netstat -tulpn | grep -q ":8888"; then
        log_success "Web 服务已启动，监听端口 8888"
    else
        log_error "Web 服务未正常启动"
    fi
    
    # 测试 HTTP 响应
    sleep 5
    if curl -s -I http://localhost:8888 | grep -q "200 OK"; then
        log_success "Web 服务响应正常"
    else
        log_warning "Web 服务可能还在启动中，请稍后测试"
    fi
}

# 显示部署结果
show_results() {
    echo
    echo "============================================="
    echo -e "${GREEN}🎉 编译未来 OJ 平台部署完成！${NC}"
    echo "============================================="
    echo
    echo "访问信息："
    echo "- 网站地址: http://$(curl -s ifconfig.me):8888"
    echo "- 本地地址: http://localhost:8888"
    echo
    echo "管理信息："
    echo "- 注册第一个用户自动获得管理员权限"
    echo "- 可通过管理界面导入一本通题库"
    echo
    echo "服务管理："
    echo "- 查看状态: pm2 status"
    echo "- 重启服务: pm2 restart all"
    echo "- 查看日志: pm2 logs"
    echo
    echo "文档位置："
    echo "- 详细部署文档: ./部署文档.md"
    echo "- 前端定制文档: ./前端定制文档.md"
    echo
    echo "============================================="
    echo -e "${BLUE}编译未来 - 让每一行代码都闪闪发光 ✨${NC}"
    echo "============================================="
}

# 主函数
main() {
    echo "============================================="
    echo -e "${BLUE}编译未来 OJ 平台 - 一键部署脚本${NC}"
    echo "============================================="
    echo
    
    check_root
    check_system
    
    log_info "开始部署，预计需要 15-30 分钟..."
    
    install_prerequisites
    install_nodejs
    install_mongodb
    install_redis
    install_judge
    setup_users
    deploy_application
    configure_services
    start_services
    setup_database
    install_plugins
    verify_deployment
    show_results
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
