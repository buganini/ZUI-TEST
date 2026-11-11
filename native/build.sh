#!/bin/sh
set -eu
source_dir=$(realpath "$1")
lvgl_dir=$(realpath "$2")
mkdir -p "$3"
build_dir=$(realpath "$3")
if ! cmake -S "$source_dir" -B "$build_dir" "-DZUI_LVGL_DIR=$lvgl_dir" "-DCMAKE_BUILD_TYPE=$4" > "$build_dir/configure.log" 2>&1; then
    cat "$build_dir/configure.log" >&2
    exit 1
fi
if ! cmake --build "$build_dir" --parallel "${ZUI_JOBS:-4}" > "$build_dir/build.log" 2>&1; then
    tail -n 80 "$build_dir/build.log" >&2
    exit 1
fi
