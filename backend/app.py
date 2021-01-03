from functools import partial
import string
import random
import sys
import uuid
import time
import json
import datetime
import pprint
import io
import os
import subprocess
from contextlib import redirect_stdout, redirect_stderr

import boto3
from boto3.dynamodb.conditions import *

from flask import Flask
from flask import request, abort, redirect, make_response, send_from_directory
import jwt

from telegram import Update, Bot
from telegram.ext import CommandHandler, MessageHandler, Filters, Dispatcher, Updater

import logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO
)
logger = logging.getLogger(__name__)


app = Flask(__name__)
app.config.from_pyfile('secrets.py')
app.config['TEMPLATES_AUTO_RELOAD'] = True

dynamodb = boto3.resource('dynamodb', region_name='eu-central-1')
table = dynamodb.Table('python-bot')

# def remote():
#     bot.send_message(chat_id=77633402, text="I was just deployed")
#     bot.send_photo(chat_id=77633402, photo="https://api.kaleidogen.nomeata.de/img/0FE345673449ABCDEF.png")

def delete_table():
    table.delete()

def create_table():
    table = dynamodb.create_table(
        TableName='python-bot',
        KeySchema=[
            { 'AttributeName': 'bot', 'KeyType': 'HASH' },
            { 'AttributeName': 'id', 'KeyType': 'RANGE' },
        ],
        AttributeDefinitions=[
            { 'AttributeName': 'bot', 'AttributeType': 'S' },
            { 'AttributeName': 'id', 'AttributeType': 'S' },
        ],
        ProvisionedThroughput={
            'ReadCapacityUnits': 10,
            'WriteCapacityUnits': 10
        },
        TimeToLiveDescription = {
            'AttributeName': 'ttl',
            'TimeToLiveStatus': 'ENABLED'
        }
    )

def define_bot(botname, token, admins):
    table.put_item( Item={
        'bot':botname,
        'id': 'settings',
        'token': token,
        'admins': admins
    })
    set_webhook(botname)

def get_bot_settings(botname):
    result = table.get_item(Key={'bot': botname, 'id': 'settings'})
    if 'Item' in result:
        return result['Item']
    else:
        raise abort(404,f"No bot {botname} known.")

def set_user_code(botname, new_code):
    table.put_item( Item={'bot':botname, 'id': 'code', 'code': new_code })

def get_user_code(botname):
    result = table.get_item(Key={'bot': botname, 'id': 'code'})
    if 'Item' in result:
        return result['Item']['code']
    else:
        return "def private_message(sender, text):\n    return f\"Hello {sender}!\"\n"

def set_user_code(botname, new_code):
    table.put_item(
        Item={'bot':botname, 'id': 'code', 'code': new_code }
    )

def get_raw_state(botname):
    result = table.get_item(Key={'bot': botname, 'id': 'state'})
    if 'Item' in result:
        return result['Item']['state']
    else:
        return '{}'

def get_state(botname):
    return json.loads(get_raw_state(botname))

def set_raw_state(botname, new_state):
    table.put_item(
        Item={'bot':botname, 'id': 'state', 'state': new_state }
    )

def set_state(botname, new_state):
    set_raw_state(botname, json.dumps(new_state))

def check_pw(pw):
    result = table.get_item(Key={'bot': '#pwds', 'id': pw})
    if 'Item' in result:
        return result['Item']['botname']
    else:
        return None

def add_pw(botname, pw):
    exp = datetime.datetime.now() + datetime.timedelta(minutes=5)
    table.put_item(Item={
        'bot':"#pwds",
        'id': pw,
        'botname': botname,
        'ttl': int(exp.timestamp())
    })

def note_event(botname, e, id_hint = 0):
    timestamp = int(time.time())

    e['bot'] = botname
    e['id'] = f"event#{timestamp:010}#{id_hint:010}"
    e['when'] = int(timestamp)
    table.put_item(Item = e)

def get_events(botname):
    result = table.query(
       KeyConditionExpression=
        Key('bot').eq(botname) &
        Key('id').begins_with("event#"),
        ScanIndexForward = False,
        Limit = 10
    )
    events = result['Items']
    for e in events:
        # remove Decimal wrapper, doesn’t work with json.dumps
        e['when'] = int(e['when'])
    return events, 'LastEvaluatedKey' in result

@app.route('/api/login', methods=('POST',))
def api_login():
    if not request.json or not 'password' in request.json:
        abort(make_response(json.dumps({'error': "Missing login data"}), 400))

    botname = check_pw(request.json['password'])

    if botname is None:
        abort(make_response(json.dumps({'error': f'Sorry, invalid password. Ask the bot with /login!'}), 403))

    iat = datetime.datetime.utcnow()
    # for now, lets simply not expire them
    #exp = iat + datetime.timedelta(hours=12)
    nbf = iat
    payload = {'iat': iat, 'nbf': nbf, 'botname': botname}
    secret = app.config['SECRET_KEY']
    token = jwt.encode(payload, secret)
    return json.dumps({'token' : token.decode('utf-8')})

def check_token():
    header = request.headers.get('Authorization', None)

    if not header:
        abort(401, "Missing JWT header")

    if not header.lower().startswith("bearer "):
        abort(401, "Wrong authentication type ")

    secret = app.config['SECRET_KEY']
    token = header[7:]
    try:
        payload = jwt.decode(token, secret)
        return payload['botname']
    except jwt.InvalidTokenError as e:
        abort(401, f"Invalid token: {e}")

@app.route('/api/get_code', methods=('POST',))
def get_code():
    botname = check_token()
    return json.dumps({
        'botname': botname,
        'code': get_user_code(botname)
    })

@app.route('/api/get_state', methods=('POST',))
def api_get_state():
    botname = check_token()
    events, has_more = get_events(botname)
    return json.dumps({
        'state': pprint.pformat(get_state(botname), indent=2,width=50),
        'events': events,
        'has_more' : has_more
    })

# This function wraps the sandbox.py program.
# It communicates via stdin/stdout and json
def sandbox(inp):
    env = {}
    for v in []: # environment variables to preserve
        if v in os.environ:
            env[v] = os.environ[v]
    result = subprocess.run(
      ["./vendor/wasmtime", "run", "--config", "wasmtime.toml", "--dir", "sandbox", "./vendor/rustpython.wasm", "--", "sandbox/sandbox.py"],
      # ["python3", "sandbox.py"],
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      env=env,
      input=json.dumps(inp).encode('utf8')
    )
    if result.returncode == 0:
        return json.loads(result.stdout)
    elif result.returncode == 134:
        print(result.stdout.decode('utf-8'))
        print(result.stderr.decode('utf-8'))
        return { 'error': 'Program aborted (timeout?)' }
    else:
        print(result.stdout.decode('utf-8'))
        print(result.stderr.decode('utf-8'))
        return { 'error': 'Program failed' }

@app.route('/api/eval_code', methods=('POST',))
def eval_code():
    botname = check_token()
    if not 'mod_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing module code"}), 400))
    if not 'eval_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing eval code"}), 400))
    out = sandbox({
        'code' : request.json['mod_code'],
        'eval' : request.json['eval_code'],
        'state': get_raw_state(botname),
    })

    e = {}
    e['trigger'] = 'eval'

    if 'new_state' in out:
        set_raw_state(botname, out['new_state'])

    if 'output' in out:
        ret = {'output': out['output']}
    elif 'exception' in out:
        e['exception'] = out['exception']
        ret = {'output': out['exception']}
    elif 'error' in out:
        # this is more an internal error
        e['exception'] = out['error']
        ret = {'output': out['error']}
    else:
        # this is more an internal error
        e['exception'] = "Unexpected result from sandbox()"
        ret = {'output': "Internal error: Unexpected result from sandbox()"}

    note_event(botname, e)
    return json.dumps(ret)

@app.route('/api/test_code', methods=('POST',))
def test_code():
    botname = check_token()
    if not 'new_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing new code data"}), 400))
    new_code = request.json['new_code']
    state = get_state(botname)

    out = sandbox({
        'code' : request.json['new_code'],
        'test' : True,
        'state': get_raw_state(botname),
    })
    return json.dumps({'error': out['error']})

@app.route('/api/set_code', methods=('POST',))
def set_code():
    botname = check_token()
    if not 'new_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing new code data"}), 400))
    set_user_code(botname, request.json['new_code'])
    return json.dumps({})

@app.route("/")
def index():
    return redirect("/admin/")

@app.route('/admin')
def send_frontend_index_redir():
    return redirect("/admin/")

@app.route('/admin/')
def send_frontend_index():
    return send_from_directory('frontend', 'index.html')

@app.route('/admin/<path:path>')
def send_frontend_file(path):
    return send_from_directory('frontend', path)


def echo(botname, update, context):
    out = sandbox({
        'code' : get_user_code(botname),
        'message' : update.message.chat.type,
        'sender' : update.message.from_user.first_name,
        'text' : update.message.text,
        'state': get_raw_state(botname),
    })

    if 'new_state' in out:
        set_raw_state(botname, out['new_state'])

    e = {}
    e['trigger'] = update.message.chat.type
    e['from'] = update.message.from_user.first_name
    e['text'] = update.message.text

    if 'response' in out:
        response = out['response']
        if response is not None:
            e['response'] = response
            context.bot.send_message(chat_id = update.message.chat.id, text = response)
    elif 'exception' in out:
        e['exception'] = out['exception']
    elif 'error' in out:
        e['exception'] = out['error']
    else:
        e['exception'] = "Internal error: Unexpected data from sandbox()"

    note_event(botname, e, update.update_id)

def login(botname, update, context):
    id = update.message.from_user.id
    settings = get_bot_settings(botname)
    if id in settings['admins']:
        note_event(botname, {'trigger' : "login", 'from': update.message.from_user.first_name}, update.update_id)
        pw = ''.join(random.SystemRandom().choice(string.ascii_uppercase) for _ in range(6))
        add_pw(botname, pw)
        update.message.reply_text(f"Welcome back! Your password is {pw}\nUse this at https://bot.nomeata.de/")
    else:
        update.message.reply_text(f"Sorry, but you are not my owner!\n(Your user id is {update.message.from_user.id}.)")

def add_handlers(botname, dp):
    dp.add_handler(CommandHandler("login", partial(login, botname), filters = Filters.chat_type.private))
    dp.add_handler(MessageHandler(Filters.text, partial(echo, botname)))


@app.route('/telegram-webhook/<botname>/<arg_token>', methods=["GET", "POST"])
def webhook(botname, arg_token):
    settings = get_bot_settings(botname)
    if arg_token != settings['token']:
        abort(403, "Wrong token")
    bot = Bot(token = settings['token'])
    # decode update and try to process it
    dp = Dispatcher(bot, None, workers=0, use_context = True)
    add_handlers(botname, dp)
    update = Update.de_json(request.json, bot)
    dp.process_update(update)
    return ""

@app.route("/delete_webhook/<botname>")
def delete_webhook(botname):
    settings = get_bot_settings(botname)
    bot = Bot(token = settings['token'])
    bot.delete_webhook()
    print("Web hook deleted")
    return "Web hook deleted"

@app.route("/set_webhook/<botname>")
def set_webhook(botname):
    settings = get_bot_settings(botname)
    bot = Bot(token = settings['token'])
    url = f"https://bot.nomeata.de/telegram-webhook/{botname}/{bot.token}"
    bot.set_webhook(url = url)
    print(f"Web hook set to {url}")
    return f"Web hook set to {url}"

# run a local bot handler
def local(botname):
    settings = get_bot_settings(botname)
    bot = Bot(token = settings['token'])
    updater = Updater(bot = bot, use_context = True)
    add_handlers(botname, updater.dispatcher)
    updater.start_polling()
    updater.idle()
