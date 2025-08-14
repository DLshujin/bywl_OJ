#!/bin/bash

# 编译未来 OJ 平台 - 一键部署脚本
# 适用于 Debian 12 / Ubuntu 22.04
# 作者: 编译未来团队

set -euo pipefail  # 遇到错误立即退出，未定义变量报错，管道错误传递

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

# 统一工作目录到脚本所在目录，避免相对路径错误
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

# 统一本地化，避免 perl/locale WARNING 干扰
export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}
export PATH="/usr/local/bin:${PATH}"

# 可选：开启彻底清理模式（CLEAN=1），在部署前移除历史安装/依赖
cleanup_previous_installation() {
	log_info "开始清理历史安装与依赖 (可通过设置 CLEAN=1 触发彻底清理)..."

	# 1) 关闭并清理 PM2 进程
	if command -v pm2 >/dev/null 2>&1; then
		log_info "停止 PM2 进程..."
		pm2 delete all >/dev/null 2>&1 || true
		pm2 kill >/dev/null 2>&1 || true
	fi

	# 2) 释放常用端口（8888/5050/27017）
	log_info "释放可能占用的端口 8888/5050/27017..."
	if command -v fuser >/dev/null 2>&1; then
		fuser -k 8888/tcp >/dev/null 2>&1 || true
		fuser -k 5050/tcp >/dev/null 2>&1 || true
		fuser -k 27017/tcp >/dev/null 2>&1 || true
	fi

	# 3) 停止服务（MongoDB / Redis）
	if systemctl list-unit-files | grep -q '^mongod\.service'; then
		log_info "停止 mongod 服务..."
		systemctl stop mongod >/dev/null 2>&1 || true
	fi
	if systemctl list-unit-files | grep -q '^redis-server\.service'; then
		log_info "停止 redis-server 服务..."
		systemctl stop redis-server >/dev/null 2>&1 || true
	fi

	# 4) 清理 Hydro 配置与沙箱（谨慎）
	log_info "清理 Hydro 本地配置与沙箱可执行文件..."
	rm -rf /root/.hydro >/dev/null 2>&1 || true
	rm -f /usr/bin/sandbox >/dev/null 2>&1 || true

	# 5) 可选：系统级依赖彻底清理（需设置 CLEAN=1）
	if [[ "${CLEAN:-0}" == "1" ]]; then
		log_warning "已启用 CLEAN=1，将彻底清理系统依赖（nodejs/mongodb/redis/pm2 等）"
		export DEBIAN_FRONTEND=noninteractive
		# 卸载 Node.js / 全局 PM2 / Yarn（若曾全局安装过）
		apt purge -y nodejs >/dev/null 2>&1 || true
		npm uninstall -g pm2 >/dev/null 2>&1 || true
		npm uninstall -g yarn >/dev/null 2>&1 || true

		# 卸载 MongoDB 及残留
		apt purge -y 'mongodb-org*' mongodb-database-tools mongodb-mongosh >/dev/null 2>&1 || true
		rm -rf /var/lib/mongo /var/log/mongodb >/dev/null 2>&1 || true
		rm -f /etc/apt/sources.list.d/mongodb-org-7.0.list >/dev/null 2>&1 || true
		rm -f /usr/share/keyrings/mongodb-server-7.0.gpg >/dev/null 2>&1 || true

		# 卸载 Redis 及残留
		apt purge -y redis-server >/dev/null 2>&1 || true
		rm -rf /var/lib/redis >/dev/null 2>&1 || true

		# 自动移除不再需要的包
		apt autoremove -y >/dev/null 2>&1 || true
		apt autoclean -y >/dev/null 2>&1 || true
	fi

	log_success "清理步骤完成"
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
            log_warning "检测到 $PRETTY_NAME，未测试的系统版本，将继续安装（可设置 FORCE=1 跳过提示）。"
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
        lsb-release unzip vim htop net-tools jq
    
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
    
    # 使用 corepack 管理 Yarn 版本（Yarn 4）
    log_info "配置 Yarn 4 (Berry) 环境..."
    corepack enable || true
    corepack prepare "yarn@4.9.1" --activate || true

    # 安装 PM2
    npm install -g pm2
    
    # 验证安装
    log_success "Node.js 安装完成，版本: $(node --version)"
    log_success "Yarn 安装完成，版本: $(yarn --version 2>/dev/null || echo '未检测到Yarn，稍后由corepack自动激活')"
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

    # 下载 go-judge（多候选 URL + 动态 API 获取）
    if [[ ! -f /usr/bin/sandbox ]]; then
        log_info "下载 Go-Judge 沙箱..."
        DOWNLOAD_OK=0
        URLS=""
        if command -v jq >/dev/null 2>&1; then
            URLS=$(curl -fsSL https://api.github.com/repos/criyle/go-judge/releases/latest \
                | jq -r '.assets[].browser_download_url' 2>/dev/null \
                | grep -E 'go-judge_.*linux_amd64' || true)
        fi
        if [[ -z "$URLS" ]]; then
            URLS=$(cat <<'EOF'
https://github.com/criyle/go-judge/releases/download/v1.9.4/go-judge_1.9.4_linux_amd64v3
https://github.com/criyle/go-judge/releases/download/v1.9.4/go-judge_1.9.4_linux_amd64v2
https://github.com/criyle/go-judge/releases/download/v1.9.4/go-judge_1.9.4_linux_amd64
https://github.com/criyle/go-judge/releases/download/v1.8.8/go-judge_1.8.8_linux_amd64
EOF
)
        fi
        for U in $URLS; do
            log_info "尝试下载: $U"
            if curl -fL "$U" -o /usr/bin/sandbox; then
                DOWNLOAD_OK=1
                break
            fi
        done
        if [[ "$DOWNLOAD_OK" != "1" ]]; then
            log_error "Go-Judge 下载失败，请检查网络或手动安装"
        fi
        chmod +x /usr/bin/sandbox || true
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
    # UI 构建可能内存占用较大，提高上限
    export NODE_OPTIONS=${NODE_OPTIONS:-"--max-old-space-size=8192"}
    if ! yarn --version >/dev/null 2>&1; then
        # 某些环境下需要重新激活 corepack
        corepack enable || true
        corepack prepare "yarn@4.9.1" --activate || true
    fi
    # 尽量使用可复现安装；若锁文件缺失或不兼容则回退
    yarn install --immutable || yarn install
    
    # 构建项目
    log_info "构建 TypeScript..."
    yarn build
    
    # 可通过环境变量强制跳过 UI 构建
    if [[ "${SKIP_UI_BUILD:-0}" == "1" ]]; then
        log_warning "已设置 SKIP_UI_BUILD=1，跳过前端 UI 构建"
    else
        # 若缺少 ui-default 的 build 脚本，则跳过构建，使用仓库内置静态资源
        if [[ ! -d "packages/ui-default/build" && ! -f "packages/ui-default/build/index.js" ]]; then
            log_warning "未检测到 packages/ui-default/build，跳过前端构建，使用仓库内置静态资源"
        else
            log_info "构建前端 UI..."
            # 依次尝试：生产（完整）→ 生产（跳过 iconfont）→ 标准 → 开发
            if ! yarn build:ui:production; then
                log_warning "build:ui:production 失败，尝试 build:ui:production:webpack（跳过 iconfont）"
                if ! yarn build:ui:production:webpack; then
                    log_warning "build:ui:production:webpack 失败，尝试 build:ui"
                    if ! yarn build:ui; then
                        log_warning "build:ui 失败，尝试开发构建 build:ui:dev"
                        yarn build:ui:dev || true
                    fi
                fi
            fi
        fi
    fi
    
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
    mkdir -p ~/.hydro
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
    su - judge -c "mkdir -p ~/.hydro" || true
    cp ~/.hydro/judge.yaml /home/judge/.hydro/
    chown judge:judge /home/judge/.hydro/judge.yaml || true
    
    log_success "服务配置完成"
}

# 启动服务
start_services() {
    log_info "第五阶段：启动服务..."
    
    # 停止可能存在的服务
    pm2 delete all 2>/dev/null || true
    
    # 安全设置：确保以项目根路径为工作目录启动，避免路径解析失败
    ROOT_DIR="$SCRIPT_DIR"
    # 启动 Hydro 主服务
    log_info "启动 Hydro 主服务..."
    pm2 start "$ROOT_DIR/packages/hydrooj/bin/hydrooj.js" --name hydro-main --update-env
    
    # 等待主服务启动
    sleep 10
    
    # 启动沙箱服务
    log_info "启动沙箱服务..."
    pm2 start ~/.hydro/start_sandbox.sh --name hydro-sandbox --update-env
    
    # 启动评测服务
    log_info "启动评测服务..."
    pm2 start "$ROOT_DIR/packages/hydrojudge/bin/hydrojudge.js" --name hydro-judge --update-env
    
    # 保存 PM2 配置并注册自启（systemd）
    pm2 save
    pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
    
    log_success "服务启动完成"
}

# 创建数据库用户
setup_database() {
    log_info "配置数据库用户..."
    
    # 等待服务完全启动
    sleep 15
    
    # 创建/更新 judge 用户（使用 sha256+salt 正确生成哈希）
    cat > /tmp/create_judge_user.js << 'EOF'
const crypto = require('crypto');
const password = 'judge123';
const salt = 'judgesalt123';
const hash = crypto.createHash('sha256').update(password + salt).digest('hex');
db.user.updateOne(
  { uname: 'judge' },
  { $set: {
      mail: 'judge@hydro.local',
      mailLower: 'judge@hydro.local',
      uname: 'judge',
      unameLower: 'judge',
      hash: hash,
      salt: salt,
      hashType: 'sha256',
      regat: new Date(),
      ip: ['127.0.0.1'],
      loginat: new Date(),
      loginip: '127.0.0.1',
      priv: 1,
      avatar: 'gravatar:judge@hydro.local'
  } },
  { upsert: true }
)
EOF
    # 执行数据库脚本
    node packages/hydrooj/bin/hydrooj.js db < /tmp/create_judge_user.js || true
    rm -f /tmp/create_judge_user.js
    
    # 重启服务应用配置
    pm2 restart all
    
    log_success "数据库配置完成"
}

# 安装题库插件
install_plugins() {
    log_info "第六阶段：安装题库插件..."
    # 确保 hydrooj CLI 可用（用于回退调用）
    if [[ ! -x /usr/local/bin/hydrooj ]]; then
        ln -sf "$SCRIPT_DIR/packages/hydrooj/bin/hydrooj.js" /usr/local/bin/hydrooj 2>/dev/null || true
        chmod +x /usr/local/bin/hydrooj 2>/dev/null || true
    fi
    export PATH="$SCRIPT_DIR/node_modules/.bin:$PATH"
    
    # 安装 hydroac-client 插件
    node packages/hydrooj/bin/hydrooj.js install https://hydro.ac/hydroac-client.zip || log_warning "插件安装可能失败，可后续手动安装"
    
    # 手动添加插件
    node packages/hydrooj/bin/hydrooj.js addon add '/root/.hydro/addons/hydroac-client' || \
        hydrooj addon add '/root/.hydro/addons/hydroac-client' || \
        log_warning "插件添加可能失败"
    
    # 重启主服务
    pm2 restart hydro-main
    
    log_success "插件安装完成"
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."
    
    # 检查服务状态
    pm2 status
    
    # 等待端口监听与 HTTP 可用（最多 60 秒）
    ATTEMPTS=0
    until [[ $ATTEMPTS -ge 30 ]]; do
        PORT_OK=0
        if command -v netstat >/dev/null 2>&1; then
            if netstat -tulpn | grep -q ":8888"; then PORT_OK=1; fi
        else
            PORT_OK=1
        fi

        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8888 || true)
        if [[ $PORT_OK -eq 1 && "$HTTP_CODE" =~ ^(200|204|301|302|304|401|403)$ ]]; then
            log_success "Web 服务已就绪 (端口:OK, HTTP:$HTTP_CODE)"
            break
        fi
        ATTEMPTS=$((ATTEMPTS+1))
        sleep 2
    done

    if [[ $ATTEMPTS -ge 30 ]]; then
        log_warning "Web 服务健康检查未通过，但进程可能已在线。请使用 pm2 logs hydro-main 检查详情。"
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
    
    # 可选彻底清理：设置环境变量 CLEAN=1 将触发
    cleanup_previous_installation

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
