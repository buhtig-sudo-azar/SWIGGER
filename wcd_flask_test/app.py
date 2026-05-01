#!/usr/bin/env python3
from flask import Flask, request, redirect

app = Flask(__name__)

# Middleware для обрезки ;
class WCDMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = environ.get('PATH_INFO', '')
        if ';' in path:
            environ['PATH_INFO'] = path.split(';')[0]
        return self.app(environ, start_response)

app.wsgi_app = WCDMiddleware(app.wsgi_app)

@app.after_request
def add_backend_headers(response):
    response.headers['X-Backend-Version'] = 'flask-2.0'
    return response

# Проверка куки
def check_auth():
    cookie = request.cookies.get('session', '')
    return cookie == 'valid'

# Защищённый маршрут — только с кукой
@app.route('/profile')
@app.route('/profile/')
def profile_index():
    if not check_auth():
        return redirect('/login', 302)
    return "PRIVATE: admin api-key=WCD-SECRET-12345"

# Защищённый catch-all — только с кукой
@app.route('/profile/<path:anything>')
def profile_with_path(anything):
    if not check_auth():
        return redirect('/login', 302)
    return "PRIVATE: admin api-key=WCD-SECRET-12345"

# Публичный маршрут
@app.route('/test')
def test():
    return "test"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)