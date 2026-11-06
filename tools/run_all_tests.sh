#!/bin/bash
# Full SurfForge regression: every tests/*.gd except generators / screenshot helpers, each with a time limit.
G="/c/Users/<user>/Downloads/Godot_v4.5.1-stable_win64.exe/Godot_v4.5.1-stable_win64_console.exe"
cd /d/SurfForge || exit 1
OUT="$TEMP/sf_regress"
rm -rf "$OUT"; mkdir -p "$OUT"
for f in tests/*.gd; do
	n=$(basename "$f" .gd)
	case "$n" in make_*|look_closeup|prefab_shot|shape_ui_shot|toolbar_shot|split_shot) continue;; esac
	mkdir -p "$OUT/$n"
	start=$(date +%s)
	timeout 600 "$G" --path . --resolution 1600x900 -s "res://$f" -- "$OUT/$n" > "$OUT/$n.log" 2>&1
	code=$?
	secs=$(( $(date +%s) - start ))
	fails=$(grep -cE "\bFAIL\b" "$OUT/$n.log")
	errs=$(grep -c "SCRIPT ERROR" "$OUT/$n.log")
	verdict=$(grep -E ": (PASS|FAIL)$" "$OUT/$n.log" | tail -1)
	echo "$n | exit $code | ${secs}s | FAIL lines $fails | script errors $errs | $verdict"
done
echo DONE
