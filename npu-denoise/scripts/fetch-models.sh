#!/usr/bin/env bash
# Fetch the DeepFilterNet3 streaming ONNX exports into the cache directory
# used by dfn.py.
set -euo pipefail

version=${1:-v0.5.6}
dest=${XDG_CACHE_HOME:-$HOME/.cache}/npu-denoise/models
url="https://raw.githubusercontent.com/Rikorose/DeepFilterNet/$version/models/DeepFilterNet3_onnx.tar.gz"

if [[ -f $dest/enc.onnx && -f $dest/erb_dec.onnx && -f $dest/df_dec.onnx ]]; then
    echo "models already present in $dest"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$dest"

echo "downloading $url"
curl -fsSL "$url" -o "$work/models.tar.gz"
tar -xzf "$work/models.tar.gz" -C "$work"
find "$work" -name '*.onnx' -exec cp {} "$dest"/ \;

for graph in enc erb_dec df_dec; do
    if [[ ! -f $dest/$graph.onnx ]]; then
        echo "missing $dest/$graph.onnx after extraction" >&2
        exit 1
    fi
done
echo "models in $dest"
