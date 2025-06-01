from flask import render_template, request, jsonify
from app import app
import os

@app.route('/')
def index():
    """
    Home page route.
    """
    return "Hello, World"

@app.route('/hello/<name>')
def hello(name):
    """
    Renders a personalized hello page.
    """
    return render_template('hello.html', name=name)

@app.route('/greet', methods=['GET', 'POST'])
def greet():
    """
    Displays a form (GET) and greets the user by name (POST).
    """
    if request.method == 'POST':
        name = request.form.get('name', 'Guest')
        return render_template('hello.html', name=name)
    return render_template('greet_form.html')

@app.route('/version')
def version():
    """
    Returns JSON containing the Git SHA and build date injected at build time.
    """
    return jsonify({
        "git_sha": os.getenv("GIT_SHA", "unknown"),
        "build_date": os.getenv("BUILD_DATE", "n/a")
    })
