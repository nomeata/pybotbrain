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

def get_state(botname):
    result = table.get_item(Key={'bot': botname, 'id': 'state'})
    if 'Item' in result:
        return json.loads(result['Item']['state'])
    else:
        return {}

def set_state(botname, new_state):
    table.put_item(
        Item={'bot':botname, 'id': 'state', 'state': json.dumps(new_state) }
    )

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

def note_event(botname, e):
    #logger.warn("Exception encountered: %s", e)

    # this should ideally be different dynamodb items,
    # with a TTL and fetched with a query
    # or at least shorten the event list…
    e['when'] = int(time.time())
    table.update_item(
        Key = { 'bot':botname,  'id': 'events' },
        UpdateExpression = "SET events = list_append(:vals, if_not_exists(events, :empty))",
        ExpressionAttributeValues = {
            ":vals" : [ e ],
            ":empty": []
        }
    )

def get_events(botname):
    result = table.get_item(Key={'bot': botname, 'id':'events'})
    if "Item" in result:
        events = result['Item']['events']
        for e in events:
            # remove Decimal wrapper, doesn’t work with json.dumps
            e['when'] = int(e['when'])
        return events
    else:
        return []

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
    return json.dumps({
        'state': pprint.pformat(get_state(botname), indent=2,width=50),
        'events': get_events(botname)
    })

@app.route('/api/test_code', methods=('POST',))
def test_code():
    botname = check_token()
    if not 'new_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing new code data"}), 400))
    new_code = request.json['new_code']
    state = get_state(botname)

    try:
        from types import ModuleType
        mod = ModuleType('botcode')
        mod.memory = state
        exec(compile(new_code,filename = "bot-code.py", mode = 'exec'), mod.__dict__)
        if 'test' in mod.__dict__:
            mod.test()
    except:
        return json.dumps({'error': str(sys.exc_info()[1])})
    else:
        return json.dumps({'error': None})

@app.route('/api/eval_code', methods=('POST',))
def eval_code():
    botname = check_token()
    if not 'mod_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing module code"}), 400))
    if not 'eval_code' in request.json:
        abort(make_response(json.dumps({'error': "Missing eval code"}), 400))
    mod_code = request.json['mod_code']
    eval_code = request.json['eval_code']
    state = get_state(botname)
    e = {}
    e['trigger'] = 'eval'

    f = io.StringIO()
    try:
        with redirect_stdout(f):
            with redirect_stderr(f):
                from types import ModuleType
                mod = ModuleType('botcode')
                mod.memory = state
                exec(compile(mod_code,filename = "bot-code.py", mode = 'exec'), mod.__dict__)
                ret = exec(compile(eval_code,filename = "eval-code.py", mode = 'single'), mod.__dict__)
    except:
        exception = str(sys.exc_info()[1])
        e['exception'] = exception
        note_event(botname, e)
        return json.dumps({'output': exception})
    else:
        set_state(botname, state)
        note_event(botname, e)
        return json.dumps({'output':f.getvalue() })

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
    state = get_state(botname)
    mod_code = get_user_code(botname)
    response = None
    e = {}
    e['trigger'] = update.message.chat.type
    e['from'] = update.message.from_user.first_name
    e['text'] = update.message.text
    try:
        from types import ModuleType
        mod = ModuleType('botcode')
        mod.memory = state
        exec(mod_code, mod.__dict__)
        if update.message.chat.type == 'private':
            if 'private_message' in mod.__dict__:
                response = mod.private_message(update.message.from_user.first_name, update.message.text)

        elif update.message.chat.type == 'group':
            if 'group_message' in mod.__dict__:
                response = mod.group_message(update.message.from_user.first_name, update.message.text)
    except:
        e['exception'] = str(sys.exc_info()[1])
    else:
        if response is not None:
            e['response'] = response
            context.bot.send_message(chat_id = update.message.chat.id, text = response)
        set_state(botname, state)
    note_event(botname, e)

def login(botname, update, context):
    id = update.message.from_user.id
    settings = get_bot_settings(botname)
    if id in settings['admins']:
        note_event(botname, {'trigger' : "login"})
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
