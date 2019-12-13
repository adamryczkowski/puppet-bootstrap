#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares celery server with rabbitmq and redis and optionally flower.


Usage:

$(basename $0)  [--use-flower] [--worker-password <password for worker>] [--worker-username <username for worker>]
                [--help] [--debug] [--log <output file>] 


where
 --use-flower                 - Installs flower monitor
 --worker-username            - Username for celery workers. Defaults to 'worker'
 --worker-password            - Password for celery workers. Defaults to empty. Changes only on new worker name.
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) --debug

"


if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

spack_location="$(get_home_dir ${USER})/tmp/spack"
spack_mirror=""
use_flower="0"
pre_install=()
user="$USER"
worker_username="worker"
worker_password=""

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	--worker-username)
	worker_username="$1"
	shift
	;;
	--worker-password)
	worker_password="$1"
	shift
	;;
	--use-flower)
	use_flower=1
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done


add_apt_source_manual bintray.rabbitmq "deb https://dl.bintray.com/rabbitmq-erlang/debian $(get_ubuntu_codename) erlang
deb https://dl.bintray.com/rabbitmq/debian $(get_ubuntu_codename) main" https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc rabbitmq.key

install_apt_packages rabbitmq-server redis-server

install_file files/redis.conf /etc/redis/redis.conf root

if [[ ${worker_pasword} == "" ]]; then
   password_phrase1=""
   password_phrase2=""
else
   password_phrase1="requirepass ${worker_pasword}"
   password_phrase2=":${worker_pasword}"
fi

textfile /etc/redis/redis_custom.conf "protected-mode no
port 6379
databases 16
${password_phrase1}" root

logexec sudo service redis-server restart

myvhost=myvhost

if ! sudo rabbitmqctl list_vhosts | grep -qE "^${myvhost}$"; then
   sudo rabbitmqctl add_vhost ${myvhost}
fi

if ! sudo rabbitmqctl list_users | grep -qE "^${worker_username}[[:space:]]+\[.*\]$"; then
   logexec sudo rabbitmqctl add_user ${worker_username} "${worker_password}"
   logexec sudo rabbitmqctl set_permissions -p ${myvhost} ${worker_username} ".*" ".*" ".*"
fi

if [[ $use_flower == 1 ]]; then
   install_pip3_packages celery[redis] flower
fi

textfile /tmp/tasks.py "from celery import Celery
app = Celery('tasks', broker='pyamqp://${worker_username}${password_phrase2}@$(hostname)//')
app.conf.update(
   broker_url='redis://${password_phrase2}@$(hostname):6379/1',
   result_backend='redis://${password_phrase2}@$(hostname):6379/1')

@app.task
def add(x, y):
    return x + y"

if !which celery >/dev/null; then
   celery_path="/home/adam/.local/bin/celery"
else
   celery_path=$(which celery)
fi

pushd /tmp
${celery_path} -A tasks worker --loglevel=info
