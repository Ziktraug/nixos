#!/run/current-system/sw/bin/bash

set -euo pipefail

export PATH="${PATH:-}:/run/current-system/sw/bin:/run/opengl-driver/bin"

# Claude's CLI data is treated as usedPercent and converted to remaining.
CLAUDE_VALUES_ARE_REMAINING=0
ANTHROPIC_GLYPH="⟠"
OPENAI_GLYPH="◎"

codexbar_bin=""
for candidate in "$(command -v codexbar 2>/dev/null)" "/run/current-system/sw/bin/codexbar"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    codexbar_bin="$candidate"
    break
  fi
done

normalize_percent() {
  value="$1"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    return 1
  fi
  printf '%s' "$value" | awk '{printf "%d", ($1 + 0)}'
}

remaining_percent() {
  used="$1"
  left=$((100 - used))
  if [ "$left" -lt 0 ]; then
    left=0
  elif [ "$left" -gt 100 ]; then
    left=100
  fi
  printf '%s' "$left"
}

color_for_remaining() {
  value="$1"
  red=$((255 - (value * 255 / 100)))
  green=$((value * 255 / 100))
  blue=120
  printf '#%02x%02x%02x' "$red" "$green" "$blue"
}

render_value() {
  value="$1"
  suffix="$2"

  if [ "$value" = "--" ]; then
    printf -- '--%s' "$suffix"
    return
  fi

  color=$(color_for_remaining "$value")
  printf '<span foreground="%s">%s%%%s</span>' "$color" "$value" "$suffix"
}

provider_remaining_percent() {
  provider="$1"
  value="$2"

  if [ "$provider" = "claude" ] && [ "$CLAUDE_VALUES_ARE_REMAINING" = "1" ]; then
    printf '%s' "$value"
  else
    remaining_percent "$value"
  fi
}

format_duration() {
  local seconds="$1"
  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  local mins=$(((seconds % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf '%dd %dh %dm' "$days" "$hours" "$mins"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh %dm' "$hours" "$mins"
  else
    printf '%dm' "$mins"
  fi
}

calculate_reset_info() {
  local provider="$1"
  local window_type="$2"
  local resets_at_var="$3"
  local remaining_sec_var="$4"

  printf -v "$resets_at_var" ''
  printf -v "$remaining_sec_var" ''

  if [ -z "$codexbar_bin" ]; then
    return 1
  fi

  local output
  output=$("$codexbar_bin" usage --provider "$provider" --source cli --format json --json-only 2>/dev/null || true)
  if [ -z "$output" ]; then
    return 1
  fi

  local line
  line=$(printf '%s\n' "$output" | grep "\"provider\":\"${provider}\"" | head -1 || true)
  if [ -z "$line" ]; then
    line=$(printf '%s\n' "$output" | head -1 || true)
  fi

  local reset_timestamp
  if [ "$window_type" = "primary" ]; then
    reset_timestamp=$(printf '%s' "$line" | jq -r 'if type == "array" then .[0].usage.primary.resetsAt // .[0].usage.primary.resetTime // empty else .usage.primary.resetsAt // .usage.primary.resetTime // empty end' 2>/dev/null || true)
  else
    reset_timestamp=$(printf '%s' "$line" | jq -r 'if type == "array" then .[0].usage.secondary.resetsAt // .[0].usage.secondary.resetTime // empty else .usage.secondary.resetsAt // .usage.secondary.resetTime // empty end' 2>/dev/null || true)
  fi

  if [ -n "$reset_timestamp" ] && [ "$reset_timestamp" != "null" ]; then
    local reset_epoch now_epoch remaining_sec
    reset_epoch=$(date -d "$reset_timestamp" +%s 2>/dev/null || echo "")
    if [ -n "$reset_epoch" ]; then
      now_epoch=$(date +%s)
      remaining_sec=$((reset_epoch - now_epoch))
      if [ "$remaining_sec" -lt 0 ]; then
        remaining_sec=0
      fi
      printf -v "$resets_at_var" '%s' "$reset_timestamp"
      printf -v "$remaining_sec_var" '%s' "$remaining_sec"
      return 0
    fi
  fi

  return 1
}

read_usage_used() {
  provider="$1"
  primary_var="$2"
  secondary_var="$3"
  error_var="$4"

  printf -v "$primary_var" ''
  printf -v "$secondary_var" ''
  printf -v "$error_var" ''

  if [ -z "$codexbar_bin" ]; then
    printf -v "$error_var" '%s' 'codexbar missing'
    return 1
  fi

  output=$("$codexbar_bin" usage --provider "$provider" --source cli --format json --json-only 2>/dev/null || true)
  if [ -z "$output" ]; then
    printf -v "$error_var" '%s' "$provider unavailable"
    return 1
  fi

  line=$(printf '%s\n' "$output" | grep "\"provider\":\"${provider}\"" | head -1 || true)
  if [ -z "$line" ]; then
    line=$(printf '%s\n' "$output" | head -1 || true)
  fi

  primary_raw=$(printf '%s' "$line" | jq -r 'if type == "array" then .[0].usage.primary.usedPercent // empty else .usage.primary.usedPercent // empty end' 2>/dev/null || true)
  secondary_raw=$(printf '%s' "$line" | jq -r 'if type == "array" then .[0].usage.secondary.usedPercent // empty else .usage.secondary.usedPercent // empty end' 2>/dev/null || true)

  primary=$(normalize_percent "$primary_raw" || true)
  secondary=$(normalize_percent "$secondary_raw" || true)

  if [ -n "$primary" ] || [ -n "$secondary" ]; then
    printf -v "$primary_var" '%s' "$primary"
    printf -v "$secondary_var" '%s' "$secondary"
    return 0
  fi

  err=$(printf '%s' "$line" | jq -r 'if type == "array" then .[0].error.message // empty else .error.message // empty end' 2>/dev/null || true)
  if [ -n "$err" ]; then
    printf -v "$error_var" '%s' "$err"
  else
    printf -v "$error_var" '%s' "$provider unavailable"
  fi
  return 1
}

claude_primary_used=""
claude_secondary_used=""
claude_error=""
codex_primary_used=""
codex_secondary_used=""
codex_error=""

claude_5h_reset_at=""
claude_5h_remaining_sec=""
claude_week_reset_at=""
claude_week_remaining_sec=""
codex_5h_reset_at=""
codex_5h_remaining_sec=""
codex_week_reset_at=""
codex_week_remaining_sec=""

read_usage_used claude claude_primary_used claude_secondary_used claude_error || true
read_usage_used codex codex_primary_used codex_secondary_used codex_error || true

calculate_reset_info claude primary claude_5h_reset_at claude_5h_remaining_sec || true
calculate_reset_info claude secondary claude_week_reset_at claude_week_remaining_sec || true
calculate_reset_info codex primary codex_5h_reset_at codex_5h_remaining_sec || true
calculate_reset_info codex secondary codex_week_reset_at codex_week_remaining_sec || true

text_parts=()
tooltip_parts=()
remaining_values=()
class=""

if [ -n "$claude_primary_used" ] || [ -n "$claude_secondary_used" ]; then
  c5h_left="--"
  cweek_left="--"
  if [ -n "$claude_primary_used" ]; then
    c5h_left=$(provider_remaining_percent claude "$claude_primary_used")
    remaining_values+=("$c5h_left")
  fi
  if [ -n "$claude_secondary_used" ]; then
    cweek_left=$(provider_remaining_percent claude "$claude_secondary_used")
    remaining_values+=("$cweek_left")
  fi
  c5h_markup=$(render_value "$c5h_left" "5h")
  cweek_markup=$(render_value "$cweek_left" "w")
  text_parts+=("${ANTHROPIC_GLYPH} ${c5h_markup}/${cweek_markup}")

  # Build multi-line tooltip for Anthropic
  claude_lines=()
  claude_lines+=("Anthropic ${ANTHROPIC_GLYPH}")

  c5h_line="  5h: ${c5h_left}% remaining"
  if [ -n "$claude_5h_remaining_sec" ]; then
    c5h_line="${c5h_line}
     resets in $(format_duration "$claude_5h_remaining_sec")"
  fi
  claude_lines+=("$c5h_line")

  cweek_line="  Weekly: ${cweek_left}% remaining"
  if [ -n "$claude_week_remaining_sec" ]; then
    cweek_line="${cweek_line}
     resets in $(format_duration "$claude_week_remaining_sec")"
  fi
  claude_lines+=("$cweek_line")

  # Join lines with newlines for tooltip
  claude_tooltip=$(printf '%s\n' "${claude_lines[@]}")
  # Remove trailing newline
  claude_tooltip="${claude_tooltip%\n}"
  tooltip_parts+=("$claude_tooltip")
else
  text_parts+=("${ANTHROPIC_GLYPH} --")
  if [ -n "$claude_error" ]; then
    tooltip_parts+=("Claude: ${claude_error}")
  fi
fi

if [ -n "$codex_primary_used" ] || [ -n "$codex_secondary_used" ]; then
  o5h_left="--"
  oweek_left="--"
  if [ -n "$codex_primary_used" ]; then
    o5h_left=$(provider_remaining_percent codex "$codex_primary_used")
    remaining_values+=("$o5h_left")
  fi
  if [ -n "$codex_secondary_used" ]; then
    oweek_left=$(provider_remaining_percent codex "$codex_secondary_used")
    remaining_values+=("$oweek_left")
  fi
  o5h_markup=$(render_value "$o5h_left" "5h")
  oweek_markup=$(render_value "$oweek_left" "w")
  text_parts+=("${OPENAI_GLYPH} ${o5h_markup}/${oweek_markup}")

  # Build multi-line tooltip for OpenAI
  codex_lines=()
  codex_lines+=("OpenAI ${OPENAI_GLYPH}")

  o5h_line="  5h: ${o5h_left}% remaining"
  if [ -n "$codex_5h_remaining_sec" ]; then
    o5h_line="${o5h_line}
     resets in $(format_duration "$codex_5h_remaining_sec")"
  fi
  codex_lines+=("$o5h_line")

  oweek_line="  Weekly: ${oweek_left}% remaining"
  if [ -n "$codex_week_remaining_sec" ]; then
    oweek_line="${oweek_line}
     resets in $(format_duration "$codex_week_remaining_sec")"
  fi
  codex_lines+=("$oweek_line")

  # Join lines with newlines for tooltip
  codex_tooltip=$(printf '%s\n' "${codex_lines[@]}")
  # Remove trailing newline
  codex_tooltip="${codex_tooltip%\n}"
  tooltip_parts+=("$codex_tooltip")
else
  text_parts+=("${OPENAI_GLYPH} --")
  if [ -n "$codex_error" ]; then
    tooltip_parts+=("OpenAI: ${codex_error}")
  fi
fi

if [ "${#remaining_values[@]}" -gt 0 ]; then
  min_left=101
  for value in "${remaining_values[@]}"; do
    if [ "$value" -lt "$min_left" ]; then
      min_left="$value"
    fi
  done
  if [ "$min_left" -le 10 ]; then
    class="critical"
  elif [ "$min_left" -le 25 ]; then
    class="warning"
  fi
else
  class="warning"
fi

text=$(IFS=' | '; printf '%s' "${text_parts[*]}")
# Join provider tooltips with blank line separator
tooltip=$(IFS=$'\n\n'; printf '%s' "${tooltip_parts[*]}")

# Build JSON manually with proper newline escaping
json_text=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g')
json_tooltip=$(printf '%s' "$tooltip" | sed 's/\\/\\\\/g; s/"/\\"/g; :a; N; $!ba; s/\n/\\n/g')
json_class=$(printf '%s' "$class" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$json_text" "$json_tooltip" "$json_class"
