# Building and hacking on pybotbrain

To run your own `pybotbrain` instance, you need an Amazon Web Services account.
I have _not_ tried setting this up from scratch, so these instructions are a
bit vague. If you try to reproduce them, please refine the instructions (and
the code) to make that easier.

## Initial setup

To prepare development, install the dependencies

```
cd backend
python3 -m venv env
. env/bin/activate
pip install -r requirements.txt
cd ..

cd frontend
npm install
npm run build-prod
```

All `python`, `zappa` and `flask` commands below are executed in `backend/`
with a loaded virtual environment; all `npm` and `npx` commands are executed in
`frontend/`

Make sure that `~/.aws/credentials` has a profile `pybotbrain` with an access
key and key id with sufficient permissions (TODO).

In `backend`, run
```
python3 -c 'import os; print(f"SECRET_KEY = {os.urandom(16)}")' > secrets.py
```
to create a secret key (used for authentication). Do not share that.

To create the initial DynamodDB table, run
```
python3 -c 'import app; app.create_table()'
```

Change `domain` to “your” Domain in `zappa_settings.json`, conigure a AWS
certificate for that domain, and set the `certificate_arn` setting accordingly.
Also change the domain in `app.py`.

To deploy the lambda function initally, run
```
zappa deploy
```

## Push new code

In `frontend/`, run
```
npm run build-prod
```
and in `backend/`, run
```
zappa update
```

## Adding bots

To add a bot, register it with [@botfather](https://t.me/BotFather), and run
```
python3 -c 'import app; app.define_bot("NameOfYourBot","1475644043:AA…8", [123456])'
```
where the second argument is the bot’s secret token, and the last argument your Telegram user id (not loginname!).

At this point, you should be able to send `/login` to your bot, and then go to https://bot.nomeata.de/admin/ and login.

## Local development (web parts)

You can work with a local webserver, while still accessing the “real” dynamo DB. To do so:

In `frontend/`, keep running
```
npx pscid
```
to compile the purescript code. Press `b` is you are unsure if it built everything.

In `frontend/`, keep running
```
npm run watch
```

In `backend/`, keep running
```
flask run --reload
```

Open the local port given.

## Local development (telegram parts)

To also handle the telegram messages locally, you have to temporarily disable
the webhook. You can do that for individual bots:
```
python3 -c 'import app;app.delete_webhook("NameOfYourBot")'
```
Now handle messages locally:
```
python3 -c 'import app;app.local("NameOfYourBot")'
```
When done, set the webhook again.
```
python3 -c 'import app;app.set_webhook("NameOfYourBot")'
```

## Vendored files

See `Sandboxing.md` for why these files are needed.

The file `backend/vendor/rustpython.wasm` is produced by running

    git clone https://github.com/RustPython/RustPython.git
    cd RustPython
    cargo build --release --target wasm32-wasi --features="freeze-stdlib"

or could be downloaded from https://wapm.io/package/rustpython#explore, once a
more up-to-date release is there.

The file `backend/vendor/wasmtime` is downloaded and extracted from
https://github.com/bytecodealliance/wasmtime/releases
