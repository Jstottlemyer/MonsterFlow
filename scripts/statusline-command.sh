#!/usr/bin/env bash
# Claude Code status line
# ctx bar | 5h bar | 7d bar | git branch+dirty+ahead/behind | model·effort | [perm] | age | cwd

input=$(cat)

# --- Helpers ---
make_bar() {
  local pct=$1 width=${2:-5}
  local filled
  filled=$(awk -v p="$pct" -v w="$width" 'BEGIN{f=int((p/100)*w + 0.5); if(f>w)f=w; if(f<0)f=0; printf "%d", f}')
  local empty=$(( width - filled ))
  local bar="▕"
  local i
  for ((i=0; i<filled; i++)); do bar="${bar}▓"; done
  for ((i=0; i<empty; i++)); do bar="${bar}░"; done
  bar="${bar}▏"
  printf "%s" "$bar"
}

color_for_pct() {
  local pct=$1
  if awk "BEGIN{exit !($pct >= 80)}"; then printf '31'
  elif awk "BEGIN{exit !($pct >= 50)}"; then printf '33'
  else printf '32'
  fi
}

usage_segment() {
  local label=$1 pct=$2
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    printf '\033[32m%s▕░░░░░▏--%%\033[0m' "$label"
    return
  fi
  local bar color
  bar=$(make_bar "$pct" 5)
  color=$(color_for_pct "$pct")
  printf '\033[%sm%s%s%.0f%%\033[0m' "$color" "$label" "$bar" "$pct"
}

# --- Context window ---
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_seg=$(usage_segment "ctx" "$ctx_pct")

# --- Rate limits ---
five_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_seg=""; week_seg=""
[ -n "$five_pct" ] && five_seg=$(usage_segment "5h" "$five_pct")
[ -n "$week_pct" ] && week_seg=$(usage_segment "7d" "$week_pct")

# --- Working directory ---
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
short_cwd="?"
[ -n "$cwd" ] && short_cwd="${cwd/#$HOME/~}"

# --- Git: branch + dirty + ahead/behind ---
git_seg=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=""
    if ! git -C "$cwd" diff --quiet 2>/dev/null || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      dirty=$(printf '\033[33m●\033[0m')
    fi
    if [ -z "$dirty" ]; then
      untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | head -1)
      [ -n "$untracked" ] && dirty=$(printf '\033[33m●\033[0m')
    fi
    ab=""
    counts=$(git -C "$cwd" rev-list --left-right --count @{u}...HEAD 2>/dev/null)
    if [ -n "$counts" ]; then
      behind=$(echo "$counts" | awk '{print $1}')
      ahead=$(echo "$counts" | awk '{print $2}')
      if [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then
        ab=$(printf ' \033[36m↑%s↓%s\033[0m' "$ahead" "$behind")
      fi
    fi
    git_seg=$(printf '\033[32m⎇ %s\033[0m%s%s' "$branch" "$dirty" "$ab")
  fi
fi

# --- Model + effort ---
model_display=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
effort=$(echo "$input" | jq -r '.effort_level // empty')
model_short=""
if [ -n "$model_display" ]; then
  model_short=$(echo "$model_display" | awk '{print tolower($1)}')
fi
model_seg=""
if [ -n "$model_short" ]; then
  if [ -n "$effort" ] && [ "$effort" != "null" ]; then
    model_seg=$(printf '\033[35m%s·%s\033[0m' "$model_short" "$effort")
  else
    model_seg=$(printf '\033[35m%s\033[0m' "$model_short")
  fi
fi

# --- Permission mode ---
perm=$(echo "$input" | jq -r '.permission_mode // .permissions.defaultMode // empty')
perm_seg=""
if [ -n "$perm" ] && [ "$perm" != "null" ]; then
  case "$perm" in
    acceptEdits)       perm_short="edits" ;;
    bypassPermissions) perm_short="bypass" ;;
    plan)              perm_short="plan" ;;
    default)           perm_short="def" ;;
    dontAsk)           perm_short="dontask" ;;
    *)                 perm_short="$perm" ;;
  esac
  perm_seg=$(printf '\033[1m[%s]\033[0m' "$perm_short")
fi

# --- Session age (from transcript mtime) ---
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
age_str=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  created=$(stat -f %B "$transcript" 2>/dev/null)
  if [ -n "$created" ]; then
    now=$(date +%s)
    elapsed=$(( now - created ))
    h=$(( elapsed / 3600 ))
    m=$(( (elapsed % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then age_str=$(printf "%dh%02dm" "$h" "$m")
    else                   age_str=$(printf "%dm" "$m")
    fi
  fi
fi

# --- Assemble ---
sep=$(printf '\033[90m|\033[0m')
result="$ctx_seg"
[ -n "$five_seg" ]  && result="$result $sep $five_seg"
[ -n "$week_seg" ]  && result="$result $sep $week_seg"
[ -n "$git_seg" ]   && result="$result $sep $git_seg"
[ -n "$model_seg" ] && result="$result $sep $model_seg"
[ -n "$perm_seg" ]  && result="$result $sep $perm_seg"
[ -n "$age_str" ]   && result="$result $sep $(printf '\033[36m%s\033[0m' "$age_str")"
result="$result $sep $(printf '\033[94m%s\033[0m' "$short_cwd")"

printf "%b\n" "$result"
