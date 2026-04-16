#!/bin/bash
# Download AI models for local LLM eval tests.
# Models are stored permanently at ~/drift-state/models/ so tests never skip.
# Usage: bash scripts/download-models.sh

set -e
MODELS_DIR="$HOME/drift-state/models"
mkdir -p "$MODELS_DIR"

GEMMA_PATH="$MODELS_DIR/gemma-4-e2b-q4_k_m.gguf"
SMOL_PATH="$MODELS_DIR/smollm2-360m-instruct-q8_0.gguf"

GEMMA_URL="https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"
SMOL_URL="https://github.com/ashish-sadh/Drift/releases/download/models-v1/smollm2-360m-instruct-q8_0.gguf"

if [ -f "$GEMMA_PATH" ]; then
    echo "✅ Gemma 4 already present ($(du -sh "$GEMMA_PATH" | cut -f1))"
else
    echo "⬇️  Downloading Gemma 4 E2B Q4_K_M (~2.9GB)..."
    curl -L --progress-bar -o "$GEMMA_PATH" "$GEMMA_URL"
    echo "✅ Gemma 4 saved to $GEMMA_PATH"
fi

if [ -f "$SMOL_PATH" ]; then
    echo "✅ SmolLM2 already present ($(du -sh "$SMOL_PATH" | cut -f1))"
else
    echo "⬇️  Downloading SmolLM2 360M Q8 (~368MB)..."
    curl -L --progress-bar -o "$SMOL_PATH" "$SMOL_URL"
    echo "✅ SmolLM2 saved to $SMOL_PATH"
fi

echo ""
echo "Models ready at $MODELS_DIR:"
ls -lh "$MODELS_DIR"
echo ""
echo "Run LLM eval: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'"
