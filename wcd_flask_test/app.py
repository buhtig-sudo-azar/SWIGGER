#!/usr/bin/env python3
from flask import Flask, request
import os
import signal
import sys

app = Flask(__name__)

# ===== MIDDLEWARE: ЭМУЛЯЦИЯ SPRING (режет ;) =====
class StripSemicolonMiddleware:
    def __init__(self, app):
        self.app = app
    
    def __call__(self, environ, start_response):
        path = environ.get('PATH_INFO', '')
        if ';' in path:
            environ['PATH_INFO'] = path.split(';')[0]
        return self.app(environ, start_response)

app.wsgi_app = StripSemicolonMiddleware(app.wsgi_app)

# ===== ОСНОВНЫЕ РОУТЫ =====
@app.route('/profile')
def profile():
    return "PRIVATE: admin api-key=WCD-SECRET-12345"

@app.route('/style.css')
def style():
    return "/* legit css */", 200, {'Content-Type': 'text/css'}

# Сюда будешь добавлять новые роуты для тестов
# @app.route('/new-route')
# def new_route():
#     return "test"

# ===== ОБРАБОТЧИКИ СИГНАЛОВ =====
def signal_handler(sig, frame):
    print("\n[!] Получен сигнал завершения. Выключаю Flask...")
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# ===== ОЧИСТКА ПОРТА ПЕРЕД ЗАПУСКОМ =====
PORT = 8081

def kill_process_on_port(port):
    try:
        pid = os.popen(f"lsof -t -i :{port}").read().strip()
        if pid:
            print(f"[!] Порт {port} занят процессом PID {pid}. Убиваю...")
            os.kill(int(pid), signal.SIGKILL)
            print(f"[+] Процесс {pid} уничтожен")
    except Exception:
        pass

kill_process_on_port(PORT)

# ===== ЗАПУСК =====
if __name__ == '__main__':
    print(f"[+] Запускаю Flask на порту {PORT}")
    print("[+] Middleware активен: режет ';' в URL")
    print("[+] Доступные роуты:")
    for rule in app.url_map.iter_rules():
        if rule.endpoint != 'static':
            methods = ','.join(rule.methods - {'HEAD', 'OPTIONS'})
            print(f"      {rule.rule} → {methods}")
    print("[*] Ctrl+C для остановки")
    print("")
    app.run(host='0.0.0.0', port=PORT)