#!/bin/bash
# wcd_gun.sh — пулемёт для тестирования WCD-защиты
# Версия: 1.0
# Расположение: wcd_flask_test/tools/

TARGET=""
COOKIE=""
DELIMITERS=(";" "." "?" "%00" "%23" "%3F" "%0A" "%09" "%20")
EXTENSIONS=(".css" ".js" ".jpg" ".ico")

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

banner() {
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${BLUE}🔫 WCD GUN v1.0 — пулемёт для тестирования Web Cache Deception${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo -e "  🎯 Target: ${GREEN}${TARGET:-НЕ ЗАДАН}${NC}"
    echo -e "  🍪 Cookie: ${YELLOW}${COOKIE:-НЕТ}${NC}"
    echo ""
}

check_target() {
    if [[ -z "$TARGET" ]]; then
        echo -e "${RED}[!] Цель не задана. Используй set target <URL>${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}[*] Проверяю доступность $TARGET...${NC}"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET")
    
    if [[ "$http_code" =~ ^(200|302|301|401|403)$ ]]; then
        echo -e "${GREEN}[+] Цель доступна (HTTP $http_code)${NC}"
        return 0
    else
        echo -e "${RED}[!] Цель недоступна или вернула HTTP $http_code${NC}"
        return 1
    fi
}

fire() {
    if ! check_target; then
        return
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
            
            # Формируем URL
            attack_url="${TARGET}${delim}test${ext}"
            
            # Первый запрос (прогрев кэша или bypass)
            curl -s -o /dev/null -b "$COOKIE" "$attack_url"
            sleep 0.2
            
            # Второй запрос (проверяем статус кэша)
            cache_status=$(curl -s -I -b "$COOKIE" "$attack_url" 2>/dev/null | grep -i "X-Cache-Status" | awk '{print $2}' | tr -d '\r')
            http_code=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE" "$attack_url")
            
            # Вывод результата
            printf "[%3d/%3d] " $current $total_tests
            
            if [[ "$cache_status" == "HIT" ]]; then
                echo -e "${RED}[!] ПРОБИТИЕ!${NC} $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${RED}$cache_status${NC}"
            elif [[ "$cache_status" == "BYPASS" ]]; then
                echo -e "${GREEN}[✓] ЗАЩИТА${NC}   $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${GREEN}$cache_status${NC}"
            elif [[ "$cache_status" == "MISS" ]]; then
                echo -e "${YELLOW}[?] MISS${NC}     $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${YELLOW}$cache_status${NC} (повтори fire)"
            else
                echo -e "    [ ]          $attack_url"
                echo -e "         → HTTP $http_code, Cache: ${cache_status:-нет заголовка}"
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

fire_single() {
    # Обстрел одного конкретного разделителя
    if [[ -z "$1" ]]; then
        echo "Используй: fire_single <разделитель>"
        return
    fi
    
    local delim="$1"
    
    echo ""
    echo -e "${YELLOW}[*] Обстрел разделителя: '$delim'${NC}"
    
    for ext in "${EXTENSIONS[@]}"; do
        attack_url="${TARGET}${delim}test${ext}"
        
        curl -s -o /dev/null -b "$COOKIE" "$attack_url"
        sleep 0.2
        
        cache_status=$(curl -s -I -b "$COOKIE" "$attack_url" 2>/dev/null | grep -i "X-Cache-Status" | awk '{print $2}' | tr -d '\r')
        
        if [[ "$cache_status" == "HIT" ]]; then
            echo -e "  ${RED}[!] $attack_url → $cache_status${NC}"
        else
            echo -e "  ${GREEN}[✓] $attack_url → $cache_status${NC}"
        fi
    done
}

set_target() {
    TARGET="$1"
    echo -e "${GREEN}[+] Цель установлена: $TARGET${NC}"
}

set_cookie() {
    COOKIE="$1"
    echo -e "${GREEN}[+] Кука установлена: $COOKIE${NC}"
}

add_delimiter() {
    DELIMITERS+=("$1")
    echo -e "${GREEN}[+] Разделитель добавлен: $1${NC}"
}

remove_delimiter() {
    local new_array=()
    for d in "${DELIMITERS[@]}"; do
        if [[ "$d" != "$1" ]]; then
            new_array+=("$d")
        fi
    done
    DELIMITERS=("${new_array[@]}")
    echo -e "${YELLOW}[-] Разделитель удалён: $1${NC}"
}

show_delimiters() {
    echo ""
    echo -e "${BLUE}Текущие разделители:${NC}"
    local i=1
    for d in "${DELIMITERS[@]}"; do
        echo "  $i) $d"
        ((i++))
    done
    echo ""
}

show_extensions() {
    echo ""
    echo -e "${BLUE}Текущие расширения:${NC}"
    for e in "${EXTENSIONS[@]}"; do
        echo "  - $e"
    done
    echo ""
}

help() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}📖 ДОСТУПНЫЕ КОМАНДЫ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
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
    echo "  check                  — проверить доступность цели"
    echo "  clear                  — очистить экран"
    echo "  help                   — это сообщение"
    echo "  exit                   — выход"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

main() {
    banner
    
    while true; do
        echo ""
        read -p "wcd-gun > " cmd arg1 arg2
        
        case $cmd in
            "set")
                case $arg1 in
                    "target") set_target "$arg2" ;;
                    "cookie") set_cookie "$arg2" ;;
                    *) echo "Используй: set target <URL> или set cookie <COOKIE>" ;;
                esac
                ;;
            "target")
                echo "Текущая цель: ${TARGET:-НЕ ЗАДАНА}"
                ;;
            "cookie")
                echo "Текущая кука: ${COOKIE:-НЕТ}"
                ;;
            "add")
                if [[ -n "$arg1" ]]; then
                    add_delimiter "$arg1"
                else
                    echo "Используй: add <разделитель>"
                fi
                ;;
            "remove")
                if [[ -n "$arg1" ]]; then
                    remove_delimiter "$arg1"
                else
                    echo "Используй: remove <разделитель>"
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
                check_target
                ;;
            "clear")
                banner
                ;;
            "help")
                help
                ;;
            "exit"|"quit")
                echo -e "${YELLOW}Выключаю пулемёт...${NC}"
                exit 0
                ;;
            "")
                # пустой ввод — игнорируем
                ;;
            *)
                echo -e "${RED}Неизвестная команда. help — список команд${NC}"
                ;;
        esac
    done
}

# === ТОЧКА ВХОДА ===

# Спрашиваем цель, если не задана
if [[ -z "$TARGET" ]]; then
    read -p "🎯 Цель (например, http://localhost:8080/profile): " TARGET
fi

# Спрашиваем куку, если не задана
if [[ -z "$COOKIE" ]]; then
    read -p "🍪 Кука (опционально, Enter чтобы пропустить): " COOKIE
fi

echo ""
echo -e "${GREEN}[+] Цель: $TARGET${NC}"
echo -e "${GREEN}[+] Кука: ${COOKIE:-НЕТ}${NC}"
echo ""

# Проверяем цель перед запуском
if ! check_target; then
    echo -e "${RED}[!] Не могу подключиться к цели. Проверь, что Nginx и Flask запущены.${NC}"
    echo -e "${YELLOW}[*] Продолжаю в интерактивном режиме (можешь сменить цель через set target)${NC}"
fi

echo ""
echo -e "${BLUE}Введи 'help' для списка команд, 'fire' для обстрела${NC}"

# Запускаем главный цикл
main