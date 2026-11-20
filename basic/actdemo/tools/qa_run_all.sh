#!/usr/bin/env bash
# 一键跑全部 QA 场景（不改游戏代码，只跑 tools/qa_*.gd）
# 用法： tools/qa_run_all.sh [输出目录]
set -u
GODOT=${GODOT:-$(command -v godot || true)}
if [ -z "$GODOT" ]; then
  echo "未找到 godot，可用 GODOT=/path/to/godot 指定" >&2
  exit 1
fi
OUT=${1:-/tmp/qa_out}
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  # class_name 索引在首次导入时才生成；缓存缺失会导致 QA 场景解析失败
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
sha1sum src/core/*.gd src/game/*.gd src/main.gd src/vesper/mech_rig.gd > "$OUT/src.sha1"
for t in qa_input qa_flow qa_death qa_vision qa_archer qa_boss qa_play qa_parry qa_hitparts qa_replay; do
  echo "=== $t ==="
  timeout 180 stdbuf -oL -eL "$GODOT" --headless --path . "res://scenes/$t.tscn" > "$OUT/$t.log" 2>&1
  echo "  exit=$?  $(grep -c '  FAIL' "$OUT/$t.log") FAIL / $(grep -c '  PASS' "$OUT/$t.log") PASS"
done
echo
echo "全部日志在 $OUT"
