# VoiceStudio (TTS + voice clone + Whisper) for local docker compose. CPU only:
# containers on macOS cannot use the Apple GPU, so this is slow; `npm run voice:local`
# runs the same server natively on MPS when you need speed. Production uses RunPod.
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libsndfile1 git build-essential curl pkg-config libopus-dev \
    && rm -rf /var/lib/apt/lists/* && pip install --no-cache-dir uv
ARG VOICESTUDIO_REF=v0.5.6
RUN git clone --depth 1 --branch "$VOICESTUDIO_REF" https://github.com/debpalash/VoiceStudio.git /app
WORKDIR /app
RUN uv sync --locked --no-dev && rm -rf /root/.cache/uv
ENV OMNIVOICE_SERVER_MODE=1 OMNIVOICE_BIND_HOST=0.0.0.0 PYTHONUNBUFFERED=1 \
    OMNIVOICE_DATA_DIR=/app/omnivoice_data HF_HOME=/app/omnivoice_data/huggingface
# ponytail: pin a small English CTranslate2 Whisper that is NOT in VoiceStudio's model catalogue, so its
# documented fail-open rule auto-downloads it on first transcription instead of demanding a manual install.
# Upgrade path: a catalogue model (e.g. deepdml/faster-whisper-large-v3-turbo-ct2) plus POST /models/install.
ENV OMNIVOICE_ASR_BACKEND=faster-whisper ASR_MODEL_FASTER=Systran/faster-whisper-small.en
EXPOSE 3900
HEALTHCHECK --interval=15s --timeout=5s --start-period=180s --retries=5 CMD curl -sf http://127.0.0.1:3900/health || exit 1
CMD ["uv", "run", "--no-sync", "uvicorn", "main:app", "--app-dir", "backend", "--host", "0.0.0.0", "--port", "3900"]
