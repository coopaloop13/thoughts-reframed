#!/usr/bin/env bash
# Start, stop, or inspect the VoiceStudio GPU pod on RunPod (the only service that bills while idle).
# Usage: scripts/voice-pod.sh start|stop|status   (reads RUNPOD_API_KEY and RUNPOD_POD_ID from backend/.env)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${RUNPOD_API_KEY:?set RUNPOD_API_KEY in backend/.env (RunPod console → Settings → API Keys)}"
: "${RUNPOD_POD_ID:?set RUNPOD_POD_ID in backend/.env}"
api() { curl -sS --max-time 60 -H "Authorization: Bearer $RUNPOD_API_KEY" -H 'content-type: application/json' "$@"; }
# POST an action and fail loudly with the API's message on any non-2xx.
act() { out=$(api -w '\n%{http_code}' -X POST -d "{\"action\":\"$1\"}" "$pod/action"); code=${out##*$'\n'}; body=${out%$'\n'*}
        case "$code" in 2*) ;; *) echo "runpod: $1 failed (HTTP $code): $body" >&2; exit 1;; esac; }
pod="https://api.runpod.io/v2/pods/$RUNPOD_POD_ID"
status() { api "$pod" | python3 -c "import json,sys; p=json.load(sys.stdin); print(f\"{p['name']} {p['id']}: {p['status']}  {p['cost']} USD/hr while running  gpu={p['gpu']['id']}\")"; }
case "${1:-}" in
  start) act start && echo "start requested"
         # ponytail: fixed 3-minute wait for /health; VoiceStudio boots in ~1 min once the image is cached
         for i in $(seq 1 36); do code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$VOICESTUDIO_URL/health" || true); [ "$code" = 200 ] && { echo "voicestudio healthy at $VOICESTUDIO_URL"; status; exit 0; }; sleep 5; done
         echo "pod started but /health not 200 after 3 min; check: $0 status" >&2; exit 1 ;;
  stop)  act stop && echo "stop requested (GPU billing ends; volume keeps the models)"; status ;;
  status) status ;;
  *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
