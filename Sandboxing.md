Sandboxing the user’s code
==========================

This project runs possibly bad or even malicious Python code, and needs to take
precautions. This file documents threat models and the considered and taken mitigations.

Threat model
------------

Running untrusted Python code on Amazon Lambda can

 * Use the Amazon Lambda’s AWS credentials to interact with other AWS services
   (e.g. DynamoDB)

   In particular, unrestricted access to DynamoDB allows them to exflitrate
   other user’s Bot’s tokens, and read the data of other bots.

 * Exfiltrate the service’s secret key (`backend/secrets.py`), and use that to
   log in as other users, playing pranks or possibly reading somewhat
   confidential data.

 * Use large amount of resources on Amazon Lambda, causing unexpected costs.

 * Connect to the wider internet and do “bad things”

   (But note that general web access from the bot code can also be a feature.)

Mitigations
-----------

At a high level, the mitigations involve:

 * Setting a restrictive role for the Amazon Lambda

   To be done!

   See https://github.com/Miserlou/Zappa/issues/244 and https://github.com/Miserlou/Zappa/issues/2079

 * Setting resource limits for Amazon Lambda, to cap costs (at the expense of service downtime)
   To be investigated.

 * Sandbox the python code.

   This should prevent the python code from

   * Accessing the main process’s environment, to protect the AWS token.
   * Accessing the `secret.py`, to protect the secret.
   * Messing with the Amazon Lambda execution environment in other ways.

   Malicious code execution is already restricted to
   `backend/sandbox/sandbox.py`, which communicated via stdin/stdout, so both
   Python-specific and process-generic mechanims can be used.

   Currently using the separate Amazon Lambda function approach.

Sandboxing with seccomp
-----------------------

Experimenting with `libseccomp`, it seems possible to white-list system calls
so that writing files (besides stdout) is allowed, but not much else.

Opening files and directories for reading is still needed to allow python
module imports; so probably needs to prevent access to `/proc` and
`secrets.py`. Not done yet.

In any case, this is disqualified because Amazon Lambda doesn’t support
libseccomp: https://stackoverflow.com/q/65544828/946226

Sandboxing with RustPython/Wasm
-------------------------------

It is rather straight-forward to sandbox Python code by running it with a
Wasm-build of [RustPython], so that all the sandboxing properties of Wasm apply
(capabilities). Because the python standard libary is embedded in the Wasm
program, only the `sandbox/` directory needs to be whitelisted using wasmtime’s
capability-based security mechanism.

This also disables network access, at least [for
now](https://github.com/WebAssembly/WASI/pull/312). This is both good and bad.

`wasmtime` also supports a timeout mechanism (although unclear if it really
excludes the time to compile the module).

This works, seems to be secure, but it is not fully satisfying because of the
rather high latency, expecially for the first invokation of an Amazon Lambda
instance. Also, the Function package is getting closer to the 50MB limit.

This was inspired by https://github.com/robot-rumble/logic/ (but is arguably
simpler, by using `rustpython.wasm` and `wasmtime` unmodified, instead of
building custom programs that use these as libraries).

I used this briefly; see the git history for code and details.

Sandboxing via a separate Amazon Lambda function
------------------------------------------------

A third option is to rely on Amazon Lambda itself for sandboxing.  Using a
separate Amazon Lambda function purely for evaluating code can isolate that
from the storage system, and could have a very restricted execution role,
addressing most attacks above.

Because of execution environment re-use, there is still the risk of malicious
code surviving until the next invocation, and messing with that response.

Maybe that can be prevented (the Amazon Lambda Execution enviornment file
system is already read-only).

If that is still an issue, a separate Amazon Lambda function per user (i.e. per
bot) could be created automatically; it seems the cost model of AWS makes that
possible. (Thanks to https://twitter.com/felixhuttmann for that suggestion).

Also adds latency, much much less than RustPython/Wasm.
