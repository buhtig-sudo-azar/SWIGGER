#!/bin/bash
# =============================================================================
# wcd_gun.sh — Пулемёт для тестирования Web Cache Deception
# =============================================================================
# Назначение:
#   - Интерактивный инструмент для массовой проверки векторов атак WCD
#   - Перебирает разделители и статические расширения
#   - Показывает статус кэша (MISS, HIT, BYPASS) и заголовки защиты
# =============================================================================

# -----------------------------------------------------------------------------
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# -----------------------------------------------------------------------------
TARGET=""                                           # Цель атаки
COOKIE=""                                           # Кука для авторизации
DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")  # Разделители
EXTENSIONS=(".css" ".js" ".jpg" ".ico")             # Статические расширения

# -----------------------------------------------------------------------------
# ЦВЕТА ДЛЯ ВЫВОДА
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# БАННЕР
# =============================================================================
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔫 WCD GUN v2.0 — пулемёт для тестирования Web Cache Deception${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}🎯 Target:${NC} ${TARGET:-НЕ ЗАДАН}"
    echo -e "  ${YELLOW}🍪 Cookie:${NC} ${COOKIE:-НЕТ}"
    echo ""
}

# =============================================================================
# ПРОВЕРКА ДОСТУПНОСТИ ЦЕЛИ
# Параметры:
#   $1 - URL для проверки (если не указан, используется $TARGET)
# =============================================================================
check_target() {
    local url="${1:-$TARGET}"
    
    if [[ -z "$url" ]]; then
        echo -e "${RED}[!] Цель не задана. Используй set target <URL>${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}[*] Проверяю доступность $url...${NC}"
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    if [[ "$http_code" =~ ^(200|302|301|401|403)$ ]]; then
        echo -e "${GREEN}[+] Цель доступна (HTTP $http_code)${NC}"
        return 0
    else
        echo -e "${RED}[!] Цель недоступна или вернула HTTP $http_code${NC}"
        return 1
    fi
}

# =============================================================================
# ОБСТРЕЛ ВСЕМИ РАЗДЕЛИТЕЛЯМИ
# =============================================================================
fire() {
    if ! check_target; then
        return 1
    fi

    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}🔥 ОТКРЫВАЮ ОГОНЬ ПО ВСЕМ ВЕКТОРАМ${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local total_tests=$((${#DELIMITERS[@]} * ${#EXTENSIONS[@]}))
    local current=0
    
    for delim in "${DELIMITERS[@]}"; do
        for ext in "${EXTENSIONS[@]}"; do
            ((current++))
            
            # Формируем URL для атаки
            local attack_url="${TARGET}${delim}test${ext}"
            
            # Первый запрос (прогрев кэша)
            curl -s -o /dev/null -b "$COOKIE" "$attack_url" 2>/dev/null
            sleep 0.2
            
            # Второй запрос (проверяем статус кэша)
            local response=$(curl -s -I -b "$COOKIE" "$attack_url" 2>/dev/null)
            local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | awk '{print $2}' | tr -d '\r')
            local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | awk '{print $2}' | tr -d '\r')
            local http_code=$(echo "$response" | head -1 | awk '{print $2}')
            
            # Вывод результата
            printf "[%3d/%3d] " $current $total_tests
            
            if [[ "$cache_status" == "HIT" ]]; then
                echo -e "${RED}[!] ПРОБИТИЕ!${NC} $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${RED}$cache_status${NC}, Bypass: ${bypass:-нет}"
            elif [[ "$cache_status" == "BYPASS" ]]; then
                echo -e "${GREEN}[✓] ЗАЩИТА${NC}   $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${GREEN}$cache_status${NC}, Bypass: ${bypass:-нет}"
            elif [[ "$cache_status" == "MISS" ]]; then
                echo -e "${YELLOW}[?] MISS${NC}     $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${YELLOW}$cache_status${NC}, Bypass: ${bypass:-нет}"
            elif [[ "$cache_status" == "NO_CACHE" ]]; then
                echo -e "${BLUE}[ ] NO_CACHE${NC} $attack_url"
                echo -e "         → HTTP $http_code, Cache: $cache_status, Bypass: ${bypass:-нет}"
            else
                echo -e "    [ ]          $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${cache_status:-нет}, Bypass: ${bypass:-нет}"
            fi
        done
    done
    
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📊 СТАТИСТИКА:${NC}"
    echo "   Проверено векторов: $total_tests"
    echo "   Если видишь HIT красным — защита пробита, допиливай nginx.conf"
    echo "   Если везде BYPASS или MISS — щит держит"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# ОБСТРЕЛ ОДНИМ РАЗДЕЛИТЕЛЕМ
# =============================================================================
fire_single() {
    local delim="$1"
    
    if [[ -z "$delim" ]]; then
        echo -e "${RED}[!] Укажи разделитель (например, fire_single ;)${NC}"
        return 1
    fi
    
    if [[ -z "$TARGET" ]]; then
        echo -e "${RED}[!] Цель не задана. Используй set target <URL>${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}[*] Обстрел разделителя: '$delim'${NC}"
    echo ""
    
    for ext in "${EXTENSIONS[@]}"; do
        local attack_url="${TARGET}${delim}test${ext}"
        
        # Первый запрос
        curl -s -o /dev/null -b "$COOKIE" "$attack_url" 2>/dev/null
        sleep 0.2
        
        # Второй запрос
        local response=$(curl -s -I -b "$COOKIE" "$attack_url" 2>/dev/null)
        local cache_status=$(echo "$response" | grep -i "X-Cache-Status" | awk '{print $2}' | tr -d '\r')
        local bypass=$(echo "$response" | grep -i "X-WCD-Bypass" | awk '{print $2}' | tr -d '\r')
        local http_code=$(echo "$response" | head -1 | awk '{print $2}')
        
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

# =============================================================================
# УСТАНОВКА ЦЕЛИ
# =============================================================================
set_target() {
    TARGET="$1"
    echo -e "${GREEN}[+] Цель установлена: $TARGET${NC}"
}

# =============================================================================
# УСТАНОВКА КУКИ
# =============================================================================
set_cookie() {
    COOKIE="$1"
    echo -e "${GREEN}[+] Кука установлена: $COOKIE${NC}"
}

# =============================================================================
# ДОБАВЛЕНИЕ РАЗДЕЛИТЕЛЯ
# =============================================================================
add_delimiter() {
    DELIMITERS+=("$1")
    echo -e "${GREEN}[+] Разделитель добавлен: $1${NC}"
}

# =============================================================================
# УДАЛЕНИЕ РАЗДЕЛИТЕЛЯ
# =============================================================================
remove_delimiter() {
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

# =============================================================================
# ПОКАЗАТЬ СПИСОК РАЗДЕЛИТЕЛЕЙ
# =============================================================================
show_delimiters() {
    echo ""
    echo -e "${CYAN}Текущие разделители:${NC}"
    local i=1
    for d in "${DELIMITERS[@]}"; do
        echo "  $i) $d"
        ((i++))
    done
    echo ""
}

# =============================================================================
# ПОКАЗАТЬ СПИСОК РАСШИРЕНИЙ
# =============================================================================
show_extensions() {
    echo ""
    echo -e "${CYAN}Текущие расширения:${NC}"
    for e in "${EXTENSIONS[@]}"; do
        echo "  - $e"
    done
    echo ""
}

# =============================================================================
# ПОКАЗАТЬ ТЕКУЩУЮ ЦЕЛЬ
# =============================================================================
show_target() {
    echo "Текущая цель: ${TARGET:-НЕ ЗАДАНА}"
}

# =============================================================================
# ПОКАЗАТЬ ТЕКУЩУЮ КУКУ
# =============================================================================
show_cookie() {
    echo "Текущая кука: ${COOKIE:-НЕТ}"
}

# =============================================================================
# ПОМОЩЬ
# =============================================================================
show_help() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📖 ДОСТУПНЫЕ КОМАНДЫ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  set target <URL>       — установить цель"
    echo "  set cookie <COOKIE>    — установить куку"
    echo "  target                 — показать текущую цель"
    echo "  cookie                 — показать текущую куку"
    echo ""
    echo "  add <CHAR>             — добавить разделитель"
    echo "  remove <CHAR>          — удалить разделитель"
    echo "  delimiters             — показать список разделителей"
    echo "  extensions             — показать список расширений"
    echo ""
    echo "  fire                   — обстрел ВСЕМИ разделителями"
    echo "  fire_single <CHAR>     — обстрел одним разделителем"
    echo ""
    echo "  check [URL]            — проверить доступность цели или URL"
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
    
    # Если цель не задана — спрашиваем
    if [[ -z "$TARGET" ]]; then
        read -p "🎯 Цель (например, http://localhost:8080/profile): " TARGET
    fi
    
    # Если кука не задана — спрашиваем
    if [[ -z "$COOKIE" ]]; then
        read -p "🍪 Кука (опционально, Enter чтобы пропустить): " COOKIE
    fi
    
    echo ""
    echo -e "${GREEN}[+] Цель: $TARGET${NC}"
    echo -e "${GREEN}[+] Кука: ${COOKIE:-НЕТ}${NC}"
    echo ""
    
    # Проверяем доступность цели
    check_target || echo -e "${YELLOW}[*] Продолжаю (можешь сменить цель через set target)${NC}"
    
    echo ""
    echo -e "${CYAN}Введи 'help' для списка команд, 'fire' для обстрела${NC}"
    
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
            "target")
                show_target
                ;;
            "cookie")
                show_cookie
                ;;
            "add")
                if [[ -n "$arg1" ]]; then
                    add_delimiter "$arg1"
                else
                    echo -e "${RED}Используй: add <разделитель>${NC}"
                fi
                ;;
            "remove")
                if [[ -n "$arg1" ]]; then
                    remove_delimiter "$arg1"
                else
                    echo -e "${RED}Используй: remove <разделитель>${NC}"
                fi
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
                # пустой ввод — игнорируем
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