#!/bin/bash

# 1. Подгружаем настройки (через точку - это надежнее)
. ./settings


# 2. Присваиваем порт (проверь, чтобы в settings был PORT_BACKEND)
TARGET_PORT=$PORT_BACKEND

# 3. Функция-киллер
stop_backend() {
    echo "[!] Чистим порт: $TARGET_PORT"
    fuser -k "$TARGET_PORT/tcp" 2>/dev/null
}

 start_backend(){ echo '[+] Start... ';  python3 server.py & }
