#!/bin/bash

channel=calendar
user=$1

prefix="/var/lib/radicale/collections"
collection="collection-root"

m_files=$(git ls-files -m)

if [ -n "$m_files" ]; then

	if [ -f "${m_files}" ]; then
		#File was changed
	else
		tmp=$(mktemp)
		git show master:${collection}/${m_files} > $tmp
		m_file=$tmp
		#File was deleted
	fi
else
	m_files=$(git ls-files --others --exclude-standard)
	if [ -n "$m_files" ]; then
		#File was added
	else
		m_file=""
	fi
fi

if [ -n "$m_file" ]; then
	text=$(python3 /etc/radicale/format_ics.py $m_file)
else
	text="Nieznane zdarzenie kalendarza"
fi

#folder=/var/lib/radicale/collections/collection-root/${user}

text="${user} modified calendar:
${text}"

escapedText=$(echo $text | sed 's/"/\"/g' | sed "s/'/\'/g" )
json="{\"channel\": \"#$channel\", \"text\": \"$escapedText\"}"
curl -s -d "payload=$json" "https://hooks.slack.com/services/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"

#echo "${text}">>/root/log.txt
