# pybotbrain: Programming a Telegram bot is kinderleicht

This project was created to help with this problem: How can I introduce my
niece and nephew to the wonders of programming? I needed a program environment
that is

 * frictionless, because every bit of annoyance about installing tooling, bad
   editors, annoying red tape (such as having to save and run a command to see
   error messages) take a toll on motivation and attention

 * relevant, so that they can immediatelly build something that is interesting
   and interacts with their world

In this particular case, I decided to make it as easy as possible for them to
program their very own Telegram bot. Using a web-based editor environment,
there is no setup to worry about. Live code checking means that at least
obvious syntax error are caught before they try to press “Deploy”. And already
with very very simple programming skills (`if`, string comparison) the kids can
write, for example, elaborate interactive fiction.

## The service

To that end, I created `pybotbrain`. This is a service running on the internet
that can host any number Telegram bots (i.e. it receives messages to these bots, and responds to them). It allows the “owners” of these bot to program the inner logic of the bot very effortless with the browser, as the following screenshots show.

The bots are programmed in Python, using a very simple programming interface, so that even with rudimentary programming skills, interesting bots can be written.

Interaction with a bot                                        | The web interface
:------------------------------------------------------------:|:--------------------------------------------------------:
![Interaction with a telegram bot](screenshot-telegram.png)   | ![The corresponding control panel](screenshot-admin.png)

## What is the API for the bot’s code?

 * To react to a private message, define a function `def private_message(sender,
   text)`. If you return a string, it will become the bot’s response.

 * To react to a group message, define a function `def group_message(sender,
   text)`. If you return a string, it will become the bot’s response.

 * You can remember things in the `memory` dictionary.

## Can I use it?

Yes you can!

  1. Open a Chat with [@PybotbrainBot](https://t.me/bybotbrainbot)
  2. Send `/newbot` to [@BotFather](https://t.me/botfather)
  3. Answer the questions to pick a name etc.
  4. @BotFather will tell you the Bot’s token, which looks like `110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw`. Send that to @PybotbrainBot (you can just forward the whole message)
  5. Now talk to _your_ bot, and say `/login`
  6. Go to https://bot.nomeata.de/admin/ to login and get started!

Of course, if you already have a Telegram bot, and you want to control it with this, just send its token to `@PybotbrainBot`

## Can I host it myself?

Sure! You do not even need a server for it, just an Amazon WebServices
account, and it will very likely run well within the free tier. See
`./Building.md` for (very rough) instructions.

## Can I contribute?

Sure! Some things on the TODO list are:

 * Write target-audience compatibe documentation

   Some first steps are in `docs/`

 * Make this safer to run

   * Find the minimal AWS policy for the backend Lambda function.
   * Improve the sandbox for the Python execution (see discussion in `./Sandboxing.md`)

 * Prettier UI

   In particular, make the editor window take the full available vertical
   space. Maybe switching from Bulma to a more modern, flexbox-based CSS
   framework might make that easier.

 * Error handling

   In particular in the UI.

 * Sensible polling for events and memory changes

   The Frontend should use not always download the full list of events, but only
   those that are new since the last one.

   Events should probably have a DynamoDB-based time-to-live.

   Memory polling could be done with a ETag-like mechanism.

   Polling should stop when UI is in a background tab.

 * Rewrite the backend in a different language, now that the Python sandboxing
   is its own process, and thus the backend is completely independent of Python.

 * Carefully adding capabilities to the bot

   This will never expose the full complexity of the [Telegram Bot
   API](https://core.telegram.org/bots/api). The goal is to teach programming
   and allow the kids to do many fun and interesting and useful things – not
   necessarily _all_ the things.

   That said, a careful extension of the capabilities, especially if they don’t
   make the first steps more complicated, are useful. Especially important
   features like “sending stickers”.

