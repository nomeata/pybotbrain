#!/usr/bin/env bash

set -e

cd sandbox
rm -f sandbox.zip
zip sandbox.zip sandbox.py
aws lambda update-function-code --region eu-central-1 --profile pybotbrain --function-name python-bot-eval --zip-file fileb://sandbox.zip
rm -f sandbox.zip
