#!/bin/bash
# ============================================================================
# ORESHNIK EXEC — KALI-ИСПОЛНИТЕЛЬ (Podman-лаборатория)
# ============================================================================
set -e

SHARED_BASE="$HOME/BB/CORE-SWIGGER/oreshnik"
TASKS_DIR="$SHARED_BASE/tasks"
RESULTS_DIR="$SHARED_BASE/results"
SYNC_DIR="$SHARED_BASE/sync"

TMP_DIR="/dev/shm/oreshnik_exec_$$"
CONTAINER_PREFIX="oreshnik_lab"
PODMAN_BIN="$(command -v podman 2>/dev/null || echo '')"
SLEEP_INTERVAL=3

HOST_USER="azar"
HOST_IP="172.25.144.219"
HOST_PATH="/home/azar/AI DevOps Mentor/shared/oreshnik"

# -------------------------- МОНТИРОВАНИЕ -------------------------------
if ! command -v sshfs &>/dev/null; then
    echo "[→] Установка sshfs..."
    sudo apt update -qq && sudo apt install -y sshfs 2>&1 | tail -3
fi

echo "[→] Монтирование хоста (${HOST_USER}@${HOST_IP})..."
mkdir -p "$SHARED_BASE"
fusermount -u "$SHARED_BASE" 2>/dev/null || true
sleep 1
sshfs "${HOST_USER}@${HOST_IP}:${HOST_PATH}" "$SHARED_BASE" \
    -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 || {
    echo "[!] Не удалось примонтировать хост"
    exit 1
}
echo "[✓] Хост примонтирован: $SHARED_BASE"

# -------------------------- ОЧИСТКА ------------------------------------
cleanup() {
    echo ""
    if [[ -n "$PODMAN_BIN" ]]; then
        $PODMAN_BIN ps --filter name="${CONTAINER_PREFIX}_" -q 2>/dev/null | while read -r cid; do
            $PODMAN_BIN stop "$cid" 2>/dev/null || true
        done
    fi
    rm -rf "/dev/shm/oreshnik_exec_*" 2>/dev/null || true
    if mountpoint -q "$SHARED_BASE" 2>/dev/null; then
        fusermount -u "$SHARED_BASE" 2>/dev/null || true
        echo "[✓] Хост размонтирован"
    fi
    exit 0
}
trap cleanup EXIT INT TERM

# -------------------------- PODMAN -------------------------------------
check_podman() {
    [[ -n "$PODMAN_BIN" ]] && $PODMAN_BIN info >/dev/null 2>&1 && return 0
    return 1
}

detect_package_manager() {
    if $PODMAN_BIN run --rm python:3.11-slim sh -c "command -v apt-get" 2>/dev/null; then
        echo "apt"
    else
        echo "apk"
    fi
}

execute_in_container() {
    local script_path="$1"
    local task_id="$2"

    check_podman || { echo "Podman недоступен" > "$SYNC_DIR/${task_id}.error"; return 1; }

    local script_name=$(basename "$script_path")
    local container_name="${CONTAINER_PREFIX}_${task_id}"
    local pkg_manager=$(detect_package_manager)

    mkdir -p "$TMP_DIR"
    cp "$script_path" "$TMP_DIR/script.py"

    if [[ "$pkg_manager" == "apt" ]]; then
        cat > "$TMP_DIR/Dockerfile" << 'DOCKEREOF'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl iputils-ping procps net-tools netcat-openbsd nmap dnsutils whois && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /lab
COPY script.py /lab/script.py
CMD ["python3", "/lab/script.py"]
DOCKEREOF
    else
        cat > "$TMP_DIR/Dockerfile" << 'DOCKEREOF'
FROM python:3.11-alpine
RUN apk add --no-cache curl iputils procps net-tools nmap bind-tools whois
WORKDIR /lab
COPY script.py /lab/script.py
CMD ["python3", "/lab/script.py"]
DOCKEREOF
    fi

    local image_tag="${CONTAINER_PREFIX}_${task_id}:latest"

    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║   PODMAN: $task_id"
    echo "╚══════════════════════════════════════════════╝"

    echo "[1/4] Сборка образа..."
    $PODMAN_BIN build --rm -t "$image_tag" "$TMP_DIR" 2>&1 | tail -5 || {
        echo "Ошибка сборки" > "$SYNC_DIR/${task_id}.error"
        return 1
    }

    echo "[4/4] Запуск контейнера с сетью..."
    local tmp_out="$TMP_DIR/out.txt"
    local tmp_err="$TMP_DIR/err.txt"

    $PODMAN_BIN run \
        --name "$container_name" \
        --userns=keep-id \
        --security-opt no-new-privileges \
        --cap-drop=ALL \
        --cap-add=NET_RAW \
        --network=slirp4netns \
        --rm \
        "$image_tag" > "$tmp_out" 2> "$tmp_err" || true

    local exit_code=$?

    {
        echo "=== ВЫПОЛНЕНИЕ СКРИПТА ==="
        echo "Задача: $task_id"
        echo "Скрипт: $script_name"
        echo "Статус: $exit_code"
        echo "Время: $(date)"
        echo ""
        echo "=== ВЫВОД ==="
        cat "$tmp_out" 2>/dev/null || echo "(пусто)"
        echo ""
        echo "=== ОШИБКИ ==="
        cat "$tmp_err" 2>/dev/null || echo "(нет)"
    } > "$RESULTS_DIR/${task_id}.txt"

    [[ -s "$tmp_err" ]] && cp "$tmp_err" "$SYNC_DIR/${task_id}.error"
    touch "$SYNC_DIR/${task_id}.done"

    $PODMAN_BIN rmi "$image_tag" 2>/dev/null || true
    rm -rf "$TMP_DIR"

    echo "  Статус: $exit_code"
    echo "  Результат: $RESULTS_DIR/${task_id}.txt"
    echo ""
}

# ============================================================================
echo ""
echo "  ORESHNIK EXEC — KALI-ИСПОЛНИТЕЛЬ"
echo "  Хост: ${HOST_USER}@${HOST_IP}"
echo "  Мониторинг: $TASKS_DIR"
echo "  CTRL+C для выхода"
echo ""

while true; do
    if ! mountpoint -q "$SHARED_BASE" 2>/dev/null; then
        echo "[!] Монтирование отвалилось. Переподключаю..."
        sshfs "${HOST_USER}@${HOST_IP}:${HOST_PATH}" "$SHARED_BASE" \
            -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 || { sleep 5; continue; }
    fi

    for task_file in "$TASKS_DIR"/task_*.py; do
        [[ ! -f "$task_file" ]] && continue
        task_id=$(basename "$task_file" .py)
        [[ -f "$SYNC_DIR/${task_id}.done" ]] || [[ -f "$SYNC_DIR/${task_id}.error" ]] && continue

        echo ""
        echo "╔══════════════════════════════════════════════╗"
        echo "║   НОВАЯ ЗАДАЧА: $task_id"
        echo "╚══════════════════════════════════════════════╝"

        execute_in_container "$task_file" "$task_id"
    done

    sleep "$SLEEP_INTERVAL"
done