#!/usr/bin/env python3
from flask import Flask

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
    response.headers['X-Backend-Version'] = 'flask-1.0'
    return response

@app.route('/profile')
@app.route('/profile/')
@app.route('/profile/user.json')
def profile_index():
    return "PRIVATE: admin api-key=WCD-SECRET-12345"

@app.route('/profile/<path:anything>')
def profile_with_path(anything):
    return "PRIVATE: admin api-key=WCD-SECRET-12345"

@app.route('/test')
def test():
    return "test"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
