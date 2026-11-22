#!/usr/bin/env bash
# 启动本工程（可传参数，例如 ./run.sh -- --ward）
cd "$(dirname "$0")"
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
engine="${GODOT_BIN:-godot}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  # class_name / 字体索引在首次导入时才生成；缓存缺失会导致脚本或字体解析失败
  "$engine" --headless --editor --path . --import --quit >/dev/null 2>&1 || true
fi
exec "$engine" --path . "$@"
