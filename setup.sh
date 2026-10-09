#!/usr/bin/env bash
# ============================================================
#  Middleware Stack · one-command bootstrap
#  Bootstraps 13 middleware services (MySQL / PostgreSQL / MongoDB /
#  Redis / Nginx / Tomcat / ZooKeeper / Kafka / RabbitMQ /
#  Elasticsearch / Keepalived / Prometheus / Grafana).
#  MinIO is optional (enable via: docker compose --profile extra up -d minio).
#
#  Usage:
#    bash setup.sh          # self-check + start all default services
#    bash setup.sh check    # environment check only
#    bash setup.sh backup   # MySQL dump + Redis persistence check
#    bash setup.sh down     # stop and remove containers
# ============================================================
set -euo pipefail

# ---------- 颜色 ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

cd "$(dirname "$0")"

# ---------- 1. 检查是否在 WSL / Linux ----------
if ! grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
  warn "未检测到 WSL 环境，继续尝试（原生 Linux 亦可）"
fi

# ---------- 2. 检查并尝试安装 Docker ----------
if ! command -v docker >/dev/null 2>&1; then
  warn "未检测到 docker，尝试自动安装 docker-ce ..."
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  $SUDO apt-get update -y
  $SUDO apt-get install -y ca-certificates curl gnupg
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
    | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null \
    || curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
         | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu ${VERSION_CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO systemctl enable --now docker 2>/dev/null || true
  info "docker 安装完成"
fi

# ---------- 3. 检查 docker 服务是否可用 ----------
if ! docker info >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  warn "docker 守护进程未运行或权限不足，尝试启动 ..."
  $SUDO systemctl start docker 2>/dev/null || $SUDO service docker start 2>/dev/null || true
  # 把当前用户加入 docker 组（免 sudo）
  $SUDO usermod -aG docker "$(whoami)" 2>/dev/null || true
  sleep 2
  if ! docker info >/dev/null 2>&1; then
    warn "docker 仍不可用。若刚加入 docker 组，请执行 'newgrp docker' 或重开终端后重跑本脚本。"
    exit 1
  fi
fi

# ---------- 4. 配置国内镜像加速（幂等） ----------
DOCKER_DAEMON=/etc/docker/daemon.json
if [ ! -f "$DOCKER_DAEMON" ] || ! grep -q "registry-mirrors" "$DOCKER_DAEMON" 2>/dev/null; then
  warn "写入镜像加速源到 $DOCKER_DAEMON ..."
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  $SUDO mkdir -p /etc/docker
  echo '{
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://hub.rat.dev"
  ]
}' | $SUDO tee "$DOCKER_DAEMON" >/dev/null
  $SUDO systemctl restart docker 2>/dev/null || $SUDO service docker restart 2>/dev/null || true
  sleep 3
fi

# ---------- 5. 检查 docker compose ----------
if ! docker compose version >/dev/null 2>&1; then
  fail "未检测到 docker compose 插件，请先执行: sudo apt-get install -y docker-compose-plugin"
fi

# ---------- 6. 镜像拉取（带加速源兜底） ----------
info "开始拉取镜像 ..."
pull_with_fallback() {
  local image="$1"            # 例如 apache/kafka:3.7.0
  local retag="$2"            # 标准名（与 compose 一致）
  local name="${image%%:*}"   # apache/kafka
  local tag="${image##*:}"    # 3.7.0
  # 先直接拉
  if docker pull "$image" >/dev/null 2>&1; then
    docker tag "$image" "$retag" >/dev/null 2>&1 || true
    info "OK  $image"
    return 0
  fi
  # 逐个加速源兜底（quay.io 为 MinIO 等镜像的官方备用发布地）
  for mirror in docker.1panel.live docker.m.daocloud.io docker.1ms.run hub.rat.dev quay.io; do
    if docker pull "$mirror/$image" >/dev/null 2>&1; then
      docker tag "$mirror/$image" "$retag"
      info "OK  $image  (via $mirror)"
      return 0
    fi
  done
  warn "拉取失败（已尝试直连+3个加速源）: $image"
  return 1
}

IMAGES=(
  "mysql:8.0"
  "postgres:16"
  "mongo:7"
  "redis:7"
  "nginx:1.27"
  "tomcat:9-jdk17"
  "zookeeper:3.8"
  "apache/kafka:3.7.0"
  "rabbitmq:3.13-management"
  "elasticsearch:8.13.0"
  "osixia/keepalived:2.0.20"
  "prom/prometheus:v2.51.0"
  "grafana/grafana:10.4.0"
)
FAILED=0
for img in "${IMAGES[@]}"; do
  pull_with_fallback "$img" "$img" || FAILED=1
done
if [ "$FAILED" -eq 1 ]; then
  warn "部分镜像拉取失败，已记录失败项（见上方日志）。"
  warn "通常为镜像源临时不可用，可稍后重试，或手动执行:"
  warn "  docker pull <镜像名>  (直连 Docker Hub)"
fi

# ---------- 7. 按模式分发 ----------
case "${1:-}" in
  check)
    info "环境检查通过。"
    exit 0
    ;;
  backup)
    info "执行备份与持久化验证 ..."
    ;;
  down)
    docker compose down
    info "已停止并清理容器（数据卷保留）。"
    exit 0
    ;;
  *)
    ;;
esac

# ---------- 8. 启动 ----------
info "启动默认服务 (13 个) ..."
docker compose up -d
sleep 3
docker compose ps
info "启动完成。各服务访问入口见 README.txt。"
info "MinIO 为可选组件，按需启用: docker compose --profile extra up -d minio"

# ---------- 9. 备份/持久化验证（backup 模式） ----------
if [ "${1:-}" = "backup" ]; then
  TS=$(date +%Y%m%d_%H%M%S)
  mkdir -p backups
  # MySQL 逻辑备份
  docker exec mysql sh -c 'mysqldump -uroot -proot123456 demo' > "backups/mysql_demo_${TS}.sql" 2>/dev/null \
    && info "MySQL 备份 -> backups/mysql_demo_${TS}.sql" \
    || warn "MySQL 备份失败（容器是否已就绪？）"
  # Redis 持久化验证：写一个 key -> 重启 -> 读回
  docker exec redis redis-cli -a redis123 SET persist_test "ok" >/dev/null 2>&1 || true
  docker restart redis >/dev/null 2>&1
  sleep 3
  VAL=$(docker exec redis redis-cli -a redis123 GET persist_test 2>/dev/null | tr -d '\r')
  if [ "$VAL" = "ok" ]; then
    info "Redis 持久化验证通过（重启后数据仍在）"
  else
    warn "Redis 持久化验证未通过，请检查 redis.conf 的 appendonly 设置"
  fi
fi

info "全部完成。"
