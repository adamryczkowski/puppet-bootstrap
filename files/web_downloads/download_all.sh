#!/bin/bash

export basedir=/home/adam/Videos
export sourcedir="${basedir}/to_download"

mkdir -p "${basedir}/to_download"

function download_item() {
	local item="$1"
	local string=$(cat "${item}")
	local pattern='^([^:]+):(.*)$'
	if [[ "$string" =~ $pattern ]]; then
		folder="${BASH_REMATCH[1]}"
		link="${BASH_REMATCH[2]}"
	else
		errcho "Wrong format of .link file ${item}"
		exit 1
	fi
	pushd "${basedir}/${folder}"
	local path="${basedir}/${folder}"

	youtube-dl -c -o '%(upload_date)s %(title)s' -c -f 'bestvideo[ext=mp4&height<=1080]+bestaudio/mp4' --write-thumbnail "$link"

	if [ $? -eq 0 ]; then
		pattern='^([^.]+)\.([^.]+)$'
		if [[ "$item" =~ $pattern ]]; then
			raw_item="${BASH_REMATCH[1]}"
		else
			errcho "Wrong format of .link filename ${item}"
			exit 1
		fi
		mv "$item" "${raw_item}.done"
	fi
	popd
}

export -f download_item

cd $basedir

#set -x
#download_folder "Kurzgesagt"
#exit 0

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

# bash prepare_download_links.sh

while ls ${sourcedir}/*.link >/dev/null; do

	ls ${sourcedir}/*.link | parallel --gnu -j1 -- download_item {}

done
