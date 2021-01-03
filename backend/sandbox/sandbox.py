if False:
    # no seccomp on Amazon Lambda :-(
    import os, sys, errno
    from pyseccomp import *

    f = SyscallFilter(defaction=KILL)

    f.add_rule(ALLOW, "open",
                   Arg(1, MASKED_EQ, os.O_RDONLY,
                       os.O_RDONLY | os.O_RDWR | os.O_WRONLY))
    f.add_rule(ALLOW, "openat",
                   Arg(2, MASKED_EQ, os.O_RDONLY,
                       os.O_RDONLY | os.O_RDWR | os.O_WRONLY))
    f.add_rule(ALLOW, "read")
    f.add_rule(ALLOW, "write", Arg(0, EQ, sys.stdout.fileno()))
    f.add_rule(ALLOW, "write", Arg(0, EQ, sys.stderr.fileno()))
    f.add_rule(ALLOW, "close")
    f.add_rule(ALLOW, "getdents64")
    f.add_rule(ALLOW, "exit_group")
    f.add_rule(ALLOW, "rt_sigaction")
    f.add_rule(ALLOW, "sigaltstack")
    f.add_rule(ALLOW, "brk")
    f.add_rule(ALLOW, "lseek")
    f.add_rule(ALLOW, "fstat")
    f.add_rule(ALLOW, "mmap")
    f.add_rule(ALLOW, "mprotect")
    f.add_rule(ALLOW, "stat")
    f.add_rule(ALLOW, "ioctl", Arg(1, EQ, 0x5401)) # TCGETS
    f.add_rule(ALLOW, "fcntl")

    f.load()

from contextlib import redirect_stdout, redirect_stderr
import traceback
import io, sys
import json

data = json.load(sys.stdin)
if 'eval' in data:
    mod_code = data['code']
    eval_code = data['eval']
    state = json.loads(data['state'])
    f = io.StringIO()
    try:
        with redirect_stdout(f):
            with redirect_stderr(f):
                from types import ModuleType
                mod = ModuleType('botcode')
                mod.memory = state
                exec(compile(mod_code,"bot-code.py",'exec'), mod.__dict__)
                ret = exec(compile(eval_code,"eval-code.py",'single'), mod.__dict__)
    except:
        exception = traceback.format_exc(limit=-1)
        print(json.dumps({'exception': exception}))
    else:
        print(json.dumps({'output': f.getvalue(), 'new_state' : json.dumps(mod.memory) }))
elif 'message' in data:
    mod_code = data['code']
    sender = data['sender']
    text = data['text']
    state = json.loads(data['state'])
    response = None
    f = io.StringIO()
    try:
        with redirect_stdout(f):
            with redirect_stderr(f):
                from types import ModuleType
                mod = ModuleType('botcode')
                mod.memory = state
                exec(compile(mod_code,"bot-code.py",'exec'), mod.__dict__)
                if data['message'] == 'private':
                    if 'private_message' in mod.__dict__:
                        response = mod.private_message(sender, text)

                elif data['message'] == 'group':
                    if 'group_message' in mod.__dict__:
                        response = mod.group_message(sender, text)
    except:
        exception = traceback.format_exc(limit=-1)
        print(json.dumps({'exception': exception}))
    else:
        print(json.dumps({'response': response, 'new_state' : json.dumps(mod.memory)}))
elif 'test' in data:
    mod_code = data['code']
    state = json.loads(data['state'])
    f = io.StringIO()
    try:
        with redirect_stdout(f):
            with redirect_stderr(f):
                from types import ModuleType
                mod = ModuleType('botcode')
                mod.memory = state
                exec(compile(mod_code,"bot-code.py",'exec'), mod.__dict__)
                if 'test' in mod.__dict__:
                    mod.test()
    except SyntaxError as e:
        exception = str(e)
        print(json.dumps({'error': exception}))
    except:
        exception = traceback.format_exc(limit=-1)
        print(json.dumps({'error': exception}))
    else:
        print(json.dumps({'error': None}))
else:
    print(json.dumps({'error': "Could not find out what to do"}))
