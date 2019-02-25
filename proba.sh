#!/bin/bash

## dependency: prepare_ubuntu.sh
## dependency: prepare_ubuntu_user.sh
## dependency: prepare_update-all.sh

cd `dirname $0`
. ./common.sh

logexec echo '\n' | lxc exec --force-local $name -- pwd 2>/dev/null

logexec pwd
