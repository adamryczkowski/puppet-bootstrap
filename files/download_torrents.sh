#!/bin/bash

function get_torrent {
	local hash="$1"
	local remote_path="$2"
	rsync -avPs  "kievbox:${remote_path}" /mnt/ext4/Downloads/
	if [ $? -eq 0 ]; then
		#tag torrent as downloaded
		qbt torrent category $hash --set done --url http://10.55.181.104:8080 --password "Zero tolerancji" --username adam
		mv /home/adam/Downloads/.torrent_queue/${hash}.info /home/adam/Downloads/.torrent_queue/${hash}.done
	fi
}

cd /mnt/ext4/Downloads

seconds_today=$(( $(date -d $(date "+%H:%M:%S") '+%s') - $(date -d $(date '+%Y-%m-%d') +%s) ))

if (( $seconds_today > 28800 )); then
	#It is after 8:00 AM. Schedule run for tomorrow
	current_epoch=$(date +%s)
	target_epoch=$(date -d "$(date -d "$(date '+%Y-%m-%d') + 1 day" '+%Y-%m-%d') 00:02" '+%s')
	sleep_seconds=$(( $target_epoch - $current_epoch ))
	echo "Waiting ${sleep_seconds} for the midnight..."
	sleep ${sleep_seconds} 
fi

current_epoch=$(date +%s)
target_epoch=$(date -d "$(date '+%Y-%m-%d') 07:55" +%s)
sleep_seconds=$(( $target_epoch - $current_epoch ))
sleep ${sleep_seconds} && kill -9 -$(ps -o pgid= $$ | grep -o '[0-9]*') &

while ls /home/adam/Downloads/.torrent_queue/*.info >/dev/null; do

pattern='.*/([0-9a-f]+)\.info$'
for file in /home/adam/Downloads/.torrent_queue/*.info; do
	if [[ "$file" =~ $pattern ]]; then
		hash=${BASH_REMATCH[1]}
		remote_path=$(cat $file)
		get_torrent $hash "$remote_path"
	fi
done


done
