#!/bin/bash

basedir=/home/adam/Videos

folders=(Computerphile PBS_Eons OddlySatisfying
	3b1b "Think Twice" LeiosOS Numberphile GlebAlexandrov Kurzgesagt MarkRober
	MinuteEarth MinutePhysics Sexplanations SixtySymbols Stats Wendover
)

mkdir -p "${basedir}/to_download"

function regexp_quote() {
	sed 's/[]\.|$(){}?+*^]/\\&/g' <<< "$*"
}

function download_folder() {
	local folder="$1"
	local path="${basedir}/${folder}"
	if [ ! -f "${path}/download.link" ]; then
		echo "Missing download.link in ${path}" >/dev/stderr
		exit 1
	fi
	local link=$(cat "${path}/download.link")
	youtube-dl --flat-playlist --dump-single-json "$link" > "${path}"/download.json
	local count=$(jq '.entries | length' "${path}/download.json")
	local channel=$(jq --raw-output '.title' "${path}/download.json")
	declare -a titles
	readarray -t titles < <(jq --raw-output '.entries[].title' "${path}/download.json")
	readarray -t urls < <(jq --raw-output '.entries[].url' "${path}/download.json")
	local last_item=${titles[0]}
	local first_missing_index=-1
	rm -f "${path}/to_download.list"
	#	touch "${path}/to_download.list"
	for ((i=0; i < ${#titles[@]}; i++)); do
		local title="${titles[$i]}"
		local escaped_title=$(regexp_quote $title)
		local escaped_path=$(regexp_quote $path)
		local existing_files=$(find "$path" -regex "^${escaped_path}/[0-9 ]*${escaped_title}\..*")
		if [ -n "$existing_files" ]; then
			break
		fi
		first_missing_index=$i
		local hash=$(echo -n "${urls[$i]}" | md5sum | awk '{print $1}')
		echo "${folder}:${urls[$i]}" >> "${basedir}/to_download/${hash}.link"
	done
	if [ "$first_missing_index" == "-1" ]; then
		echo "No new videos from ${channel} since your last visit"
		return 0
	fi
	echo "There are $((first_missing_index+1)) new videos from ${channel} since your last visit:"
	for ((i=0; i<=first_missing_index; i++)); do
		local title="${titles[$i]}"
		echo "   $((i+1)). $title"
	done
}

cd $basedir

#set -x
#download_folder "Kurzgesagt"
#exit 0

for folder in "${folders[@]}"; do
	download_folder "$folder"
done
