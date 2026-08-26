#!/bin/bash -eu

OUT_DIR="build/desktop"
mkdir -p $OUT_DIR
odin build source/main_desktop -out:$OUT_DIR/snake
echo "Desktop build created in ${OUT_DIR}"
