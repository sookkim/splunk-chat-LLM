#!/usr/bin/env bash
# One-time host setup for this repo on Ubuntu 24.04 (tested target: EC2 m7i.2xlarge, no GPU).
# Run from the repo root as the ubuntu user:  bash scripts/setup_ec2.sh
# Then: fill in .env, log out/in (docker group), and ./run.sh infra && ./run.sh index && ./run.sh app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> OS packages"
sudo apt-get update -y
sudo apt-get install -y git curl lsof tmux build-essential cmake python3-venv python3-dev \
  libmagic1 poppler-utils libgl1 libglib2.0-0

echo "==> Docker Engine + compose plugin"
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker

echo "==> Python venv + dependencies"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip uv
# CPU-only torch first unless a GPU is present (saves ~3GB of CUDA wheels)
command -v nvidia-smi >/dev/null || uv pip install torch --index-url https://download.pytorch.org/whl/cpu
uv pip install -r requirements.txt
python -c "from opentelemetry.sdk.trace import SpanProcessor" \
  || { echo "!! opentelemetry-api/sdk versions differ; aligning"; \
       uv pip install "opentelemetry-api==$(python -c 'import importlib.metadata as m; print(m.version("opentelemetry-sdk"))')"; }

[[ -f .env ]] || { cp .env.example .env; chmod 600 .env; echo "==> Created .env from .env.example: fill in the empty values"; }

cat <<'EOF'

Done. Next:
  1. Fill in .env (AWS_BEARER_TOKEN_BEDROCK or an instance role, SPLUNK_ACCESS_TOKEN,
     SPLUNK_REALM, SPLUNK_AO_O11Y_TOKEN, SPLUNK_AO_PROJECT)
  2. Log out and back in so the docker group applies (docker ps must work without sudo)
  3. tmux new -s demo
     ./run.sh infra && ./run.sh index && ./run.sh app
  4. From your laptop: ssh -i <key.pem> -L 8501:localhost:8501 ubuntu@<EC2_IP>  →  http://localhost:8501
EOF
