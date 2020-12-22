% Bot-Ideen

# Der einfachste Bot

```python
def private_message(sender, text):
    return "Hallo! Ich bin Ellas Telegram-Bot, aber noch kann ich nicht viel 🤷"
```

# Ein höflicher Bot

```python
def private_message(sender, text):
    return f"Hallo {sender}, wie geht es dir heute?"
```

Beachte das `f` vor dem Anführungszeichen.

# Ein Bot der Ella erkennt

```python
def private_message(sender, text):
    if sender == "Ella":
        return "Stets zu Diensten, meine Herrin und Gebieterin!"
    else:
        return f"Hallo {sender}, wie geht es dir heute?"
```

# Ein Bot der Fragen beantworten kann

```python
def private_message(sender, text):
    if text == "Wie geht es dir?":
        return "Ganz gut, muss ich sagen"
    else:
        return f"Hallo {sender}, wie geht es dir heute?"
```

Gern noch mehr!

# Ein Bot der dich auf eine Reise nimmt:

```python
def private_message(sender, text):
    if text == "Spielplatz":
        return "Der Spielplatz ist toll. Von hier aus kannst du auf die Straße oder in den Wald gehen"
    elif text == "Straße":
        return "Rumms, ein Auto fährt vorbei. Du kannst von hier zum Spielplatz gehen"
    elif text == "Wald":
        return "Es ist kühl und dunkel. Gehst du zum Spielplatz oder zur Höhle?"
    elif text == "Höhle":
        return "Ein Bär hauste hier. Von hier kannst du in den Wald gehen."
    else:
        return "Willkommen zu meiner magischen Welt. Um anzufangen, schreibe \"Spielplatz\"!"
```

Achtung, die Strings `"Rumms … gehen"` sind jeweils in einer einzigen Zeile!

Die Beschreibungen und Orte dürfen gerne noch ausgebaut werden ☺
