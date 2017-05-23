#!/usr/bin/env python
import argparse
import os.path
parser = argparse.ArgumentParser()
parser.add_argument('-d', dest='dir')
parser.add_argument('input')
args = parser.parse_args()

out = os.path.join(args.dir, args.input)

f = open(out, 'w')
f.write('!Generated Fortran file')  # python will convert \n to os.linesep
f.close()