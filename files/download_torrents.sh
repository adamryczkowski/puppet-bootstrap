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


pattern='.*/([0-9a-f]+)\.info$'
for file in /home/adam/Downloads/.torrent_queue/*.info; do
	if [[ "$file" =~ $pattern ]]; then
		hash=${BASH_REMATCH[1]}
		remote_path=$(cat $file)
		get_torrent $hash "$remote_path"
	fi
done
