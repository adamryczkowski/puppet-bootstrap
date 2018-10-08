#!/bin/bash
CHANNEL="#ci"
USERNAME="git1.imgw.pl"
EMOJI=":ghost:"
MSG="Próba"

PAYLOAD="payload={\"channel\": \"$CHANNEL\", \"username\": \"$USERNAME\", \"text\": \"$MSG\", \"icon_emoji\": \"$EMOJI\"}"
HOOK=https://hooks.slack.com/services/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

curl -X POST --data-urlencode "$PAYLOAD" "$HOOK"
