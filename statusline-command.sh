#!/usr/bin/env bash

input=$(cat)

# --- Color palette ---
C_MODEL="\033[35m"   # magenta (strong violet)
C_COST="\033[32m"    # green
C_DUR="\033[37m"     # light gray
C_SEP="\033[90m"     # dark gray (separators only)
C_RESET="\033[0m"

# Dynamic color based on usage percentage (shared by ctx/5h/7d).
usage_color() {
  local p=$1
  if [ "$p" -lt 50 ]; then printf "\033[94m"       # blue bright
  elif [ "$p" -lt 80 ]; then printf "\033[33m"     # yellow
  else printf "\033[31m"                           # red
  fi
}

# --- Model ---
# Mostrar sólo el nombre del modelo (ej "Opus 4.8"); quitar cualquier paréntesis
# de contexto (ej " (1M context)") que es redundante con el medidor ctx de abajo
# y no se actualiza al cambiar de modelo.
model=$(echo "$input" | jq -r '.model.display_name // "unknown"' | sed -E 's/ *\([^)]*(context|ctx)[^)]*\)//I')

# --- Context window ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // 0')

if [ -n "$used_pct" ]; then
  bar_total=10
  filled=$(LC_ALL=C awk "BEGIN {printf \"%.0f\", $used_pct * $bar_total / 100}")
  empty=$((bar_total - filled))
  bar_filled=$(printf "%${filled}s" | tr ' ' '#')
  bar_empty=$(printf "%${empty}s" | tr ' ' '-')
  pct_int=$(LC_ALL=C awk "BEGIN {printf \"%.0f\", $used_pct}")
  bcolor=$(usage_color "$pct_int")

  used_k=$(LC_ALL=C awk "BEGIN {printf \"%.0fk\", $ctx_total * $used_pct / 100 / 1000}")
  total_k=$(LC_ALL=C awk "BEGIN {printf \"%.0fk\", $ctx_total/1000}")

  ctx_line=$(printf "%bctx: [%s%s] %s/%s (%s%%)%b" \
    "$bcolor" "$bar_filled" "$bar_empty" "$used_k" "$total_k" "$pct_int" "$C_RESET")
else
  ctx_line=$(printf "%bctx: --%b" "\033[94m" "$C_RESET")
fi

# --- Rate limits (Pro/Max) ---
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

five_line=""
seven_line=""
if [ -n "$five_pct" ]; then
  five_int=$(LC_ALL=C awk "BEGIN {printf \"%.0f\", $five_pct}")
  fcolor=$(usage_color "$five_int")
  five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  five_remaining=""
  if [ -n "$five_reset" ]; then
    now=$(date +%s)
    delta=$((five_reset - now))
    if [ "$delta" -gt 0 ]; then
      h=$((delta / 3600))
      m=$(((delta % 3600) / 60))
      if [ "$h" -gt 0 ]; then
        five_remaining=$(printf " (reset %dh%dm)" "$h" "$m")
      else
        five_remaining=$(printf " (reset %dm)" "$m")
      fi
    fi
  fi
  five_line=$(printf "%bday (5h): %s%%%s%b" "$fcolor" "$five_int" "$five_remaining" "$C_RESET")
fi
if [ -n "$seven_pct" ]; then
  seven_int=$(LC_ALL=C awk "BEGIN {printf \"%.0f\", $seven_pct}")
  scolor=$(usage_color "$seven_int")
  seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  seven_remaining=""
  if [ -n "$seven_reset" ]; then
    now=$(date +%s)
    delta=$((seven_reset - now))
    if [ "$delta" -gt 0 ]; then
      d=$((delta / 86400))
      h=$(((delta % 86400) / 3600))
      m=$(((delta % 3600) / 60))
      if [ "$d" -gt 0 ]; then
        seven_remaining=$(printf " (reset %dd%dh)" "$d" "$h")
      elif [ "$h" -gt 0 ]; then
        seven_remaining=$(printf " (reset %dh%dm)" "$h" "$m")
      else
        seven_remaining=$(printf " (reset %dm)" "$m")
      fi
    fi
  fi
  seven_line=$(printf "%bweek (7d): %s%%%s%b" "$scolor" "$seven_int" "$seven_remaining" "$C_RESET")
fi

# --- Cost ---
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
cost=$(LC_ALL=C awk "BEGIN {printf \"%.2f\", $cost_usd}")
cost_line=$(printf "%b\$%s%b" "$C_COST" "$cost" "$C_RESET")

# --- Duration ---
dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
dur_s=$((dur_ms / 1000))
if [ "$dur_s" -lt 60 ]; then
  dur_str="${dur_s}s"
elif [ "$dur_s" -lt 3600 ]; then
  dur_str="$((dur_s / 60))m$((dur_s % 60))s"
else
  dur_str="$((dur_s / 3600))h$(((dur_s % 3600) / 60))m"
fi
dur_line=$(printf "%b%s%b" "$C_DUR" "$dur_str" "$C_RESET")

# --- Compose ---
sep=$(printf "%b|%b" "$C_SEP" "$C_RESET")

parts=()
parts+=("$(printf "%b%s%b" "$C_MODEL" "$model" "$C_RESET")")
parts+=("$ctx_line")
[ -n "$five_line" ] && parts+=("$five_line")
[ -n "$seven_line" ] && parts+=("$seven_line")
parts+=("$cost_line")
parts+=("$dur_line")

content=""
for i in "${!parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    content="${parts[$i]}"
  else
    content="$content $sep ${parts[$i]}"
  fi
done

# --- Right-align ---
cols=$(tput cols 2>/dev/null </dev/tty || echo 120)
visible=$(printf '%b' "$content" | sed -E 's/\x1b\[[0-9;]*m//g')
visible_len=${#visible}
col=$(( cols - visible_len + 1 ))
[ "$col" -lt 1 ] && col=1

printf "\033[${col}G%b\n" "$content"

# Bottom border
border=$(printf '─%.0s' $(seq 1 "$visible_len"))
printf "\033[${col}G%b%s%b" "$C_SEP" "$border" "$C_RESET"
