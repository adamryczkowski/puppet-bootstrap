#!/usr/bin/env bash
# ----------------------------------------------------------------------
#  copilot-premium-percent.sh
#
#  Prints the remaining Premium Copilot request quota as an integer
#  (0‑100) or the em‑dash (—) on any error.
#
#  * Works for Copilot for Business (organisation) accounts.
#  * Falls back to user‑level queries (which will always return the em‑dash
#    for personal Copilot licences).
#
#  Requirements:
#    • GitHub CLI (gh) installed
#    • Authenticated token with the `copilot` scope
#    • If you want organisation data, set ORG="<org‑login>"
#
#  DEBUG=1 prints all request/response information on stderr.
# ----------------------------------------------------------------------

set -euo pipefail

EM_DASH="—"
DEBUG="${DEBUG:-0}"
COPILOT_ACCEPT="application/vnd.github.copilot+json"
API_VERSION="2022-11-28"

log() { [[ "$DEBUG" -eq 1 ]] && printf '%s\n' "$*" >&2; }
die() { printf "%s\n" "$EM_DASH"; exit 0; }

# ----------------------------------------------------------------------
#  1️⃣  Basic checks
# ----------------------------------------------------------------------
log "Checking that 'gh' is installed …"
command -v gh >/dev/null 2>&1 || die

log "Checking that we are authenticated …"
gh auth status -t >/dev/null 2>&1 || die

# ----------------------------------------------------------------------
#  2️⃣  Verify token has the `copilot` scope
# ----------------------------------------------------------------------
log "Fetching token scopes …"
TOKEN_SCOPES=$(gh api -i /user 2>/dev/null | grep -i '^X-Oauth-Scopes:' || true)
log "Scopes header: $TOKEN_SCOPES"

if [[ "$TOKEN_SCOPES" != *"copilot"* ]]; then
    log "⚠️  Token is missing the required 'copilot' scope."
    log "Create a PAT (or fine‑grained token) that includes the Copilot permission."
    die
fi

# ----------------------------------------------------------------------
#  3️⃣  Organisation mode?
# ----------------------------------------------------------------------
ORG="${ORG:-}"                     # e.g. export ORG=my-company
if [[ -n "$ORG" ]]; then
    log "Organisation mode – will query org '$ORG'"
fi

# ----------------------------------------------------------------------
#  4️⃣  GraphQL query variants (place‑holder %ROOT% is replaced later)
# ----------------------------------------------------------------------
declare -a GRAPHQL_VARIANTS=(
# 1 – Copilot usage → premium (newest docs)
'query { %ROOT% { copilot { usage { premium { limit remaining } } } } }' \
'.data.%ROOT_KEY%.copilot.usage.premium | select(.!=null) | [.limit, .remaining] | @tsv'

# 2 – Copilot usage → premiumRequests (older wording)
'query { %ROOT% { copilot { usage { premiumRequests { limit remaining } } } } }' \
'.data.%ROOT_KEY%.copilot.usage.premiumRequests | select(.!=null) | [.limit, .remaining] | @tsv'

# 3 – aiUserRateLimit with category list
'query { %ROOT% { aiUserRateLimit { categoryLimits { category limit remaining } } } }' \
'.data.%ROOT_KEY%.aiUserRateLimit.categoryLimits[]
   | select(.category=="PREMIUM")
   | [.limit, .remaining] | @tsv'

# 4 – aiUserRateLimit without categories
'query { %ROOT% { aiUserRateLimit { limit remaining } } }' \
'.data.%ROOT_KEY%.aiUserRateLimit | select(.!=null) | [.limit, .remaining] | @tsv'
)

# ----------------------------------------------------------------------
#  5️⃣  Helper: run a single GraphQL variant
# ----------------------------------------------------------------------
run_graphql_variant() {
    local tmpl jq tmpl_root root_key resp
    tmpl="$1"
    jq="$2"

    if [[ -n "$ORG" ]]; then
        root='organization(login:"'"$ORG"'")'
        root_key='organization'
    else
        root='viewer'
        root_key='viewer'
    fi

    # Replace placeholders
    local query="${tmpl//%ROOT%/$root}"
    jq="${jq//%ROOT_KEY%/$root_key}"

    log "Running GraphQL (root=$root_key): $query"
    if resp=$(gh api graphql \
                -f query="$query" \
                --jq "$jq" \
                -H "Accept: $COPILOT_ACCEPT" \
                -H "X-GitHub-Api-Version: $API_VERSION" \
                2>/dev/null); then

        # Even on exit‑0 the payload may contain an "errors" array.
        if [[ "$resp" == *'"errors":'* ]]; then
            log "GraphQL payload contains errors – skipping."
            return 1
        fi

        # Expect two tab‑separated numbers.
        if [[ -n "$resp" && "$resp" == *$'\t'* ]]; then
            log "GraphQL succeeded – raw output: $resp"
            printf '%s\n' "$resp"
            return 0
        else
            log "GraphQL succeeded but did not return <limit><TAB><remaining>."
            return 1
        fi
    else
        log "GraphQL request failed (non‑zero exit status)."
        return 1
    fi
}

# ----------------------------------------------------------------------
#  6️⃣  Try all GraphQL variants
# ----------------------------------------------------------------------
log "Attempting GraphQL queries …"
for ((i=0; i<${#GRAPHQL_VARIANTS[@]}; i+=2)); do
    if pair=$(run_graphql_variant "${GRAPHQL_VARIANTS[i]}" "${GRAPHQL_VARIANTS[i+1]}"); then
        # -------------------------------------------------------------
        # 6a – we have a good pair → compute percentage and exit
        # -------------------------------------------------------------
        IFS=$'\t' read -r LIMIT REMAINING <<<"$pair"

        [[ "$LIMIT" =~ ^[0-9]+$ ]]   || { log "LIMIT not numeric"; die; }
        [[ "$REMAINING" =~ ^-?[0-9]+$ ]] || { log "REMAINING not numeric"; die; }
        (( LIMIT > 0 )) || { log "LIMIT <= 0"; die; }

        (( REMAINING < 0 )) && REMAINING=0
        (( REMAINING > LIMIT )) && REMAINING=$LIMIT

        PERCENT=$(( REMAINING * 100 / LIMIT ))
        (( PERCENT < 0 )) && PERCENT=0
        (( PERCENT > 100 )) && PERCENT=100

        printf "%d\n" "$PERCENT"
        exit 0
    fi
done

# ----------------------------------------------------------------------
#  7️⃣  REST fallback
# ----------------------------------------------------------------------
log "All GraphQL attempts failed – trying REST endpoint …"

if [[ -n "$ORG" ]]; then
    REST_PATH="/orgs/$ORG/copilot/usage"
else
    REST_PATH="/copilot/premium/usage"
fi

# Grab headers + body so we can inspect the HTTP status.
if full_resp=$(gh api -i "$REST_PATH" \
                -H "Accept: $COPILOT_ACCEPT" \
                -H "X-GitHub-Api-Version: $API_VERSION" \
                2>/dev/null); then

    status_line=$(printf '%s\n' "$full_resp" | head -n1)
    log "REST status line: $status_line"

    if ! printf '%s' "$status_line" | grep -q '^HTTP/[0-9.]\+ 200 '; then
        log "REST endpoint returned non‑200 – likely the org does not have Copilot for Business."
        die
    fi

    # Strip headers – everything after the first blank line is the JSON body.
    body=$(printf '%s\n' "$full_resp" | sed -n '/^\r*$/,$p' | sed '1d')
    log "REST body: $body"

    # The org‑level response shape is:
    #   { "copilot": { "usage": { "premium": { "limit": N, "remaining": M } } } }
    if [[ "$ORG" != "" ]]; then
        LIMIT=$(jq -r '.copilot.usage.premium.limit // empty' <<<"$body")
        REMAINING=$(jq -r '.copilot.usage.premium.remaining // empty' <<<"$body")
    else
        # user‑level (still kept for completeness)
        LIMIT=$(jq -r '.limit // empty' <<<"$body")
        REMAINING=$(jq -r '.remaining // empty' <<<"$body")
    fi

    if [[ -n "$LIMIT" && -n "$REMAINING" ]]; then
        [[ "$LIMIT" =~ ^[0-9]+$ ]]   || { log "REST LIMIT not numeric"; die; }
        [[ "$REMAINING" =~ ^-?[0-9]+$ ]] || { log "REST REMAINING not numeric"; die; }
        (( LIMIT > 0 )) || { log "REST LIMIT <= 0"; die; }

        (( REMAINING < 0 )) && REMAINING=0
        (( REMAINING > LIMIT )) && REMAINING=$LIMIT

        PERCENT=$(( REMAINING * 100 / LIMIT ))
        (( PERCENT < 0 )) && PERCENT=0
        (( PERCENT > 100 )) && PERCENT=100

        printf "%d\n" "$PERCENT"
        exit 0
    else
        log "REST payload missing limit/remaining fields."
    fi
else
    log "REST request failed (non‑zero exit status)."
fi

# ----------------------------------------------------------------------
#  8️⃣  Nothing succeeded – final fallback
# ----------------------------------------------------------------------
die
