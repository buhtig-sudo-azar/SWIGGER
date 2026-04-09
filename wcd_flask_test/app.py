from flask import Flask, request

app = Flask(__name__)

class StripSemicolonMiddleware:
    def __init__(self, app):
        self.app = app
    
    def __call__(self, environ, start_response):
        # environ['PATH_INFO'] — это сырой путь от сервера
        path = environ.get('PATH_INFO', '')
        if ';' in path:
            environ['PATH_INFO'] = path.split(';')[0]
        return self.app(environ, start_response)

app.wsgi_app = StripSemicolonMiddleware(app.wsgi_app)

@app.route('/profile')
def profile():
    return "PRIVATE: admin api-key=WCD-SECRET-12345"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)