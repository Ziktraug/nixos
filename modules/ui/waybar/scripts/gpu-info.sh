#!/run/current-system/sw/bin/bash
# GPU monitoring script for Waybar

smi_bin=""
for candidate in "$(command -v nvidia-smi 2>/dev/null)" \
  "/run/opengl-driver/bin/nvidia-smi" \
  "/run/current-system/sw/bin/nvidia-smi"
do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    smi_bin="$candidate"
    break
  fi
done

if [ -z "$smi_bin" ]; then
  printf '{"text":"N/A", "tooltip":"nvidia-smi not found"}'
  exit 0
fi

data=$(
  timeout 1s "$smi_bin" --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || true
)

if [ -z "$data" ]; then
  printf '{"text":"N/A", "tooltip":"GPU not available"}'
  exit 0
fi

usage=$(printf '%s\n' "$data" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}')
mem_used=$(printf '%s\n' "$data" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
mem_total=$(printf '%s\n' "$data" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
temp=$(printf '%s\n' "$data" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}')

if [ -z "$usage" ] || [ -z "$mem_used" ] || [ -z "$mem_total" ] || [ -z "$temp" ]; then
  printf '{"text":"N/A", "tooltip":"GPU parse failed"}'
  exit 0
fi

printf '{"text":"%s", "tooltip":"GPU: %s%% | Memory: %sMiB/%sMiB | Temp: %s°C"}' \
  "$usage" "$usage" "$mem_used" "$mem_total" "$temp"
