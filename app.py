from functools import partial
import string
import random
import sys
import uuid
import time
import json
import datetime

import boto3
from boto3.dynamodb.conditions import *

from flask import Flask
from flask import request, abort, render_template, redirect, url_for

from telegram import Update, Bot
from telegram.ext import CommandHandler, MessageHandler, Filters, Dispatcher, Updater

import logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO
)
logger = logging.getLogger(__name__)


app = Flask(__name__)
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
        }
    )

def define_bot(botname, token, admins):
    table.put_item( Item={
        'bot':botname,
        'id': 'settings',
        'token': token,
        'admins': admins
    })

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
        return "def direct_message(sender, text):\n    return f\"Hello {sender}!\"\n"

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

def get_pws(botname):
    result = table.get_item(Key={'bot': botname, 'id': 'pw'})
    if 'Item' in result:
        return result['Item']['pws']
    else:
        abort(403, "No password set, please /login first")

def add_pw(botname, pw):
    table.update_item(
        Key = { 'bot':botname,  'id': 'pw' },
        UpdateExpression = "SET pws = list_append(:vals, if_not_exists(pws, :empty))",
        ExpressionAttributeValues = {
            ":vals" : [ pw ],
            ":empty": []
        }
    )

def note_error(botname, e):
    logger.warn("Exception encountered: %s", e)
    table.update_item(
        Key = { 'bot':botname,  'id': 'errors' },
        UpdateExpression = "SET errors = list_append(:vals, if_not_exists(errors, :empty))",
        ExpressionAttributeValues = {
            ":vals" : [ { "when": int(time.time()), "msg": str(e) } ],
            ":empty": []
        }
    )

def last_errors(botname):
    result = table.get_item(Key={'bot': botname, 'id':'errors'})
    if "Item" in result:
        errs = result['Item']['errors']
        for e in errs:
            e['when'] = datetime.datetime.fromtimestamp(e['when'])
        return errs
    else:
        return []


@app.route('/edit_code/<botname>', methods=('GET', 'POST'))
def edit_code(botname):
    settings = get_bot_settings(botname)
    pw = request.cookies.get(f"bot-{botname}-pw")
    print("cookie:", pw)
    pws = get_pws(botname)
    if not pw or pw not in pws:
        err = ""
        if request.method == 'POST' and 'pw' in request.form:
            pw = request.form['pw']
            if pw in pws:
                resp = redirect(url_for('edit_code', botname = botname))
                resp.set_cookie(f"bot-{botname}-pw", pw)
                return resp
            err = "Sorry, wrong code"
        return render_template('login.html', err = err)

    if request.method == 'POST':
        if 'code' in request.form:
            set_user_code(botname, request.form['code'])
            return redirect(url_for('edit_code', botname = botname))
        if 'eval' in request.form:
            eval_user_code(botname, request.form['eval'])
            return redirect(url_for('edit_code', botname = botname))
        if 'logout' in request.form:
            resp = redirect(url_for('edit_code', botname = botname))
            resp.delete_cookie(f"bot-{botname}-pw")
            return resp

    return render_template('edit_code.html',
        code = get_user_code(botname),
        state = get_state(botname),
        errors = last_errors(botname)
    )

def eval_user_code(botname, code):
    state = get_state(botname)
    mod_code = get_user_code(botname)
    try:
        from types import ModuleType
        mod = ModuleType('botcode')
        mod.memory = state
        exec(mod_code, mod.__dict__)
        exec(code, mod.__dict__)
    except:
        note_error(botname, sys.exc_info()[1])
    else:
        set_state(botname, state)

def echo(botname, update, context):
    state = get_state(botname)
    mod_code = get_user_code(botname)
    try:
        from types import ModuleType
        mod = ModuleType('botcode')
        mod.memory = state
        exec(mod_code, mod.__dict__)
        response = mod.direct_message(update.message.from_user.first_name, update.message.text)
    except:
        note_error(botname, sys.exc_info()[1])
    else:
        if response is not None:
            update.message.reply_text(response)
        set_state(botname, state)

def login(botname, update, context):
    id = update.message.from_user.id
    settings = get_bot_settings(botname)
    if id in settings['admins']:
        pw = ''.join(random.SystemRandom().choice(string.ascii_uppercase) for _ in range(6))
        add_pw(botname, pw)
        update.message.reply_text(f"Welcome back! Your password is {pw}\nUse this at https://bot.nomeata.de/edit_code/{botname}")
    else:
        update.message.reply_text(f"Sorry, but you are not my owner!\n(Your id is {update.message.from_user.id})")

def add_handlers(botname, dp):
    dp.add_handler(CommandHandler("login", partial(login, botname), filters = Filters.chat_type.channel))
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

@app.route("/")
def index():
    return "Hello"

# run a local bot handler
def local(botname):
    settings = get_bot_settings(botname)
    bot = Bot(token = settings['token'])
    updater = Updater(bot = bot, use_context = True)
    add_handlers(botname, updater.dispatcher)
    updater.start_polling()
    updater.idle()
