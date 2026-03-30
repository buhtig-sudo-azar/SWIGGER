#!/bin/bash

# 1. Подгружаем настройки (порты, пути)
[[ -f ./settings ]] && . ./settings

# 2. Переменные среды (Zero Trust: работаем только в RAM)
WORK_DIR="/tmp/anatoly_project"
TARGET_PORT=$PORT_BACKEND  # Берем из settings (например, 8080)

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

# 5. Мониторинг (Живой поток логов)
monitor_attack() {
    echo "[*] Запуск живого мониторинга WCD..."
    touch "$WORK_DIR/log"
    tail -f "$WORK_DIR/log" | awk '{print $1, " -> ", $7}' 
}

# --- АТОМАРНЫЙ ЗАПУСК ЯДРА ---
init_ram && stop_backend && monitor_attack
