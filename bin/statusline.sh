#!/bin/bash
# ccstatusline v1.0.0 — https://github.com/nezdemkovski/ccstatusline
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "
tmpdir="/tmp/claude"
mkdir -p "$tmpdir"

# Single timestamp for the entire render
NOW=$(date +%s)

# ── Config ──────────────────────────────────────────────
config_file="$HOME/.claude/ccstatusline.config.json"
if [ -f "$config_file" ]; then
    IFS=$'\t' read -r cfg_context cfg_git cfg_session cfg_thinking cfg_rate cfg_cost cfg_usage_ttl cfg_cost_ttl cfg_token_ttl \
        <<< "$(jq -r '[
            (.sections.context // true | tostring),
            (.sections.git // true | tostring),
            (.sections.session // true | tostring),
            (.sections.thinking // true | tostring),
            (.sections.rate_limits // true | tostring),
            (.sections.cost_tracking // false | tostring),
            (.cache_ttl.usage // 60 | tostring),
            (.cache_ttl.cost // 300 | tostring),
            (.cache_ttl.token // 300 | tostring)
        ] | join("\t")' "$config_file" 2>/dev/null)"
fi
: "${cfg_context:=true}" "${cfg_git:=true}" "${cfg_session:=true}" "${cfg_thinking:=true}"
: "${cfg_rate:=true}" "${cfg_cost:=false}" "${cfg_usage_ttl:=60}"
: "${cfg_cost_ttl:=300}" "${cfg_token_ttl:=300}"

# ── Precomputed bar segments (width=10, only 11 combos) ─
_FILLED=("" "●" "●●" "●●●" "●●●●" "●●●●●" "●●●●●●" "●●●●●●●" "●●●●●●●●" "●●●●●●●●●" "●●●●●●●●●●")
_EMPTY=("○○○○○○○○○○" "○○○○○○○○○" "○○○○○○○○" "○○○○○○○" "○○○○○○" "○○○○○" "○○○○" "○○○" "○○" "○" "")

build_bar() {
    local pct=$1 mode=$2
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    local filled=$(( pct * 10 / 100 ))
    local c
    if [ "$mode" = "remaining" ]; then
        if (( pct <= 10 )); then c="$red"
        elif (( pct <= 30 )); then c="$yellow"
        elif (( pct <= 50 )); then c="$orange"
        else c="$green"; fi
    else
        if (( pct >= 90 )); then c="$red"
        elif (( pct >= 70 )); then c="$yellow"
        elif (( pct >= 50 )); then c="$orange"
        else c="$green"; fi
    fi
    printf '%b' "${c}${_FILLED[$filled]}${dim}${_EMPTY[$filled]}${reset}"
}

color_for_pct() {
    local pct=$1
    if (( pct >= 90 )); then printf '%b' "$red"
    elif (( pct >= 70 )); then printf '%b' "$yellow"
    elif (( pct >= 50 )); then printf '%b' "$orange"
    else printf '%b' "$green"; fi
}

color_for_remaining() {
    local pct=$1
    if (( pct <= 10 )); then printf '%b' "$red"
    elif (( pct <= 30 )); then printf '%b' "$yellow"
    elif (( pct <= 50 )); then printf '%b' "$orange"
    else printf '%b' "$green"; fi
}

format_tokens() {
    local num=$1
    if (( num >= 1000000 )); then
        printf "%d.%dm" $(( num / 1000000 )) $(( (num % 1000000) / 100000 ))
    elif (( num >= 1000 )); then
        printf "%dk" $(( num / 1000 ))
    else
        printf "%d" "$num"
    fi
}

format_reset_secs() {
    local diff=$1
    (( diff < 0 )) && diff=0
    if (( diff >= 86400 )); then
        printf "%dd %dh" $(( diff / 86400 )) $(( (diff % 86400) / 3600 ))
    elif (( diff >= 3600 )); then
        printf "%dh %dm" $(( diff / 3600 )) $(( (diff % 3600) / 60 ))
    elif (( diff >= 60 )); then
        printf "%dm" $(( diff / 60 ))
    else
        printf "%ds" "$diff"
    fi
}

# ── Extract all JSON fields in one jq call ──────────────
read_json=$(jq -r '[
    (.model.display_name // "Claude"),
    (.context_window.context_window_size // 200000 | tostring),
    ((.context_window.current_usage.input_tokens // 0) +
     (.context_window.current_usage.cache_creation_input_tokens // 0) +
     (.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
    (.cwd // ""),
    (.session.start_time // .session.startTime // "")
] | join("\t")' <<< "$input")

IFS=$'\t' read -r model_name size current cwd session_start <<< "$read_json"
(( size == 0 )) && size=200000

if (( size > 0 )); then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

# ── Thinking toggle — grep instead of jq ────────────────
thinking_on=false
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ] && grep -q '"alwaysThinkingEnabled": *true' "$settings_path" 2>/dev/null; then
    thinking_on=true
fi

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session │ Thinking ──
pct_color=$(color_for_pct "$pct_used")
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty=""
if [ "$cfg_git" != "false" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if ! git -C "$cwd" diff-index --quiet HEAD -- 2>/dev/null; then
        git_dirty="*"
    fi
fi

session_duration=""
if [ "$cfg_session" != "false" ]; then
    session_marker="$tmpdir/session-start"
    if [ -z "$session_start" ] || [ "$session_start" = "null" ]; then
        if [ ! -f "$session_marker" ]; then
            echo "$NOW" > "$session_marker"
        fi
        start_epoch=$(<"$session_marker")
    else
        stripped="${session_start%%.*}"
        stripped="${stripped%%Z}"
        stripped="${stripped%%+*}"
        stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"
        if [[ "$session_start" == *"Z"* ]] || [[ "$session_start" == *"+00:00"* ]]; then
            start_epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        else
            start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        fi
        [ -z "$start_epoch" ] && start_epoch=$(date -d "${session_start}" +%s 2>/dev/null)
    fi
    if [ -n "$start_epoch" ]; then
        elapsed=$(( NOW - start_epoch ))
        if (( elapsed >= 3600 )); then
            session_duration="$(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m"
        elif (( elapsed >= 60 )); then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

line1="${blue}${model_name}${reset}"
if [ "$cfg_context" != "false" ]; then
    line1+="${sep}${dim}context${reset} ${pct_color}${pct_used}%${reset}"
fi
line1+="${sep}${cyan}${dirname}${reset}"
[ -n "$git_branch" ] && line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
[ -n "$session_duration" ] && line1+="${sep}${dim}session${reset} ${white}${session_duration}${reset}"
if [ "$cfg_thinking" != "false" ]; then
    line1+="${sep}"
    if $thinking_on; then
        line1+="${magenta}◐ thinking${reset}"
    else
        line1+="${dim}◑ thinking${reset}"
    fi
fi

# ── OAuth token (cached to avoid repeated Keychain hits) ──
token_cache="$tmpdir/statusline-token.cache"
token_max_age=$cfg_token_ttl

get_oauth_token() {
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    if [ -f "$token_cache" ]; then
        local mtime
        mtime=$(stat -f %m "$token_cache" 2>/dev/null || stat -c %Y "$token_cache" 2>/dev/null)
        if (( (NOW - mtime) < token_max_age )); then
            <"$token_cache"
            return 0
        fi
    fi

    local token=""

    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        [ -n "$blob" ] && token=$(jq -r '.claudeAiOauth.accessToken // empty' <<< "$blob" 2>/dev/null)
    fi

    if [ -z "$token" ] || [ "$token" = "null" ]; then
        local creds_file="${HOME}/.claude/.credentials.json"
        [ -f "$creds_file" ] && token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
    fi

    if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "$token" > "$token_cache"
        echo "$token"
        return 0
    fi

    echo ""
}

# ── Lock helper (prevents duplicate background refreshes) ──
acquire_lock() {
    local lockfile="$1" max_age="${2:-30}"
    if mkdir "$lockfile" 2>/dev/null; then
        echo $$ > "$lockfile/pid"
        return 0
    fi
    local lock_mtime
    lock_mtime=$(stat -f %m "$lockfile/pid" 2>/dev/null || stat -c %Y "$lockfile/pid" 2>/dev/null || echo 0)
    if (( (NOW - lock_mtime) > max_age )); then
        rm -rf "$lockfile"
        if mkdir "$lockfile" 2>/dev/null; then
            echo $$ > "$lockfile/pid"
            return 0
        fi
    fi
    return 1
}

release_lock() {
    rm -rf "$1"
}

# ── Fetch usage data (cached, background refresh) ───────
rate_lines=""
if [ "$cfg_rate" != "false" ]; then
    cache_file="$tmpdir/statusline-usage-cache.json"
    cache_max_age=$cfg_usage_ttl

    needs_refresh=true
    usage_data=""

    if [ -f "$cache_file" ]; then
        usage_data=$(<"$cache_file")
        cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
        (( (NOW - cache_mtime) < cache_max_age )) && needs_refresh=false
    fi

    if $needs_refresh && acquire_lock "$tmpdir/usage-refresh.lock" 30; then
        (
            trap 'release_lock "'"$tmpdir"'/usage-refresh.lock"' EXIT
            token=$(get_oauth_token)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                response=$(curl -s --max-time 10 \
                    -H "Accept: application/json" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $token" \
                    -H "anthropic-beta: oauth-2025-04-20" \
                    -H "User-Agent: claude-code/2.1.34" \
                    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
                if [ -n "$response" ] && jq -e '.five_hour' <<< "$response" >/dev/null 2>&1; then
                    echo "$response" > "$cache_file"
                fi
            fi
        ) &>/dev/null &
        disown 2>/dev/null || true
    fi

    # ── Rate limit lines (single jq call) ──────────────────
    if [ -n "$usage_data" ]; then
        usage_parsed=$(jq -r --argjson now "$NOW" '
            def to_epoch: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | sub("\\+[0-9]{2}:[0-9]{2}$"; "Z") | if endswith("Z") then . else . + "Z" end | fromdateiso8601;
            [
            (.five_hour.utilization // 0 | round | tostring),
            (.five_hour.resets_at // "" | if . != "" then (to_epoch - $now | tostring) else "" end),
            (.seven_day.utilization // 0 | round | tostring),
            (.seven_day.resets_at // "" | if . != "" then (to_epoch - $now | tostring) else "" end),
            (.extra_usage.is_enabled // false | tostring),
            (.extra_usage.utilization // 0 | round | tostring),
            (.extra_usage.used_credits // 0 | . / 100 | tostring),
            (.extra_usage.monthly_limit // 0 | . / 100 | tostring)
        ] | join("\t")' <<< "$usage_data" 2>/dev/null) || usage_parsed=""

        if [ -n "$usage_parsed" ]; then
            IFS=$'\t' read -r fh_used fh_reset_secs sd_used sd_reset_secs extra_enabled extra_pct extra_used extra_limit <<< "$usage_parsed"

            five_hour_pct=$(( 100 - fh_used ))
            (( five_hour_pct < 0 )) && five_hour_pct=0
            five_hour_bar=$(build_bar "$five_hour_pct" "remaining")
            five_hour_pct_color=$(color_for_remaining "$five_hour_pct")
            five_hour_reset=""
            [ -n "$fh_reset_secs" ] && five_hour_reset=$(format_reset_secs "$fh_reset_secs")

            rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}$(printf "%3d" "$five_hour_pct")% left${reset} ${dim}resets in${reset} ${white}${five_hour_reset}${reset}"

            seven_day_pct=$(( 100 - sd_used ))
            (( seven_day_pct < 0 )) && seven_day_pct=0
            seven_day_bar=$(build_bar "$seven_day_pct" "remaining")
            seven_day_pct_color=$(color_for_remaining "$seven_day_pct")
            seven_day_reset=""
            [ -n "$sd_reset_secs" ] && seven_day_reset=$(format_reset_secs "$sd_reset_secs")

            rate_lines+="\n${white}weekly${reset}  ${seven_day_bar} ${seven_day_pct_color}$(printf "%3d" "$seven_day_pct")% left${reset} ${dim}resets in${reset} ${white}${seven_day_reset}${reset}"

            if [ "$extra_enabled" = "true" ]; then
                extra_pct_int=${extra_pct%%.*}
                extra_bar=$(build_bar "$extra_pct_int")
                extra_pct_color=$(color_for_pct "$extra_pct_int")

                extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                [ -z "$extra_reset" ] && extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')

                rate_lines+="\n${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset}"
                rate_lines+="\n${dim}resets ${reset}${white}${extra_reset}${reset}"
            fi
        fi
    fi
fi

# ── Cost data (ccusage, cached, background refresh) ─────
cost_lines=""
if [ "$cfg_cost" != "false" ]; then
    cost_cache="$tmpdir/statusline-cost-cache.json"
    cost_max_age=$cfg_cost_ttl

    cost_needs_refresh=true
    cost_data=""

    if [ -f "$cost_cache" ]; then
        cost_data=$(<"$cost_cache")
        cost_mtime=$(stat -f %m "$cost_cache" 2>/dev/null || stat -c %Y "$cost_cache" 2>/dev/null)
        (( (NOW - cost_mtime) < cost_max_age )) && cost_needs_refresh=false
    fi

    if $cost_needs_refresh && command -v ccusage >/dev/null 2>&1 && acquire_lock "$tmpdir/cost-refresh.lock" 60; then
        _captured_session_id="$CLAUDE_SESSION_ID"
        (
            trap 'release_lock "'"$tmpdir"'/cost-refresh.lock"' EXIT
            today=$(date +%Y%m%d)
            yesterday=$(date -v-1d +%Y%m%d 2>/dev/null || date -d "yesterday" +%Y%m%d 2>/dev/null)
            thirty_days_ago=$(date -v-30d +%Y%m%d 2>/dev/null || date -d "30 days ago" +%Y%m%d 2>/dev/null)

            today_json=$(ccusage daily --json --since "$today" 2>/dev/null)
            yesterday_json=$(ccusage daily --json --since "$yesterday" --until "$yesterday" 2>/dev/null)
            month_json=$(ccusage daily --json --since "$thirty_days_ago" 2>/dev/null)

            session_cost=0 session_tokens=0
            if [ -n "$_captured_session_id" ]; then
                session_json=$(ccusage session --json --id "$_captured_session_id" 2>/dev/null)
                session_cost=$(jq -r '.sessions[0].totalCost // 0' <<< "$session_json" 2>/dev/null)
                session_tokens=$(jq -r '.sessions[0].totalTokens // 0' <<< "$session_json" 2>/dev/null)
            fi

            read -r today_cost today_tokens <<< "$(jq -r '([.daily[].totalCost] | add // 0 | tostring) + " " + ([.daily[].totalTokens] | add // 0 | tostring)' <<< "$today_json" 2>/dev/null)"
            read -r yesterday_cost yesterday_tokens <<< "$(jq -r '([.daily[].totalCost] | add // 0 | tostring) + " " + ([.daily[].totalTokens] | add // 0 | tostring)' <<< "$yesterday_json" 2>/dev/null)"
            read -r month_cost month_tokens <<< "$(jq -r '([.daily[].totalCost] | add // 0 | tostring) + " " + ([.daily[].totalTokens] | add // 0 | tostring)' <<< "$month_json" 2>/dev/null)"

            jq -n \
                --argjson sc "${session_cost:-0}" \
                --argjson st "${session_tokens:-0}" \
                --argjson tc "${today_cost:-0}" \
                --argjson tt "${today_tokens:-0}" \
                --argjson yc "${yesterday_cost:-0}" \
                --argjson yt "${yesterday_tokens:-0}" \
                --argjson mc "${month_cost:-0}" \
                --argjson mt "${month_tokens:-0}" \
                '{session_cost:$sc, session_tokens:$st, today_cost:$tc, today_tokens:$tt, yesterday_cost:$yc, yesterday_tokens:$yt, month_cost:$mc, month_tokens:$mt}' \
                > "$cost_cache"
        ) &>/dev/null &
        disown 2>/dev/null || true
    fi

    if [ -n "$cost_data" ]; then
        cost_parsed=$(jq -r '
            def fmt_cost: "\(. | tostring | split(".") | if length > 1 then .[0] + "." + (.[1] + "00")[0:2] else .[0] + ".00" end)";
            def fmt_tok: if . >= 1000000000 then "\(. / 1000000000 * 10 | round / 10)B"
                elif . >= 1000000 then "\(. / 1000000 * 10 | round / 10)M"
                elif . >= 1000 then "\(. / 1000 | round)K"
                else "\(. | round)" end;
            "$\(.session_cost | fmt_cost)\t\(.session_tokens | fmt_tok)\t$\(.today_cost | fmt_cost)\t\(.today_tokens | fmt_tok)\t$\(.yesterday_cost | fmt_cost)\t\(.yesterday_tokens | fmt_tok)\t$\(.month_cost | fmt_cost)\t\(.month_tokens | fmt_tok)"
        ' <<< "$cost_data" 2>/dev/null) || cost_parsed=""

        if [ -n "$cost_parsed" ]; then
            IFS=$'\t' read -r sc st tc tt yc yt mc mt <<< "$cost_parsed"
            cost_lines="${dim}session${reset} ${white}${sc}${reset} ${dim}·${reset} ${white}${st}${reset}${sep}${dim}today${reset} ${white}${tc}${reset} ${dim}·${reset} ${white}${tt}${reset}${sep}${dim}yesterday${reset} ${white}${yc}${reset} ${dim}·${reset} ${white}${yt}${reset}${sep}${dim}30d${reset} ${white}${mc}${reset} ${dim}·${reset} ${white}${mt}${reset}"
        fi
    fi
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"
[ -n "$cost_lines" ] && printf "\n\n%b" "$cost_lines"

exit 0
