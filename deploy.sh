#!/bin/bash

# CLIProxyAPIPlus - Deployment Script (Centos 10 / Docker)
# This script is idempotent and handles initial setup and updates.

set -e

PROJECT_DIR="/opt/cli-proxy"
SOURCE_DIR="$PROJECT_DIR/source"
CONFIG_FILE="$PROJECT_DIR/config.yaml"
# 用户 Fork 的仓库地址
FORK_REPO="https://github.com/15863004186sunchi/CLIProxyAPIPlus"
# 使用本地构建的镜像名称
DOCKER_IMAGE="cli-proxy-custom:latest"

# 1. 基础环境检查与依赖安装
echo "正在检查并安装基础依赖 (git, openssl, yum-utils, net-tools)..."
yum install -y git openssl yum-utils net-tools || echo "部分依赖安装失败，尝试继续..."

if ! command -v docker &> /dev/null; then
    echo "正在安装 Docker..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
    systemctl start docker
    systemctl enable docker
fi

if ! command -v docker-compose &> /dev/null; then
    echo "正在安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 1.5 从 Fork 仓库获取源码并构建镜像
echo "正在从 Fork 仓库同步源码: $FORK_REPO"
mkdir -p "$SOURCE_DIR"
if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "首次克隆仓库..."
    git clone "$FORK_REPO" "$SOURCE_DIR"
else
    echo "提取最新代码..."
    cd "$SOURCE_DIR" && git pull
fi

echo "正在构建自定义镜像 (包含最新 uTLS/特征伪装) 此步骤可能需要几分钟..."
cd "$SOURCE_DIR"
docker build -t "$DOCKER_IMAGE" .
cd "$PROJECT_DIR"

# 2. 解决端口冲突与清理已知冲突容器
echo "正在清理冲突容器..."
# 停止所有可能占用 8317 的容器
CONFLICT_CONTAINERS=$(docker ps -a --filter "publish=8317" --format '{{.Names}}')
if [ ! -z "$CONFLICT_CONTAINERS" ]; then
    echo "发现占用 8317 端口的容器: $CONFLICT_CONTAINERS，正在清理..."
    docker stop $CONFLICT_CONTAINERS || true
    docker rm $CONFLICT_CONTAINERS || true
fi

# 针对特定名字的清理 (兼容旧版本)
for name in "cli-proxy-api-plus" "cli-proxy"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^$name$"; then
        echo "清理容器: $name..."
        docker stop $name || true
        docker rm $name || true
    fi
done

# 再次检查 8317 端口占用情况 (由于 Docker 映射，可能在主机上看不到具体进程，但 docker stop 已解决大部分)
PID=$(netstat -tunlp | grep ":8317 " | awk '{print $7}' | cut -d'/' -f1 || true)
if [ ! -z "$PID" ] && [ "$PID" != "-" ]; then
    echo "发现端口 8317 被进程 $PID 占用，正在尝试强制关闭..."
    kill -9 "$PID" || true
fi

# 3. 创建目录并预设权限
echo "创建项目目录及数据目录..."
mkdir -p "$PROJECT_DIR/auths" "$PROJECT_DIR/logs"
chmod -R 777 "$PROJECT_DIR/auths" "$PROJECT_DIR/logs"
cd "$PROJECT_DIR"

# 4. 生成管理脚本 manage.sh
cat << 'EOF' > manage.sh
#!/bin/bash
# CLIProxyAPIPlus - Management Script
# Usage: ./manage.sh [start|stop|restart|logs|update|status]

PROJECT_DIR="/opt/cli-proxy"
DOCKER_COMPOSE="docker-compose"

cd "$PROJECT_DIR" || exit 1

case "$1" in
    start)
        echo "正在启动 CLIProxyAPIPlus..."
        $DOCKER_COMPOSE up -d --remove-orphans
        ;;
    stop)
        echo "正在停止 CLIProxyAPIPlus..."
        $DOCKER_COMPOSE down
        ;;
    restart)
        echo "正在重启 CLIProxyAPIPlus..."
        $DOCKER_COMPOSE restart
        ;;
    logs)
        echo "正在查看日志... (Ctrl+C 退出)"
        $DOCKER_COMPOSE logs -f
        ;;
    update)
        echo "正在从 Fork 仓库获取最新源码并重新构建..."
        # 直接运行 deploy.sh 即可完成源码更新、构建与重启
        bash "$PROJECT_DIR/deploy.sh"
        echo "更新并重新构建完成。"
        ;;
    status)
        $DOCKER_COMPOSE ps
        ;;
    *)
        echo "使用方法: $0 {start|stop|restart|logs|update|status}"
        exit 1
        ;;
esac
EOF
chmod +x manage.sh

# 5. 初始化配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo "初始化配置文件..."
    PASSWORD="sunchi" # 尊重用户之前的习惯
    
    cat <<EOF > "$CONFIG_FILE"
# CLIProxyAPIPlus Configuration
# Server port
port: 8317

# Global Proxy (Residential Proxy for Evasion)
proxy-url: "http://nenuncxc:ufpi8flnz6uh@9.142.41.22:6192/"

# Remote Management (Required for browser access)
remote-management:
  allow-remote: true
  secret-key: "$PASSWORD"

# Authentication directory
auth-dir: "/root/.cli-proxy-api"

# AI Service Providers
# You can add credentials here or via management UI
gemini-api-key: []
claude-api-key: []
codex-api-key: []
openai-compatibility: []

# Debug settings
debug: false
EOF
    echo "======================================"
    echo "配置文件已生成: $CONFIG_FILE"
    echo "管理后台初始密码: $PASSWORD"
    echo "住宅代理已配置: 9.142.41.22:6192"
    echo "======================================"
else
    # 强制更新已有的 proxy-url (如果存在)
    if grep -q "proxy-url:" "$CONFIG_FILE"; then
        sed -i 's|proxy-url:.*|proxy-url: "http://nenuncxc:ufpi8flnz6uh@9.142.41.22:6192/"|' "$CONFIG_FILE"
    else
        # 否则插入到第二行
        sed -i '2i\proxy-url: "http://nenuncxc:ufpi8flnz6uh@9.142.41.22:6192/"' "$CONFIG_FILE"
    fi
    echo "已成功将住宅代理写入现有配置: $CONFIG_FILE"
    # 强制修正已有配置的结构（如果发现 server: 这种错误嵌套）
    if grep -q "server:" "$CONFIG_FILE"; then
        echo "发现旧版错误配置结构，正在重置为正确格式..."
        PASSWORD="sunchi"
        cat <<EOF > "$CONFIG_FILE"
port: 8317
remote-management:
  allow-remote: true
  secret-key: "$PASSWORD"
auth-dir: "/root/.cli-proxy-api"
gemini-api-key: []
claude-api-key: []
codex-api-key: []
openai-compatibility: []
EOF
    fi
fi

# 6. 生成 docker-compose.yml
# 移除 obsolete version 标签
cat <<EOF > docker-compose.yml
services:
  cli-proxy:
    image: $DOCKER_IMAGE
    container_name: cli-proxy
    restart: always
    ports:
      - "8317:8317"
      - "8085:8085"
    volumes:
      - ./config.yaml:/CLIProxyAPI/config.yaml
      - ./auths:/root/.cli-proxy-api
      - ./logs:/CLIProxyAPI/logs
    environment:
      - TZ=Asia/Shanghai
EOF

# 7. 启动服务
echo "使用本地构建的镜像启动服务..."
# 确保先停止可能冲突的编排
docker-compose down || true
docker-compose up -d --remove-orphans

echo "部署成功！"
echo "你可以通过命令 cd $PROJECT_DIR && ./manage.sh logs 查看运行情况。"
