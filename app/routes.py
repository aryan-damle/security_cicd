from flask import render_template, request
from app import app

@app.route('/')
def index():
    return "Hello, World"

@app.route('/hello/<name>')
def hello(name):
    return render_template('hello.html', name=name)

@app.route('/greet', methods=['GET', 'POST'])
def greet():
    if request.method == 'POST':
        name = request.form.get('name', 'Guest')
        return render_template('hello.html', name=name)
    return render_template('greet_form.html')