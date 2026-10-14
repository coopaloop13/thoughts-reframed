#!/usr/bin/env bash
# Run VoiceStudio natively on this Mac (Apple GPU via MPS) instead of the RunPod pod.
# One-time setup:
#   git clone --depth 1 --branch v0.5.6 https://github.com/debpalash/VoiceStudio.git ~/Development/VoiceStudio
#   cd ~/Development/VoiceStudio && uv sync --locked
# Then in backend/.env: VOICESTUDIO_URL=http://host.docker.internal:3900 (the Compose'd backend reaches the host that way).
# Usage: scripts/voice-local.sh   (reads VOICESTUDIO_API_KEY from backend/.env; override the checkout with VOICESTUDIO_DIR)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${VOICESTUDIO_API_KEY:?set VOICESTUDIO_API_KEY in backend/.env}"
dir="${VOICESTUDIO_DIR:-$HOME/Development/VoiceStudio}"
[ -d "$dir/backend" ] || { echo "VoiceStudio checkout not found at $dir; see the setup comment in $0" >&2; exit 1; }
cd "$dir"
# SERVER_MODE relaxes the loopback-only gate: requests from the backend container arrive from Docker's gateway, not 127.0.0.1.
# Whisper Turbo (1.6 GB) instead of the 3 GB default; install once via POST /models/install {"repo_id":"mlx-community/whisper-large-v3-turbo"}.
export OMNIVOICE_SERVER_MODE=1 OMNIVOICE_API_KEY="$VOICESTUDIO_API_KEY" ASR_MODEL=mlx-community/whisper-large-v3-turbo
exec uv run --no-sync uvicorn main:app --app-dir backend --host 127.0.0.1 --port 3900
