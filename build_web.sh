#!/bin/bash -eu

EMSCRIPTEN_SDK_DIR="$HOME/emsdk"
OUT_DIR="build/web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

odin build source/main_web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -out:$OUT_DIR/game.wasm.obj

ODIN_PATH=$(odin root)

cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

files="$OUT_DIR/game.wasm.obj ${0%/*}/vendor_wasm/libraylib.web.a"

flags="-sUSE_GLFW=3 -sWARN_ON_UNDEFINED_SYMBOLS=0 --shell-file source/main_web/index_template.html"

emcc -o $OUT_DIR/index.html $files $flags

rm $OUT_DIR/game.wasm.obj

echo "Web build created in ${OUT_DIR}"
