#!/bin/bash
set -euo pipefail
set +x

log="/dev/stdout"

cd "$(dirname "$0")"
. ./common.sh

logexec bla

#logexec true
#
#echo "Failure test"
#
logexec /bin/false

echo "Failure failure"