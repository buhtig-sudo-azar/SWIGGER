#!/bin/bash
# Функция очистки
cleanup() {
    # 1. Специфичная очистка модуля (если есть)
    if declare -f module_cleanup >/dev/null; then
        module_cleanup
    fi

    # 2. Убиваем все процессы из массива PIDS
    all_pids=""
    for pid in "${PIDS[@]}"; do
 all_pids+=$(pstree -p $pid 2>/dev/null | grep -o '([0-9]\+)' | grep -o '[0-9]\+' | tr '\n' ' ')
done
kill $all_pids 2>/dev/null
sleep 0.9
kill -9 $all_pids 2>/dev/null

    # 3. Удаляем RAM-директорию
    rm -rf "$WORK_DIR"

    exit 0
}
trap cleanup SIGINT SIGTERM EXIT
load_module() {
    local mod_name=$1
    local mod_path="./modules/${mod_name}.sh"
    if [[ -f "$mod_path" ]]; then
        source "$mod_path"
    else
        echo "Модуль не найден: $mod_path"
        exit 1
    fi
}
[[ -f ./settings ]] && . ./settings

# 2. Переменные среды (Zero Trust: работаем только в RAM)
WORK_DIR="/tmp/anatoly_project"
TARGET_PORT=$PORT_BACKEND  # Берем из settings (например, 8080)
PIDS=()
wait_for_port() {
    local port=$1
    while ! nc -z localhost $port 2>/dev/null; do
        sleep 0.1
    done
}

# 3. Функция-киллер (Очистка порта перед запуском)
stop_backend() {
    echo "[!] Чистим порт: $TARGET_PORT"
    fuser -k "$TARGET_PORT/tcp" 2>/dev/null || :
}

# 4. Инициализация среды (Zero Trust: проверка и создание папок)
init_ram() {
    mkdir -p "$WORK_DIR/cache"
    if [ -d "$WORK_DIR/cache" ] && [ -w "$WORK_DIR" ]; then
        echo "[+] Среда в RAM готова: $WORK_DIR"
    else
        echo "[!!!] КРИТИЧЕСКАЯ ОШИБКА: Нет доступа к RAM"
        exit 1
    fi
}


# --- АТОМАРНЫЙ ЗАПУСК ЯДРА ---
init_ram && stop_backend
if [[ -z "$1" ]]; then
    echo "Использование: ./kernel.sh <модуль>"
    exit 1
fi
load_module "$1"
if declare -f module_run >/dev/null; then
    module_run
else
    echo "Модуль не содержит функцию module_run"
    exit 1
fi
wait
