#! /usr/bin/env bash
set -euo pipefail

# -------- 基本配置（可改） --------
PROJECT_NAME="lightrag-backend"
PROFILE_NAME="run"
COMPOSE_FILES=("infra.compose.yml" "base.compose.yml" "./biz/strategy.compose.yml" "./biz/app.compose.yml" "./biz/gas.compose.yml")
PG_SERVICE_NAMES=("postgres" "lightrag-postgres")
NEO4J_SERVICE_NAMES=("neo4j" "lightrag-neo4j")
VOLUMES=("lightrag_pg_data" "lightrag_neo4j_data" "lightrag_inputs" "lightrag_storage")
BASE_DIR_DEFAULT="/home/chrpue/projects/knowledge"
# 所有可能运行的容器名列表，用于强制清理
ALL_CONTAINER_NAMES=(
    "lightrag-postgres" "lightrag-neo4j"
    "lightrag-app" "lightrag-mcp-app-server"
    "lightrag-gas" "lightrag-mcp-gas-server"
    "lightrag-strategy" "lightrag-mcp-strategy-server"
)
# ---------------------------------

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "缺少命令: $1"; exit 1; }; }
need_cmd docker
docker compose version >/dev/null 2>&1 || { echo "需要 Docker Compose v2"; exit 1; }

SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
[[ -n "$SUDO" ]] && $SUDO -v || true

# --- 彩色输出与格式化工具 ---
if tput setaf 8 >/dev/null 2>&1; then
  GREEN="$(tput setaf 2)"; GRAY="$(tput setaf 8)"; RED="$(tput setaf 1)"; RESET="$(tput sgr0)"
else
  GREEN=$'[32m'; GRAY=$'[90m'; RED=$'[31m'; RESET=$'[0m'
fi
INDENT="  " # 统一的缩进字符串

# 基础输出函数
info(){ printf "\n%b>>> %s%b\n" "$GREEN" "$1" "$RESET"; }
say(){  printf "%s\n" "$1"; }
ask(){  printf "%b%s%b" "$GRAY" "$1" "$RESET"; }
ok(){   printf "%b✓ %s%b\n" "$GREEN" "$1" "$RESET"; }
fail(){ printf "%b✕ %s%b\n" "$RED"   "$1" "$RESET"; }

# 带缩进的输出函数
say_i(){  printf "%s%s\n" "$INDENT" "$1"; }
ask_i(){  printf "%s%b%s%b" "$INDENT" "$GRAY" "$1" "$RESET"; }
ok_i(){   printf "%s%b✓ %s%b\n" "$INDENT" "$GREEN" "$1" "$RESET"; }
fail_i(){ printf "%s%b✕ %s%b\n" "$INDENT" "$RED"   "$1" "$RESET"; }


# ---- 安全护栏：只允许清空 .../lightrag 根 ----
guard_lightrag_root(){ [[ "$1" == */lightrag ]] || { fail_i "安全检查失败：$1 不是以 /lightrag 结尾"; exit 1; }; }

# ---- 以当前用户创建/接管目录（必要时 sudo） ----
ensure_dir_owned(){
  local d="$1" uid gid
  uid="$(id -u)"; gid="$(id -g)"
  if [[ -d "$d" ]]; then
    [[ -w "$d" ]] || { [[ -n "$SUDO" ]] && $SUDO chown -R "$uid:$gid" "$d"; }
  else
    install -d -m 0755 -o "$uid" -g "$gid" "$d" 2>/dev/null || $SUDO install -d -m 0755 -o "$uid" -g "$gid" "$d"
  fi
}

# ---- compose down/up ----
compose_down(){
  pushd "$COMPOSE_DIR" >/dev/null
  local args=(); for f in "${COMPOSE_FILES[@]}"; do args+=(-f "$f"); done
  docker compose -p "$PROJECT_NAME" "${args[@]}" down --remove-orphans -t 0 2>/dev/null || true
  popd >/dev/null
}
compose_up(){
  pushd "$COMPOSE_DIR" >/dev/null
  local args=(); for f in "${COMPOSE_FILES[@]}"; do args+=(-f "$f"); done
  docker compose --profile "$PROFILE_NAME" -p "$PROJECT_NAME" "${args[@]}" up -d --build --force-recreate
  popd >/dev/null
}

# 获取容器 ID
get_cid_by_names(){
  local name cid
  for name in "$@"; do
    cid="$(docker compose -p "$PROJECT_NAME" ps -q "$name" 2>/dev/null || true)"
    [[ -n "$cid" ]] && { echo "$cid"; return; }
  done
  for name in "$@"; do
    cid="$(docker ps --filter "name=$name" -q | head -n1)"
    [[ -n "$cid" ]] && { echo "$cid"; return; }
  done
  echo ""
}

# =========== 主流程 ===========
COMPOSE_DIR="${PWD}"

# 1) 基准目录输入
info "步骤 1: 设置 LightRAG 基准目录"
# 使用 read -e -i 实现单行可编辑输入
ask_i "请输入项目根目录 (回车使用默认): "
read -r -e -i "${BASE_DIR_DEFAULT}" BASE_DIR
[[ -z "${BASE_DIR}" ]] && BASE_DIR="${BASE_DIR_DEFAULT}"

BASE_DIR="${BASE_DIR%/}"
LR_ROOT="${BASE_DIR}/lightrag"
LR_PG="${LR_ROOT}/pg_data"
LR_NEO4J="${LR_ROOT}/neo4j"
LR_INPUTS="${LR_ROOT}/inputs"
LR_STORAGE="${LR_ROOT}/storage"

# 2) 目录确认与清理
info "步骤 2: 确认目录结构与数据清理"
say_i "以下目录将被用于存储 LightRAG 数据："
printf "%s  [Postgres 数据库]: %s\n" "$INDENT" "${LR_PG}"
printf "%s  [Neo4j    数据库]: %s\n" "$INDENT" "${LR_NEO4J}"
printf "%s  [Inputs   文档]:   %s\n" "$INDENT" "${LR_INPUTS}"
printf "%s  [Storage  存储]:   %s\n" "$INDENT" "${LR_STORAGE}"
ask_i "确认使用以上目录吗？ (y/N) "
read -r yn
[[ "$yn" =~ ^[yY]$ ]] || { say_i "操作已取消。"; exit 0; }

# 已存在时，二次确认删除
if [[ -d "$LR_ROOT" ]] || [[ -d "$LR_PG" ]] || [[ -d "$LR_NEO4J" ]] || [[ -d "$LR_INPUTS" ]] || [[ -d "$LR_STORAGE" ]]; then
  ask_i "检测到 ${LR_ROOT} 已存在。是否清空并重建？ (y/N) "
  read -r wipe
  if [[ "$wipe" =~ ^[yY]$ ]]; then
    ask_i "为防误删，请输入 ${RED}DELETE${GRAY} 确认（其他任意键取消）："
    read -r del2
    if [[ "$del2" == "DELETE" ]]; then
      guard_lightrag_root "$LR_ROOT"
      say_i "正在停止相关容器..."
      compose_down
      say_i "正在清空目录 ${LR_ROOT} ..."
      command -v chattr >/dev/null 2>&1 && $SUDO chattr -R -i "$LR_ROOT" 2>/dev/null || true
      if $SUDO rm -rf -- "$LR_ROOT"; then
        ok_i "已成功清空 ${LR_ROOT}"
      else
        fail_i "清空 ${LR_ROOT} 失败"; exit 1
      fi
    else
      say_i "未输入 DELETE，保留原数据。"
    fi
  fi
fi

# 3) 创建目录并归当前用户
info "步骤 3: 准备本地目录"
ensure_dir_owned "$LR_ROOT"
ensure_dir_owned "$LR_PG"
ensure_dir_owned "$LR_NEO4J"
ensure_dir_owned "$LR_INPUTS"
ensure_dir_owned "$LR_STORAGE"
ok_i "所有本地数据目录均已准备就绪。"

# 4) 卷：一次选择是否重建
info "步骤 4: 处理 Docker 卷"
ask_i "若 Docker 卷已存在，是否删除并重建？ (y/N) "
read -r wipev
if [[ "$wipev" =~ ^[yY]$ ]]; then
  say_i "正在停止并移除所有相关容器以释放卷..."
  for c in "${ALL_CONTAINER_NAMES[@]}"; do
      docker stop "$c" >/dev/null 2>&1 || true
      docker rm "$c" >/dev/null 2>&1 || true
  done
  ok_i "相关容器已清理。"
  
  for v in "${VOLUMES[@]}"; do
    if docker volume inspect "$v" >/dev/null 2>&1; then
        if docker volume rm "$v" >/dev/null; then
            ok_i "旧卷已删除: $v"
        else
            fail_i "无法删除卷: $v。请手动运行 'docker ps -a' 检查并用 'docker rm -f <容器ID>' 清理。"
        fi
    fi
    docker volume create "$v" >/dev/null
    ok_i "卷已就绪: $v"
  done
else
  for v in "${VOLUMES[@]}"; do
    if docker volume inspect "$v" >/dev/null 2>&1; then
      say_i "保留现有卷：$v"
    else
      docker volume create "$v" >/dev/null
      ok_i "成功创建卷：$v"
    fi
  done
fi

# 5) 启动 LightRAG Compose 堆栈
info "步骤 5: 启动 LightRAG 服务"
say_i "正在使用 Docker Compose 启动所有服务，请稍候..."
compose_up

# 6) 修正数据存储权限
info "步骤 6: 同步并修正数据权限"

# Postgres
PG_CID="$(get_cid_by_names "${PG_SERVICE_NAMES[@]}")"
if [[ -n "$PG_CID" ]]; then
  PG_UID="$(docker exec "$PG_CID" sh -lc 'id -u postgres' 2>/dev/null || true)"
  PG_GID="$(docker exec "$PG_CID" sh -lc 'id -g postgres' 2>/dev/null || true)"
  if [[ "$PG_UID" =~ ^[0-9]+$ && "$PG_GID" =~ ^[0-9]+$ ]]; then
    if $SUDO chown -R "$PG_UID:$PG_GID" "$LR_PG" && $SUDO chmod 700 "$LR_PG"; then
      ok_i "Postgres -> ${LR_PG} 权限已设为 ${PG_UID}:${PG_GID} (700)"
    else
      fail_i "Postgres -> ${LR_PG} 权限修正失败"
    fi
  else
    fail_i "未能获取 Postgres 容器内的用户 UID/GID"
  fi
else
  fail_i "未找到 Postgres 容器（尝试名称：${PG_SERVICE_NAMES[*]}）"
fi

# Neo4j
NEO_CID="$(get_cid_by_names "${NEO4J_SERVICE_NAMES[@]}")"
if [[ -n "$NEO_CID" ]]; then
  NEO_UIDGID="$(docker exec "$NEO_CID" sh -lc "stat -c '%u:%g' /data" 2>/dev/null || true)"
  if [[ "$NEO_UIDGID" =~ ^[0-9]+:[0-9]+$ ]]; then
    if $SUDO chown -R "$NEO_UIDGID" "$LR_NEO4J" && $SUDO chmod 750 "$LR_NEO4J"; then
      ok_i "Neo4j -> ${LR_NEO4J} 权限已设为 ${NEO_UIDGID} (750)"
    else
      fail_i "Neo4j -> ${LR_NEO4J} 权限修正失败"
    fi
  else
    fail_i "未能获取 Neo4j 容器的 /data 目录 UID:GID"
  fi
else
  fail_i "未找到 Neo4j 容器（尝试名称：${NEO4J_SERVICE_NAMES[*]}）"
fi

# inputs / storage
MY_UID="$(id -u)"; MY_GID="$(id -g)"
if $SUDO chown -R "$MY_UID:$MY_GID" "$LR_INPUTS" "$LR_STORAGE" && chmod -R u+rwX,go-rwx "$LR_INPUTS" "$LR_STORAGE"; then
  ok_i "Inputs/Storage -> 目录权限已归属当前用户"
else
  fail_i "Inputs/Storage -> 目录权限修正失败"
fi

info "部署完成"
say_i "根目录: ${LR_ROOT}"
say_i "项目名: ${PROJECT_NAME}"
say_i "Profile: ${PROFILE_NAME}"






