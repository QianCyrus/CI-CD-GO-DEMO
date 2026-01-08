#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[%s] %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

# --- config (通过环境变量可覆盖) ---
APP_NAME="${APP_NAME:-cicd-go-demo}"
# 默认用用户目录，避免强依赖 sudo；如需统一放到 /opt，可在环境变量覆盖：STATE_DIR=/opt/<app>
STATE_DIR="${STATE_DIR:-${HOME:-/opt}/${APP_NAME}}"
STATE_SUBDIR="${STATE_SUBDIR:-state}"
NETWORK="${NETWORK:-${APP_NAME}-net}"

APP_PORT="${APP_PORT:-8080}"       # app 容器内部端口
PUBLIC_PORT="${PUBLIC_PORT:-80}"   # nginx 对外端口
HEALTH_PATH="${HEALTH_PATH:-/healthz}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-30}"

NGINX_IMAGE="${NGINX_IMAGE:-nginx:1.27-alpine}"
NGINX_CONTAINER="${NGINX_CONTAINER:-${APP_NAME}-nginx}"

ACTION="${ACTION:-deploy}" # deploy | rollback | status

# deploy/rollback 时需要
IMAGE="${IMAGE:-}"

# 服务器拉取 GHCR 镜像用（可选；若镜像公开可不填）
GHCR_USERNAME="${GHCR_USERNAME:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"

STATE_PATH="${STATE_DIR}/${STATE_SUBDIR}"
CURRENT_COLOR_FILE="${STATE_PATH}/current_color"
CURRENT_IMAGE_FILE="${STATE_PATH}/current_image"
PREVIOUS_IMAGE_FILE="${STATE_PATH}/previous_image"

NGINX_CONF_DIR="${STATE_DIR}/nginx/conf.d"
NGINX_CONF_FILE="${NGINX_CONF_DIR}/default.conf"

current_color() {
  if [[ -f "$CURRENT_COLOR_FILE" ]]; then
    cat "$CURRENT_COLOR_FILE"
  else
    echo ""
  fi
}

idle_color() {
  local cur
  cur="$(current_color)"
  if [[ "$cur" == "blue" ]]; then
    echo "green"
  elif [[ "$cur" == "green" ]]; then
    echo "blue"
  else
    echo "blue"
  fi
}

current_image() {
  if [[ -f "$CURRENT_IMAGE_FILE" ]]; then
    cat "$CURRENT_IMAGE_FILE"
  else
    echo ""
  fi
}

previous_image() {
  if [[ -f "$PREVIOUS_IMAGE_FILE" ]]; then
    cat "$PREVIOUS_IMAGE_FILE"
  else
    echo ""
  fi
}

ensure_dirs() {
  mkdir -p "$STATE_PATH" "$NGINX_CONF_DIR"
}

ensure_network() {
  if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    log "create docker network: $NETWORK"
    docker network create "$NETWORK" >/dev/null
  fi
}

write_nginx_conf() {
  local color="$1"
  cat >"$NGINX_CONF_FILE" <<EOF
upstream ${APP_NAME}_upstream {
  server ${APP_NAME}-${color}:${APP_PORT};
  keepalive 32;
}

server {
  listen ${PUBLIC_PORT};
  server_name _;

  location / {
    proxy_pass http://${APP_NAME}_upstream;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout 30s;
    proxy_send_timeout 30s;
  }
}
EOF
}

ensure_nginx_running() {
  if docker ps --format '{{.Names}}' | grep -qx "$NGINX_CONTAINER"; then
    return 0
  fi

  if docker container inspect "$NGINX_CONTAINER" >/dev/null 2>&1; then
    log "start existing nginx container: $NGINX_CONTAINER"
    docker start "$NGINX_CONTAINER" >/dev/null
    return 0
  fi

  log "run nginx container: $NGINX_CONTAINER"
  docker run -d \
    --name "$NGINX_CONTAINER" \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p "${PUBLIC_PORT}:${PUBLIC_PORT}" \
    -v "${NGINX_CONF_DIR}:/etc/nginx/conf.d:ro" \
    "$NGINX_IMAGE" >/dev/null
}

nginx_reload() {
  ensure_nginx_running
  docker exec "$NGINX_CONTAINER" nginx -s reload >/dev/null
}

docker_login_ghcr_if_needed() {
  if [[ -n "$GHCR_USERNAME" && -n "$GHCR_TOKEN" ]]; then
    log "docker login ghcr.io (username=${GHCR_USERNAME})"
    printf "%s" "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin >/dev/null
    return 0
  fi
  return 1
}

docker_logout_ghcr_if_logged_in() {
  docker logout ghcr.io >/dev/null 2>&1 || true
}

run_app_container() {
  local color="$1"
  local image="$2"
  local name="${APP_NAME}-${color}"

  # 先删再起，避免名字冲突
  docker rm -f "$name" >/dev/null 2>&1 || true

  log "run app container: name=${name} image=${image}"
  docker run -d \
    --name "$name" \
    --restart unless-stopped \
    --network "$NETWORK" \
    -e "PORT=${APP_PORT}" \
    "$image" >/dev/null
}

wait_healthz() {
  local color="$1"
  local url="http://${APP_NAME}-${color}:${APP_PORT}${HEALTH_PATH}"

  log "healthcheck: ${url} (timeout=${HEALTH_TIMEOUT_SEC}s)"
  local start now
  start="$(date +%s)"

  while true; do
    if docker run --rm --network "$NETWORK" curlimages/curl:8.8.0 -fsS "$url" >/dev/null 2>&1; then
      log "healthcheck OK"
      return 0
    fi

    now="$(date +%s)"
    if (( now - start >= HEALTH_TIMEOUT_SEC )); then
      return 1
    fi
    sleep 1
  done
}

remove_container_if_exists() {
  local name="$1"
  docker rm -f "$name" >/dev/null 2>&1 || true
}

deploy_image() {
  local target_image="$1"

  [[ -n "$target_image" ]] || die "IMAGE is required for deploy"

  ensure_dirs
  ensure_network

  local cur_color idle cur_image logged_in
  cur_color="$(current_color)"
  idle="$(idle_color)"
  cur_image="$(current_image)"

  logged_in="false"
  if docker_login_ghcr_if_needed; then
    logged_in="true"
  fi

  log "docker pull: ${target_image}"
  docker pull "$target_image" >/dev/null

  run_app_container "$idle" "$target_image"

  if ! wait_healthz "$idle"; then
    log "healthcheck FAILED, keep traffic on old version"
    log "container logs (tail): ${APP_NAME}-${idle}"
    docker logs --tail 200 "${APP_NAME}-${idle}" || true
    die "deploy aborted due to failed healthcheck"
  fi

  log "switch traffic to: ${idle}"
  write_nginx_conf "$idle"
  nginx_reload

  # 切流量后再清理旧容器（零宕机关键点）
  if [[ -n "$cur_color" ]]; then
    log "remove old container: ${APP_NAME}-${cur_color}"
    remove_container_if_exists "${APP_NAME}-${cur_color}"
  fi

  # 更新状态文件（用于回滚）
  if [[ -n "$cur_image" && "$cur_image" != "$target_image" ]]; then
    echo "$cur_image" >"$PREVIOUS_IMAGE_FILE"
  fi
  echo "$target_image" >"$CURRENT_IMAGE_FILE"
  echo "$idle" >"$CURRENT_COLOR_FILE"

  if [[ "$logged_in" == "true" ]]; then
    docker_logout_ghcr_if_logged_in
  fi

  log "deploy done: color=${idle} image=${target_image}"
}

rollback() {
  ensure_dirs

  local prev cur
  prev="$(previous_image)"
  cur="$(current_image)"

  [[ -n "$prev" ]] || die "no previous_image recorded yet, cannot rollback"

  log "rollback: current=${cur} -> previous=${prev}"
  deploy_image "$prev"
}

status() {
  ensure_dirs
  cat <<EOF
app_name=${APP_NAME}
network=${NETWORK}
nginx_container=${NGINX_CONTAINER}
current_color=$(current_color)
current_image=$(current_image)
previous_image=$(previous_image)
EOF
}

main() {
  require_cmd docker

  case "$ACTION" in
    deploy)
      deploy_image "$IMAGE"
      ;;
    rollback)
      rollback
      ;;
    status)
      status
      ;;
    *)
      die "unknown ACTION: $ACTION (expected deploy|rollback|status)"
      ;;
  esac
}

main "$@"

