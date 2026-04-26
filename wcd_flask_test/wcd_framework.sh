#!/bin/bash
# =============================================================================
# Файл: wcd_framework.sh — WCD LAUNCHER
# Назначение: Управление стендом Web Cache Deception (Flask + Nginx в RAM)
# =============================================================================

# --- НАСТРОЙКИ ---------------------------------------------------------------
PROJECT_DIR="$HOME/BB/CORE-SWIGGER/wcd_flask_test"
RAM_DIR="/tmp/wcd_sandbox"
STATE_FILE="$RAM_DIR/.state"
FLASK_PORT=8081
NGINX_PORT=8080
LOG_FILE="$PROJECT_DIR/wcd.log"

# Обязательные файлы (должны быть созданы вручную)
REQUIRED_FILES=(
    "$PROJECT_DIR/app.py"
    "$PROJECT_DIR/nginx.conf"
    "$PROJECT_DIR/nginx_vuln.conf"
    "$PROJECT_DIR/tools/wcd_gun.sh"
)

# Доступные конфигурации Nginx
declare -A NGINX_CONFIGS=(
    ["vuln"]="nginx_vuln.conf"
    ["secure"]="nginx.conf"
)
ACTIVE_CONFIG=""

# --- ЦВЕТА -------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- PID-ы -------------------------------------------------------------------
FLASK_PID=""
NGINX_PID=""

# =============================================================================
# ОБЩИЕ ФУНКЦИИ
# =============================================================================

# Логирование в файл
log_event() {
    local event_type="$1"
    local message="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] [$event_type] $message" >> "$LOG_FILE"
    [[ -n "$details" ]] && echo "    $details" >> "$LOG_FILE"
}

# =============================================================================
# БЛОК LAUNCHER (УПРАВЛЕНИЕ СТЕНДОМ)
# =============================================================================

# Строгая проверка обязательных файлов
check_required_files() {
    echo -e "${CYAN}[ПРОВЕРКА] Сканирую обязательные файлы...${NC}"
    local missing=0
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "  ${GREEN}[✓]${NC} $file"
        else
            echo -e "  ${RED}[✗]${NC} $file ${RED}ОТСУТСТВУЕТ${NC}"
            missing=1
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        echo ""
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}[!] ОБНАРУЖЕНЫ ОТСУТСТВУЮЩИЕ ФАЙЛЫ. ЗАПУСК НЕВОЗМОЖЕН.${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[+] Все обязательные файлы найдены.${NC}"
    echo ""
}

# Сохранение состояния для пулемёта
save_state() {
    mkdir -p "$RAM_DIR"
    cat > "$STATE_FILE" << EOF
# WCD Sandbox State File
ACTIVE_CONFIG="$ACTIVE_CONFIG"
CONFIG_FILE="${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
TARGET_URL="http://127.0.0.1:$NGINX_PORT/profile"
FLASK_PORT="$FLASK_PORT"
NGINX_PORT="$NGINX_PORT"
EOF
    echo -e "${GREEN}[+] Состояние сохранено в $STATE_FILE${NC}"
}

# Выбор конфигурации
select_config() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🛡️  WCD LAUNCHER — Выбор режима работы${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Выберите конфигурацию Nginx:${NC}"
    echo ""
    echo -e "  ${RED}1) vuln${NC}    — Уязвимый режим (без защиты, для отработки атак)"
    echo -e "  ${GREEN}2) secure${NC}  — Защищённый режим (с блокировкой WCD)"
    echo ""
    echo -e "${CYAN}Введи номер (1 или 2):${NC}"
    
    while true; do
        read -p "> " choice
        case $choice in
            1) ACTIVE_CONFIG="vuln"; break ;;
            2) ACTIVE_CONFIG="secure"; break ;;
            *) echo -e "${RED}[!] Введи 1 или 2${NC}" ;;
        esac
    done
    
    echo ""
    echo -e "${GREEN}[+] Выбран режим: ${ACTIVE_CONFIG}${NC}"
    echo -e "${GREEN}[+] Файл конфигурации: ${NGINX_CONFIGS[$ACTIVE_CONFIG]}${NC}"
    log_event "CONFIG" "Выбран режим" "$ACTIVE_CONFIG -> ${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
    sleep 1
}

# Полная очистка (включая кэш Nginx)
full_cleanup() {
    echo -e "\n${YELLOW}[!] ПОЛНАЯ ОЧИСТКА: процессы, RAM-директория, кэш Nginx...${NC}"
    
    # Nginx
    if [[ -n "$NGINX_PID" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "   Останавливаю Nginx (PID $NGINX_PID)..."
        sudo nginx -s quit -c "$RAM_DIR/${NGINX_CONFIGS[$ACTIVE_CONFIG]}" 2>/dev/null || true
        sleep 0.5
        sudo kill -KILL "$NGINX_PID" 2>/dev/null || true
        log_event "STOP" "Nginx остановлен" "PID: $NGINX_PID"
    fi
    sudo pkill -9 nginx 2>/dev/null || true
    sudo fuser -k "$NGINX_PORT/tcp" 2>/dev/null || true

    # Flask
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        echo "   Останавливаю Flask (PID $FLASK_PID)..."
        kill -KILL -"$FLASK_PID" 2>/dev/null || true
        log_event "STOP" "Flask остановлен" "PID: $FLASK_PID"
    fi
    sudo fuser -k "$FLASK_PORT/tcp" 2>/dev/null || true

    # Удаление RAM-директории
    if [[ -d "$RAM_DIR" ]]; then
        rm -rf "$RAM_DIR"
        echo "   RAM-директория удалена: $RAM_DIR"
        log_event "INFO" "RAM-директория удалена" "$RAM_DIR"
    fi

    # Очистка кэша Nginx
    if [[ -d "/tmp/nginx_cache" ]]; then
        sudo rm -rf /tmp/nginx_cache/*
        echo "   Кэш Nginx очищен: /tmp/nginx_cache"
        log_event "INFO" "Кэш Nginx очищен" "/tmp/nginx_cache"
    fi
    
    echo -e "${GREEN}[+] Полная очистка завершена.${NC}"
}

# Очистка при выходе
cleanup() {
    log_event "STOP" "Лаунчер завершает работу, очистка ресурсов"
    full_cleanup
    log_event "STOP" "Сессия завершена"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    echo -e "${GREEN}[+] Очистка завершена. Лог: $LOG_FILE${NC}"
    exit 0
}

# Подготовка RAM-окружения (динамическое копирование ВСЕХ файлов)
prepare_ram() {
    echo -e "${CYAN}[1/4] Подготовка RAM-окружения...${NC}"
    mkdir -p "$RAM_DIR" "$RAM_DIR/tools"
    
    # Копируем основные файлы Flask и Nginx
    cp "$PROJECT_DIR/app.py" "$RAM_DIR/"
    cp "$PROJECT_DIR/nginx.conf" "$RAM_DIR/"
    cp "$PROJECT_DIR/nginx_vuln.conf" "$RAM_DIR/"
    
    # Копируем ВСЮ директорию tools динамически (рекурсивно)
    if [[ -d "$PROJECT_DIR/tools" ]]; then
        cp -r "$PROJECT_DIR/tools/"* "$RAM_DIR/tools/" 2>/dev/null
        # Убеждаемся что пулемёт исполняемый
        [[ -f "$RAM_DIR/tools/wcd_gun.sh" ]] && chmod +x "$RAM_DIR/tools/wcd_gun.sh"
    fi
    
    save_state
    
    log_event "INFO" "Файлы скопированы в RAM" "Источник: $PROJECT_DIR -> $RAM_DIR"
    echo -e "${GREEN}   [+] Файлы скопированы в $RAM_DIR${NC}"
}

# Запуск Flask
start_flask() {
    echo -e "${CYAN}[2/4] Запуск Flask (порт $FLASK_PORT)...${NC}"
    cd "$RAM_DIR"
    
    # Проверка наличия Flask ДО запуска
    echo -n "   Проверка Flask..."
    if ! python3 -c "import flask" 2>/dev/null; then
        echo -e " ${RED}НЕ НАЙДЕН${NC}"
        echo ""
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}[!] ОШИБКА: Flask не установлен в текущем окружении!${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}[*] Текущее окружение Python: $(which python3)${NC}"
        echo -e "${YELLOW}[*] Установите Flask командой: pip install flask${NC}"
        echo -e "${YELLOW}[*] Или активируйте окружение, где Flask установлен${NC}"
        echo ""
        log_event "ERROR" "Flask не установлен" "Выполните: pip install flask"
        return 1
    fi
    echo -e " ${GREEN}OK${NC}"
    
    # Проверка синтаксиса app.py перед запуском
    echo -n "   Проверка синтаксиса app.py..."
    local syntax_check=$(python3 -m py_compile app.py 2>&1)
    if [[ $? -ne 0 ]]; then
        echo -e " ${RED}ОШИБКА${NC}"
        echo ""
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}[!] ОШИБКА: Синтаксическая ошибка в app.py!${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}$syntax_check${NC}"
        echo ""
        log_event "ERROR" "Синтаксическая ошибка в app.py" "$syntax_check"
        return 1
    fi
    echo -e " ${GREEN}OK${NC}"
    
    # Проверка, что порт свободен
    echo -n "   Проверка порта $FLASK_PORT..."
    if lsof -i :$FLASK_PORT 2>/dev/null | grep -q LISTEN; then
        echo -e " ${RED}ЗАНЯТ${NC}"
        echo ""
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}[!] ОШИБКА: Порт $FLASK_PORT уже занят!${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}[*] Процесс на порту:${NC}"
        lsof -i :$FLASK_PORT 2>/dev/null
        echo -e "${YELLOW}[*] Освободите порт или измените FLASK_PORT в скрипте${NC}"
        log_event "ERROR" "Порт $FLASK_PORT занят" "$(lsof -i :$FLASK_PORT 2>/dev/null)"
        return 1
    fi
    echo -e " ${GREEN}СВОБОДЕН${NC}"
    
    # Запуск Flask
    echo -n "   Запуск Flask..."
    setsid python3 app.py > "$RAM_DIR/flask.log" 2>&1 &
    FLASK_PID=$!
    echo -e " PID=$FLASK_PID"
    
    echo -n "   Ожидание Flask"
    for i in $(seq 1 20); do
        if nc -z localhost $FLASK_PORT 2>/dev/null; then
            echo -e " ${GREEN}готов (PID $FLASK_PID)${NC}"
            log_event "START" "Flask запущен" "PID: $FLASK_PID, Порт: $FLASK_PORT"
            return 0
        fi
        sleep 0.2
        echo -n "."
    done
    
    # Если не запустился - показываем логи
    echo -e "\n${RED}[!] Flask не запустился за отведённое время${NC}"
    echo -e "${YELLOW}[*] PID процесса: $FLASK_PID${NC}"
    
    # Проверяем, жив ли процесс
    if kill -0 $FLASK_PID 2>/dev/null; then
        echo -e "${YELLOW}[*] Процесс жив, но порт не открыт. Возможно, Flask долго загружается${NC}"
        echo -e "${YELLOW}[*] Лог Flask:${NC}"
        cat "$RAM_DIR/flask.log" 2>/dev/null | tail -20
        log_event "WARN" "Flask запущен но порт не отвечает" "PID: $FLASK_PID"
        return 1
    else
        echo -e "${RED}[*] Процесс упал. Лог ошибки:${NC}"
        if [[ -f "$RAM_DIR/flask.log" ]]; then
            cat "$RAM_DIR/flask.log"
        else
            echo "Лог недоступен"
        fi
        log_event "ERROR" "Flask упал при запуске" "$(cat $RAM_DIR/flask.log 2>/dev/null)"
        FLASK_PID=""
        return 1
    fi
}

# Запуск Nginx
start_nginx() {
    local config_file="${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
    echo -e "${CYAN}[3/4] Запуск Nginx (порт $NGINX_PORT) с конфигом: ${BLUE}$config_file${NC}"
    mkdir -p "$RAM_DIR/nginx_temp" "/tmp/nginx_cache"
    
    sudo nginx -c "$RAM_DIR/$config_file" 2>/dev/null
    NGINX_PID=$(sudo cat "$RAM_DIR/nginx.pid" 2>/dev/null | head -1)
    
    if [[ -n "$NGINX_PID" ]]; then
        echo -e "${GREEN}   [+] Nginx запущен (PID $NGINX_PID)${NC}"
        log_event "START" "Nginx запущен" "PID: $NGINX_PID, Порт: $NGINX_PORT, Конфиг: $config_file"
    else
        echo -e "${YELLOW}   [!] PID Nginx не определён, но процесс может работать${NC}"
        log_event "WARN" "PID Nginx не определён" "Конфиг: $config_file"
    fi
}

# Перезапуск с выбором конфига
restart_services() {
    echo -e "${YELLOW}[!] Перезапуск сервисов...${NC}"
    log_event "INFO" "Перезапуск сервисов начат"
    
    full_cleanup
    FLASK_PID=""
    NGINX_PID=""
    sleep 1
    
    select_config
    
    [[ -d "$RAM_DIR" ]] && rm -rf "$RAM_DIR"
    prepare_ram
    start_flask || { 
        echo -e "${RED}[!] Не удалось запустить Flask${NC}"
        echo -e "${YELLOW}[*] Проверьте логи: $LOG_FILE${NC}"
        log_event "ERROR" "Перезапуск прерван - Flask не запустился"
        return 1
    }
    start_nginx
    log_event "INFO" "Сервисы перезапущены с конфигом: ${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
}

# Горячее переключение конфига
switch_config() {
    echo -e "${YELLOW}[!] Горячее переключение конфигурации...${NC}"
    select_config
    local config_file="${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
    
    save_state
    
    echo -e "${CYAN}[*] Перезагружаю Nginx с новым конфигом: $config_file${NC}"
    if sudo nginx -s reload -c "$RAM_DIR/$config_file" 2>/dev/null; then
        echo -e "${GREEN}[+] Конфигурация переключена на $ACTIVE_CONFIG${NC}"
        log_event "CONFIG" "Горячее переключение" "$ACTIVE_CONFIG -> $config_file"
    else
        echo -e "${RED}[!] Ошибка перезагрузки. Возможно, Nginx не запущен.${NC}"
        echo -e "${YELLOW}[*] Попробуйте 'restart' для полного перезапуска.${NC}"
        return 1
    fi
}

# Статус стенда
show_status() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}СТАТУС СТЕНДА${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        echo -e "  Flask:    ${GREEN}● РАБОТАЕТ${NC} (PID $FLASK_PID, порт $FLASK_PORT)"
    else
        echo -e "  Flask:    ${RED}○ ОСТАНОВЛЕН${NC}"
    fi
    
    if sudo lsof -i :$NGINX_PORT 2>/dev/null | grep -q nginx; then
        echo -e "  Nginx:    ${GREEN}● РАБОТАЕТ${NC} (порт $NGINX_PORT)"
        echo -e "  Режим:    ${BLUE}$ACTIVE_CONFIG${NC} (${NGINX_CONFIGS[$ACTIVE_CONFIG]})"
    else
        echo -e "  Nginx:    ${RED}○ ОСТАНОВЛЕН${NC}"
    fi
    
    echo -e "\n  ${CYAN}Цель для пулемёта:${NC} http://127.0.0.1:$NGINX_PORT/profile"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# Запуск пулемёта (интерактивный режим, как было)
run_gun() {
    local target="http://127.0.0.1:$NGINX_PORT/profile"
    echo -e "${CYAN}[*] Запускаю пулемёт с целью: $target${NC}"
    echo -e "${CYAN}[*] Режим стенда: $ACTIVE_CONFIG${NC}"
    echo ""
    
    cd "$RAM_DIR/tools"
    ./wcd_gun.sh "$target"
    cd "$RAM_DIR"
    
    echo ""
    echo -e "${GREEN}[+] Пулемёт завершил работу.${NC}"
    log_event "ACTION" "Пулемёт завершил работу"
}

# Меню лаунчера
show_launcher_menu() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🛡️  WCD LAUNCHER — Песочница в RAM${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}Flask:${NC} localhost:$FLASK_PORT  |  ${GREEN}Nginx:${NC} localhost:$NGINX_PORT"
    echo -e "  ${GREEN}RAM dir:${NC} $RAM_DIR"
    echo -e "  ${GREEN}Лог:${NC} $LOG_FILE"
    echo -e "  ${BLUE}Режим:${NC} ${ACTIVE_CONFIG:-НЕ ВЫБРАН} (${NGINX_CONFIGS[$ACTIVE_CONFIG]:-})"
    echo ""
    echo -e "${YELLOW}Команды:${NC}"
    echo "  gun           — запустить пулемёт"
    echo "  test <url>    — тестовый запрос (curl -I)"
    echo "  log           — последние 20 строк лога"
    echo "  logfull       — открыть лог в less"
    echo "  restart       — полный перезапуск с очисткой кэша и выбором режима"
    echo "  switch        — сменить режим на лету (hot reload)"
    echo "  status        — статус стенда"
    echo "  help          — это меню"
    echo "  exit          — выход и ПОЛНАЯ очистка"
    echo ""
}

# Основной цикл лаунчера
launcher_main() {
    check_required_files
    
    echo "" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    log_event "START" "=== НОВАЯ СЕССИЯ WCD LAUNCHER ==="
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"

    select_config
    prepare_ram
    start_flask || exit 1
    start_nginx || exit 1
    log_event "INFO" "Лаунчер готов к работе с конфигом: ${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
    
    echo -e "${GREEN}[+] Стенд успешно запущен!${NC}"
    sleep 1

    while true; do
        show_launcher_menu
        read -p "wcd-launcher > " cmd arg
        case $cmd in
            gun)
                run_gun
                echo ""
                read -p "Нажмите Enter для возврата в меню..."
                ;;
            test)
                [[ -z "$arg" ]] && echo -e "${RED}Укажи URL${NC}" || {
                    log_event "ACTION" "Тестовый запрос" "$arg"
                    echo -e "${GREEN}Запрос к $arg :${NC}"
                    curl -s -I "$arg" | head -10
                }
                ;;
            log)    tail -20 "$LOG_FILE" ;;
            logfull) less "$LOG_FILE" ;;
            restart) restart_services ;;
            switch)  switch_config ;;
            status)  show_status ;;
            help)    show_launcher_menu ;;
            exit|quit) exit 0 ;;
            *) [[ -n "$cmd" ]] && echo -e "${RED}Неизвестная команда: $cmd${NC}" ;;
        esac
        if [[ "$cmd" != "gun" ]]; then
            echo ""
            read -p "Нажмите Enter для продолжения..."
        fi
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
trap cleanup EXIT SIGINT
launcher_main