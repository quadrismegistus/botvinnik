#!/usr/bin/env bash
#
# Chess-GPT deps and weights. Everything lands INSIDE this directory (venv/,
# weights/), which .gitignore excludes — the weights are 100MB+ each and the
# venv carries torch.
#
#     bash scripts/engines/chessgpt/setup.sh            # the human-trained 8-layer
#     bash scripts/engines/chessgpt/setup.sh --all      # the whole comparison set
#
set -euo pipefail
cd "$(dirname "$0")"

# The corpus is the variable under study, so the default is the human-trained
# one and --all pulls the matched set: same architecture, same layer count,
# different teachers, plus an untrained control for the floor.
MODELS=("lichess_8layers_ckpt_no_optimizer.pt")
if [ "${1:-}" = "--all" ]; then
	MODELS+=(
		"stockfish_8layers_ckpt_no_optimizer.pt"
		"lichess_stockfish_mix_8layers_ckpt_no_optimizer.pt"
		"lichess_8layers_gt_18k_ckpt_no_optimizer.pt"
		"randominit_8layers_ckpt.pt"
	)
fi

if [ ! -d venv ]; then
	echo ">> venv"
	python3 -m venv venv
	./venv/bin/pip install --quiet --upgrade pip
fi
echo ">> deps (torch, python-chess, huggingface_hub)"
./venv/bin/pip install --quiet torch chess huggingface_hub

# The tokenizer, from the author's repo rather than reconstructed: the vocab is
# 32 characters and the STOI ORDER matters, so a hand-built one would encode
# silently wrong rather than fail.
if [ ! -f meta.pkl ]; then
	echo ">> meta.pkl (tokenizer)"
	curl -sfL -o meta.pkl \
		"https://raw.githubusercontent.com/adamkarvonen/chess_llm_interpretability/main/models/meta.pkl"
fi

mkdir -p weights
for m in "${MODELS[@]}"; do
	if [ -f "weights/$m" ]; then echo ">> have $m"; continue; fi
	echo ">> downloading $m"
	./venv/bin/python - "$m" <<'PY'
import shutil, sys
from huggingface_hub import hf_hub_download
name = sys.argv[1]
shutil.copy(hf_hub_download("adamkarvonen/chess_llms", name), f"weights/{name}")
PY
done
echo ">> ok. smoke test:  bash scripts/shims/chessgpt/run.sh <<< $'uci\nposition startpos\ngo\nquit'"
