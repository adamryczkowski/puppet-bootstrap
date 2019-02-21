#!/usr/bin/env python3

import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("schema", help="gsettings shema", metavar="SCHEMA")
parser.add_argument("key", help="gsettings key", metavar="KEY")
parser.add_argument("index",
                    help="KEY array index where VALUE(s) need to be inserted",
                    metavar="INDEX", type=int)
parser.add_argument("value",
                    help="gsettings VALUE(s) to add to the KEY array",
                    metavar="VALUE", nargs='*')

args = parser.parse_args()

array = eval(subprocess.check_output(["gsettings", "get", args.schema, args.key]))
for v in sorted(args.value, reverse=True):
    try:
        value = eval(v)
    except NameError:
        value = v
    array.insert(args.index, value)
subprocess.call(["gsettings", "set", args.schema, args.key, str(array)])
