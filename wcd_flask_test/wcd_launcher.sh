#!/bin/bash
# =============================================================================
# wcd_launcher.sh — Лаунчер для песочницы Web Cache Deception в RAM
# Версия: 2.1 (исправлен restart, логирование событий)
# =============================================================================
# Назначение:
#   - Копирует файлы проекта в /tmp/wcd_sandbox (оперативная память)
#   - Запускает Flask (порт 8081) и Nginx (порт 8080)
#   - Предоставляет интерактивное меню для управления
#   - При выходе полностью убивает все процессы и удаляет RAM-директорию
#   - Логирует все действия и HTTP-запросы в wcd.log на хосте
# =============================================================================

set -e  # Выходить при любой ошибке (кроме обработанных случаев)

# -----------------------------------------------------------------------------
# НАСТРОЙКИ (измени здесь, если нужно)
# -----------------------------------------------------------------------------
PROJECT_DIR="$HOME/BB/CORE-SWIGGER/wcd_flask_test"   # Откуда копируем файлы
RAM_DIR="/tmp/wcd_sandbox"                           # Рабочая папка в RAM
FLASK_PORT=8081                                      # Порт Flask
NGINX_PORT=8080                                      # Порт Nginx
LOG_FILE="$PROJECT_DIR/wcd.log"                      # Лог-файл на хосте

# -----------------------------------------------------------------------------
# ЦВЕТА ДЛЯ ВЫВОДА
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'    # Успех
YELLOW='\033[1;33m'   # Предупреждение/ожидание
RED='\033[0;31m'      # Ошибка
CYAN='\033[0;36m'     # Информация/заголовки
NC='\033[0m'          # Сброс цвета

# -----------------------------------------------------------------------------
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ДЛЯ PID-ов ПРОЦЕССОВ
# -----------------------------------------------------------------------------
FLASK_PID=""   # PID мастер-процесса Flask (группы процессов)
NGINX_PID=""   # PID мастер-процесса Nginx

# =============================================================================
# ФУНКЦИЯ ЛОГИРОВАНИЯ СОБЫТИЙ (УНИВЕРСАЛЬНАЯ)
# Параметры:
#   $1 - тип события (START, STOP, INFO, ERROR, WARN, ACTION, REQUEST)
#   $2 - описание события
#   $3 - дополнительные данные (опционально)
# =============================================================================
log_event() {
    local event_type="$1"
    local message="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$event_type] $message" >> "$LOG_FILE"
    if [[ -n "$details" ]]; then
        echo "    $details" >> "$LOG_FILE"
    fi
}

# =============================================================================
# ЛОГИРОВАНИЕ HTTP-ЗАПРОСА (для команды test)
# =============================================================================
log_http_request() {
    local url="$1"
    local method="${2:-GET}"
    local cookie="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "[$timestamp] [REQUEST] $method $url" >> "$LOG_FILE"
    [[ -n "$cookie" ]] && echo "    Cookie: $cookie" >> "$LOG_FILE"
    echo "───────────────────────────────────────────────────────────────" >> "$LOG_FILE"
    
    # Выполняем запрос и пишем заголовки ответа
    if [[ -n "$cookie" ]]; then
        curl -s -I -b "$cookie" "$url" >> "$LOG_FILE" 2>&1
    else
        curl -s -I "$url" >> "$LOG_FILE" 2>&1
    fi
    
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# =============================================================================
# ФУНКЦИЯ ОЧИСТКИ ПРИ ВЫХОДЕ ИЗ ЛАУНЧЕРА
# Вызывается только при exit или Ctrl+C (SIGINT)
# =============================================================================
cleanup() {
    log_event "STOP" "Лаунчер завершает работу, очистка ресурсов"
    
    echo -e "\n${YELLOW}[!] Завершение работы, очистка ресурсов...${NC}"
    
    # -------------------------------------------------------------------------
    # 1. Останавливаем Nginx
    # -------------------------------------------------------------------------
    if [[ -n "$NGINX_PID" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "   Останавливаю Nginx (PID $NGINX_PID)..."
        sudo nginx -s quit -c "$RAM_DIR/nginx.conf" 2>/dev/null || true
        sleep 0.5
        sudo kill -KILL "$NGINX_PID" 2>/dev/null || true
        log_event "STOP" "Nginx остановлен" "PID: $NGINX_PID"
    fi
    # Добиваем порт
    sudo fuser -k "$NGINX_PORT/tcp" 2>/dev/null || true
    
    # -------------------------------------------------------------------------
    # 2. Останавливаем Flask (используем SIGKILL, он не перехватывается trap)
    # -------------------------------------------------------------------------
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        echo "   Останавливаю Flask (PID $FLASK_PID)..."
        kill -KILL -"$FLASK_PID" 2>/dev/null || true
        log_event "STOP" "Flask остановлен" "PID: $FLASK_PID"
    fi
    # Добиваем порт
    sudo fuser -k "$FLASK_PORT/tcp" 2>/dev/null || true
    
    # -------------------------------------------------------------------------
    # 3. Удаляем RAM-директорию со всем содержимым
    # -------------------------------------------------------------------------
    if [[ -d "$RAM_DIR" ]]; then
        rm -rf "$RAM_DIR"
        echo "   RAM-директория удалена: $RAM_DIR"
        log_event "INFO" "RAM-директория удалена" "$RAM_DIR"
    fi
    
    log_event "STOP" "Сессия завершена"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo -e "${GREEN}[+] Очистка завершена. Лог сохранён в $LOG_FILE${NC}"
    exit 0
}

# -----------------------------------------------------------------------------
# Вешаем обработчик cleanup ТОЛЬКО на EXIT и SIGINT (Ctrl+C)
# SIGTERM не используем, чтобы не срабатывал при рестарте
# -----------------------------------------------------------------------------
trap cleanup EXIT SIGINT

# =============================================================================
# ПОДГОТОВКА RAM-ОКРУЖЕНИЯ
# =============================================================================
prepare_ram() {
    echo -e "${CYAN}[1/4] Подготовка RAM-окружения...${NC}"
    
    # Создаём рабочую папку в /tmp и подпапку tools
    mkdir -p "$RAM_DIR"
    mkdir -p "$RAM_DIR/tools"
    
    # Копируем файлы из проекта в RAM
    cp "$PROJECT_DIR/app.py" "$RAM_DIR/"
    cp "$PROJECT_DIR/nginx.conf" "$RAM_DIR/"
    cp -r "$PROJECT_DIR/tools/." "$RAM_DIR/tools/" 2>/dev/null || true
    
    # Делаем пулемёт исполняемым
    chmod +x "$RAM_DIR/tools/wcd_gun.sh" 2>/dev/null || true
    
    log_event "INFO" "Файлы скопированы в RAM" "Источник: $PROJECT_DIR -> $RAM_DIR"
    
    echo -e "${GREEN}   [+] Файлы скопированы в $RAM_DIR${NC}"
}

# =============================================================================
# ЗАПУСК FLASK
# =============================================================================
start_flask() {
    echo -e "${CYAN}[2/4] Запуск Flask (порт $FLASK_PORT)...${NC}"
    
    # Переходим в RAM-директорию
    cd "$RAM_DIR"
    
    # Запускаем Flask в фоне через setsid (создаёт новую сессию)
    setsid python3 app.py > "$RAM_DIR/flask.log" 2>&1 &
    FLASK_PID=$!
    
    # Ждём, пока порт станет доступен (максимум 4 секунды)
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
    
    # Если за 20 итераций не запустился — ошибка
    echo -e "\n${RED}[!] Flask не запустился${NC}"
    log_event "ERROR" "Flask не запустился" "Порт: $FLASK_PORT"
    return 1
}

# =============================================================================
# ЗАПУСК NGINX
# =============================================================================
start_nginx() {
    echo -e "${CYAN}[3/4] Запуск Nginx (порт $NGINX_PORT)...${NC}"
    
    # Создаём временные папки для Nginx внутри RAM
    mkdir -p "$RAM_DIR/nginx_temp" "$RAM_DIR/nginx_cache"
    
    # Запускаем Nginx с нашим конфигом
    sudo nginx -c "$RAM_DIR/nginx.conf" 2>/dev/null
    
    # Пытаемся получить PID мастер-процесса
    NGINX_PID=$(sudo cat "$RAM_DIR/nginx.pid" 2>/dev/null)
    if [[ -z "$NGINX_PID" ]]; then
        NGINX_PID=$(pgrep -f "nginx.*$RAM_DIR/nginx.conf" | head -1)
    fi
    
    if [[ -n "$NGINX_PID" ]]; then
        echo -e "${GREEN}   [+] Nginx запущен (PID $NGINX_PID)${NC}"
        log_event "START" "Nginx запущен" "PID: $NGINX_PID, Порт: $NGINX_PORT"
    else
        echo -e "${YELLOW}   [!] PID Nginx не определён, остановка будет через fuser${NC}"
        log_event "WARN" "PID Nginx не определён" "Порт: $NGINX_PORT"
    fi
}

# =============================================================================
# ПЕРЕЗАПУСК СЕРВИСОВ (без вызова cleanup)
# =============================================================================
restart_services() {
    echo -e "${YELLOW}[!] Перезапуск сервисов...${NC}"
    log_event "INFO" "Перезапуск сервисов начат"
    
    # -------------------------------------------------------------------------
    # 1. Останавливаем Nginx
    # -------------------------------------------------------------------------
    if [[ -n "$NGINX_PID" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "   Останавливаю Nginx (PID $NGINX_PID)..."
        sudo nginx -s quit -c "$RAM_DIR/nginx.conf" 2>/dev/null || true
        sleep 0.5
        sudo kill -KILL "$NGINX_PID" 2>/dev/null || true
    fi
    sudo fuser -k "$NGINX_PORT/tcp" 2>/dev/null || true
    
    # -------------------------------------------------------------------------
    # 2. Останавливаем Flask (используем SIGKILL — не перехватывается trap)
    # -------------------------------------------------------------------------
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        echo "   Останавливаю Flask (PID $FLASK_PID)..."
        kill -KILL -"$FLASK_PID" 2>/dev/null || true
    fi
    sudo fuser -k "$FLASK_PORT/tcp" 2>/dev/null || true
    
    # Сбрасываем PID-ы
    FLASK_PID=""
    NGINX_PID=""
    
    sleep 1
    
    # -------------------------------------------------------------------------
    # 3. Проверяем, существует ли RAM_DIR (на случай, если что-то удалило)
    # -------------------------------------------------------------------------
    if [[ ! -d "$RAM_DIR" ]]; then
        echo "   [!] RAM-директория отсутствует, пересоздаю..."
        prepare_ram
    fi
    
    # -------------------------------------------------------------------------
    # 4. Запускаем заново
    # -------------------------------------------------------------------------
    start_flask
    start_nginx
    
    log_event "INFO" "Сервисы перезапущены"
}

# =============================================================================
# ПОКАЗАТЬ СТАТУС ПРОЦЕССОВ И ПОРТОВ
# =============================================================================
show_status() {
    echo -e "${CYAN}Статус процессов:${NC}"
    
    # Проверяем Flask по PID
    if [[ -n "$FLASK_PID" ]] && kill -0 "$FLASK_PID" 2>/dev/null; then
        echo -e "  Flask: ${GREEN}работает${NC} (PID $FLASK_PID)"
    else
        echo -e "  Flask: ${RED}не работает${NC}"
    fi
    
    # Проверяем Nginx: сначала по порту (надёжнее), потом по PID
    if sudo lsof -i :$NGINX_PORT 2>/dev/null | grep -q nginx; then
        local nginx_pids=$(sudo lsof -t -i :$NGINX_PORT 2>/dev/null | tr '\n' ' ')
        echo -e "  Nginx: ${GREEN}работает${NC} (PID $nginx_pids)"
    elif [[ -n "$NGINX_PID" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then
        echo -e "  Nginx: ${GREEN}работает${NC} (PID $NGINX_PID)"
    else
        echo -e "  Nginx: ${RED}не работает${NC}"
    fi
    
    echo ""
    echo "Порты:"
    echo "  Flask ($FLASK_PORT):"
    sudo lsof -i :$FLASK_PORT 2>/dev/null | tail -n +2 | sed 's/^/    /' || echo "    свободен"
    echo "  Nginx ($NGINX_PORT):"
    sudo lsof -i :$NGINX_PORT 2>/dev/null | tail -n +2 | sed 's/^/    /' || echo "    свободен"
}

# =============================================================================
# ИНТЕРАКТИВНОЕ МЕНЮ
# =============================================================================
show_menu() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🛡️  WCD LAUNCHER — Песочница в RAM${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}Flask:${NC} localhost:$FLASK_PORT  |  ${GREEN}Nginx:${NC} localhost:$NGINX_PORT"
    echo -e "  ${GREEN}RAM dir:${NC} $RAM_DIR"
    echo -e "  ${GREEN}Лог (хост):${NC} $LOG_FILE"
    echo ""
    echo -e "${YELLOW}Команды:${NC}"
    echo "  gun           — запустить пулемёт"
    echo "  test <url>    — тестовый запрос + запись в лог"
    echo "  log           — последние 20 строк лога"
    echo "  logfull       — открыть лог в less"
    echo "  restart       — перезапустить сервисы"
    echo "  status        — статус процессов и портов"
    echo "  help          — подсказка"
    echo "  exit          — выход и очистка"
    echo ""
}

# =============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# =============================================================================
main() {
    # Инициализация лог-файла
    echo "" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    log_event "START" "=== НОВАЯ СЕССИЯ WCD LAUNCHER ==="
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    
    # 1. Подготовка RAM
    prepare_ram
    
    # 2. Запуск Flask (если не запустится — выход)
    start_flask || exit 1
    
    # 3. Запуск Nginx
    start_nginx || exit 1
    
    log_event "INFO" "Лаунчер готов к работе"
    
    # 4. Главный цикл обработки команд
    while true; do
        show_menu
        read -p "wcd-launcher > " cmd arg
        
        case $cmd in
            gun)
                log_event "ACTION" "Запуск пулемёта wcd_gun.sh"
                echo -e "${YELLOW}Запускаю пулемёт...${NC}"
                cd "$RAM_DIR/tools"
                ./wcd_gun.sh
                cd "$RAM_DIR"
                log_event "ACTION" "Пулемёт завершил работу"
                ;;
            test)
                if [[ -z "$arg" ]]; then
                    echo -e "${RED}Укажи URL (например, test http://localhost:8080/profile)${NC}"
                else
                    log_event "ACTION" "Тестовый запрос" "$arg"
                    log_http_request "$arg"
                    echo -e "${GREEN}Запрос выполнен, результат в логе.${NC}"
                    curl -s -I "$arg" | head -3
                fi
                ;;
            log)
                echo -e "${CYAN}Последние 20 строк лога:${NC}"
                tail -20 "$LOG_FILE"
                ;;
            logfull)
                less "$LOG_FILE"
                ;;
            restart)
                restart_services
                ;;
            status)
                show_status
                ;;
            help)
                show_menu
                ;;
            exit|quit)
                echo -e "${YELLOW}Выход...${NC}"
                exit 0
                ;;
            *)
                if [[ -n "$cmd" ]]; then
                    echo -e "${RED}Неизвестная команда: $cmd${NC}"
                fi
                ;;
        esac
        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
main