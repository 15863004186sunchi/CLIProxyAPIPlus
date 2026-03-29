#!/bin/bash

# CLIProxyAPIPlus - Management Script
# Usage: ./manage.sh [start|stop|restart|logs|update|status]

PROJECT_DIR="/opt/cli-proxy"
DOCKER_COMPOSE="docker-compose"

# 检查是否在项目目录
if [ ! -f "docker-compose.yml" ]; then
    if [ -d "$PROJECT_DIR" ]; then
        cd "$PROJECT_DIR" || exit 1
    else
        echo "错误: 未找到项目目录 $PROJECT_DIR 或 docker-compose.yml"
        exit 1
    fi
fi

case "$1" in
    start)
        echo "正在启动 CLIProxyAPIPlus..."
        $DOCKER_COMPOSE up -d
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
        echo "正在拉取最新镜像并更新..."
        $DOCKER_COMPOSE pull
        $DOCKER_COMPOSE up -d
        echo "更新完成。"
        ;;
    status)
        $DOCKER_COMPOSE ps
        ;;
    *)
        echo "使用方法: $0 {start|stop|restart|logs|update|status}"
        exit 1
        ;;
esac
