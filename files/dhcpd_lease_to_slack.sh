#!/bin/bash

channel=n2n
text="$1 $2 $3 $4"

escapedText=$(echo $text | sed 's/"/\"/g' | sed "s/'/\'/g" )
json="{\"channel\": \"#$channel\", \"text\": \"$escapedText\"}"
curl -s -d "payload=$json" "https://hooks.slack.com/services/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"

echo "${text}">>/root/log.txt
