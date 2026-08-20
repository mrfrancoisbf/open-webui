# syntax=docker/dockerfile:1

ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_SLIM=false
ARG USE_PERMISSION_HARDENING=false
ARG USE_CUDA_VER=cu128

ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""
ARG USE_AUXILIARY_EMBEDDING_MODEL=TaylorAI/bge-micro-v2

ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"
ARG BUILD_HASH=dev-build

ARG UID=0
ARG GID=0


######## WebUI frontend ########

FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS build

ARG BUILD_HASH
ARG NODE_OPTIONS=--max-old-space-size=8192

ENV NODE_OPTIONS=${NODE_OPTIONS}

WORKDIR /app

RUN apk add --no-cache git

COPY package.json package-lock.json ./

RUN npm ci --force

COPY . .

ENV APP_BUILD_HASH=${BUILD_HASH}

RUN npm run build


######## WebUI backend ########

FROM python:3.11-slim-bookworm AS base

ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_SLIM
ARG USE_PERMISSION_HARDENING
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL
ARG USE_AUXILIARY_EMBEDDING_MODEL
ARG UID
ARG GID

ENV PYTHONUNBUFFERED=1

ENV ENV=prod \
    PORT=8080 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_SLIM_DOCKER=${USE_SLIM} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL} \
    USE_AUXILIARY_EMBEDDING_MODEL_DOCKER=${USE_AUXILIARY_EMBEDDING_MODEL}

# Ollama is external in your Coolify setup.
ENV OLLAMA_BASE_URL="" \
    OPENAI_API_BASE_URL=""

ENV OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false

# Whisper
ENV WHISPER_MODEL="base" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models"

# RAG
ENV RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL_DOCKER" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL_DOCKER" \
    AUXILIARY_EMBEDDING_MODEL="$USE_AUXILIARY_EMBEDDING_MODEL_DOCKER" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models"

# Tiktoken
ENV TIKTOKEN_ENCODING_NAME="cl100k_base" \
    TIKTOKEN_CACHE_DIR="/app/backend/data/cache/tiktoken"

# Hugging Face
ENV HF_HOME="/app/backend/data/cache/embedding/models"

WORKDIR /app/backend

ENV HOME=/root

# User / permissions
RUN if [ $UID -ne 0 ]; then \
        if [ $GID -ne 0 ]; then \
            addgroup --gid $GID app; \
        fi; \
        adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma && \
    echo -n 00000000-0000-0000-0000-000000000000 \
    > $HOME/.cache/chroma/telemetry_user_id

RUN chown -R $UID:$GID /app $HOME


# ------------------------------------------------------------
# SYSTEM DEPENDENCIES
# ------------------------------------------------------------
#
# Conserved intentionally:
# - build-essential / gcc / python3-dev:
#   required because some Python packages may need native compilation.
# - pandoc:
#   used for document conversion.
# - ffmpeg:
#   used for audio/video processing and Whisper-related features.
# - libmariadb-dev:
#   kept for compatibility with OpenWebUI's supported DB stack.
# - libsm6/libxext6:
#   kept for image/vision-related Python dependencies.
# - git/curl/jq/ca-certificates/netcat/zstd:
#   used by the application/build/runtime tooling.
#
# The safest optimization here is therefore not to remove these
# dependencies blindly.

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        build-essential \
        pandoc \
        gcc \
        netcat-openbsd \
        curl \
        jq \
        ca-certificates \
        libmariadb-dev \
        python3-dev \
        ffmpeg \
        libsm6 \
        libxext6 \
        zstd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------
# PYTHON DEPENDENCIES
# ------------------------------------------------------------

COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

ENV UV_LINK_MODE=copy


# ------------------------------------------------------------
# PYTORCH + PYTHON PACKAGES
# ------------------------------------------------------------
#
# Your previous failure was a ReadTimeout while downloading
# torch-2.9.1+cpu from download-r2.pytorch.org.
#
# Keep the extended timeout/retry values.

RUN set -e; \
    pip3 install \
        --no-cache-dir \
        --default-timeout=1200 \
        --retries=10 \
        uv; \
    \
    if [ "$USE_CUDA" = "true" ]; then \
        \
        pip3 install \
            --default-timeout=1200 \
            --retries=10 \
            --no-cache-dir \
            'torch<=2.9.1' \
            torchvision \
            torchaudio \
            --index-url https://download.pytorch.org/whl/$USE_CUDA_DOCKER_VER; \
        \
        uv pip install \
            --system \
            --retries 10 \
            --timeout 1200 \
            --no-cache-dir \
            -r requirements.txt; \
        \
        python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')"; \
        python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ.get('AUXILIARY_EMBEDDING_MODEL', 'TaylorAI/bge-micro-v2'), device='cpu')"; \
        python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"; \
        python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"; \
        python -c "import nltk; nltk.download('punkt_tab')"; \
    \
    else \
        \
        pip3 install \
            --default-timeout=1200 \
            --retries=10 \
            --no-cache-dir \
            'torch<=2.9.1' \
            torchvision \
            torchaudio \
            --index-url https://download.pytorch.org/whl/cpu; \
        \
        uv pip install \
            --system \
            --retries 10 \
            --timeout 1200 \
            --no-cache-dir \
            -r requirements.txt; \
        \
        if [ "$USE_SLIM" != "true" ]; then \
            \
            python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')"; \
            python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ.get('AUXILIARY_EMBEDDING_MODEL', 'TaylorAI/bge-micro-v2'), device='cpu')"; \
            python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"; \
            python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"; \
            python -c "import nltk; nltk.download('punkt_tab')"; \
        fi; \
    fi; \
    \
    mkdir -p /app/backend/data && \
    chown -R $UID:$GID /app/backend/data && \
    rm -rf /root/.cache/pip


# ------------------------------------------------------------
# OLLAMA
# ------------------------------------------------------------
#
# IMPORTANT:
# Ollama is already running as a separate Coolify resource.
# We deliberately DO NOT install Ollama inside this image.
#
# USE_OLLAMA remains available for compatibility with your fork,
# but the default is false.


# ------------------------------------------------------------
# FRONTEND
# ------------------------------------------------------------

COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json


# ------------------------------------------------------------
# BACKEND
# ------------------------------------------------------------

COPY --chown=$UID:$GID ./backend .


# Runtime-generated static assets need write permissions.
RUN chgrp -R 0 /app/backend/open_webui/static && \
    chmod -R g=u /app/backend/open_webui/static


EXPOSE 8080


HEALTHCHECK CMD curl --silent --fail \
    http://localhost:${PORT:-8080}/health \
    | jq -ne 'input.status == true' || exit 1


# Optional OpenShift permission hardening
RUN if [ "$USE_PERMISSION_HARDENING" = "true" ]; then \
        set -eux; \
        chgrp -R 0 /app /root || true; \
        chmod -R g+rwX /app /root || true; \
        find /app -type d -exec chmod g+s {} + || true; \
        find /root -type d -exec chmod g+s {} + || true; \
    fi


USER $UID:$GID


ARG BUILD_HASH

ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true


CMD ["bash", "start.sh"]
