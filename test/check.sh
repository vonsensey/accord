#!/usr/bin/env bash
# Plain-bash asserts for bin/accord-apply. No framework. Exit 0 = pass.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
APPLY="$HERE/../bin/accord-apply"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAILED=0
assert() { # $1 = description, $2 = 0/1 pass flag
  if [ "$2" = "0" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1"
    FAILED=1
  fi
}

# Every test run: fixed css/state targets, no gsettings, no restarts.
run_apply() { # $1 = theme dir, remaining args passed through
  local theme=$1; shift
  ACCORD_THEME_DIR="$theme" \
  ACCORD_GTK4_CSS="$WORK/gtk-4.0/gtk.css" \
  ACCORD_GTK3_CSS="$WORK/gtk-3.0/gtk.css" \
  ACCORD_STATE_DIR="$WORK/state" \
  ACCORD_NO_GSETTINGS=1 \
    "$APPLY" --no-restart "$@"
}

css4="$WORK/gtk-4.0/gtk.css"
css3="$WORK/gtk-3.0/gtk.css"
state="$WORK/state/state.json"
jqs() { jq -r "$1" "$state" 2>/dev/null; }

# ------------------------------------------------------------ run 1: dark theme
run_apply "$HERE/fixtures/accord-dark"
assert "dark: apply exits 0" $?

assert "dark: gtk4 css written" "$([ -s "$css4" ]; echo $?)"
assert "dark: gtk3 css written" "$([ -s "$css3" ]; echo $?)"
assert "dark: window_bg is theme background" \
  "$(grep -q '@define-color window_bg_color #202020;' "$css4"; echo $?)"
assert "dark: view_bg is dark_background" \
  "$(grep -q '@define-color view_bg_color #181818;' "$css4"; echo $?)"
assert "dark: headerbar_bg is darker_background" \
  "$(grep -q '@define-color headerbar_bg_color #101010;' "$css4"; echo $?)"
assert "dark: card_bg is lighter_background" \
  "$(grep -q '@define-color card_bg_color #2a2a2a;' "$css4"; echo $?)"
assert "dark: accent_bg is theme accent" \
  "$(grep -q '@define-color accent_bg_color #3050d0;' "$css4"; echo $?)"
assert "dark: on-accent picks foreground (farther in luma)" \
  "$(grep -q '@define-color accent_fg_color #e0e0e0;' "$css4"; echo $?)"
assert "dark: destructive maps to red" \
  "$(grep -q '@define-color destructive_bg_color #d04040;' "$css4"; echo $?)"
assert "dark: gtk3 selected bg is accent" \
  "$(grep -q '@define-color theme_selected_bg_color #3050d0;' "$css3"; echo $?)"
assert "dark: gtk3 base is view color" \
  "$(grep -q '@define-color theme_base_color #181818;' "$css3"; echo $?)"
assert "dark: both files start with the managed marker" \
  "$([ "$(head -c 14 "$css4")" = "/* >>> accord:" ] && [ "$(head -c 14 "$css3")" = "/* >>> accord:" ]; echo $?)"

assert "dark: state.json is valid json with schemaVersion 1" \
  "$(jq -e '.schemaVersion == 1' "$state" >/dev/null; echo $?)"
assert "dark: state records mode dark" "$([ "$(jqs .mode)" = dark ]; echo $?)"
assert "dark: state records theme name from dir" "$([ "$(jqs .theme)" = accord-dark ]; echo $?)"
assert "dark: state on_accent matches css" "$([ "$(jqs .palette.on_accent)" = '#e0e0e0' ]; echo $?)"
assert "dark: state separation is 139" "$([ "$(jqs .palette.separation)" = 139 ]; echo $?)"
assert "dark: gsettings skipped under ACCORD_NO_GSETTINGS" \
  "$([ "$(jqs .gsettings.applied)" = false ]; echo $?)"
assert "dark: both files reported created" \
  "$([ "$(jqs .files.gtk4.status)" = created ] && [ "$(jqs .files.gtk3.status)" = created ]; echo $?)"

# --------------------------------------------------- run 2: idempotent rerun
m4_before=$(stat -c %Y "$css4"); m3_before=$(stat -c %Y "$css3")
sleep 1.1
run_apply "$HERE/fixtures/accord-dark"
assert "rerun: exits 0" $?
assert "rerun: gtk4 css untouched (no watcher churn)" \
  "$([ "$(stat -c %Y "$css4")" = "$m4_before" ]; echo $?)"
assert "rerun: gtk3 css untouched" "$([ "$(stat -c %Y "$css3")" = "$m3_before" ]; echo $?)"
assert "rerun: status unchanged" "$([ "$(jqs .files.gtk4.status)" = unchanged ]; echo $?)"
assert "rerun: exactly one managed block" \
  "$([ "$(grep -c '>>> accord:managed' "$css4")" = 1 ]; echo $?)"

# ------------------------------------------------------------ run 3: light theme
run_apply "$HERE/fixtures/accord-light"
assert "light: apply exits 0" $?
assert "light: view keeps the lightest tone (background)" \
  "$(grep -q '@define-color view_bg_color #eff1f5;' "$css4"; echo $?)"
assert "light: window drops to dark_background" \
  "$(grep -q '@define-color window_bg_color #e3e4e8;' "$css4"; echo $?)"
assert "light: headerbar is darker_background" \
  "$(grep -q '@define-color headerbar_bg_color #d7d8dc;' "$css4"; echo $?)"
assert "light: on-accent picks background (farther in luma)" \
  "$(grep -q '@define-color accent_fg_color #eff1f5;' "$css4"; echo $?)"
assert "light: state records mode light" "$([ "$(jqs .mode)" = light ]; echo $?)"
assert "light: separation is 144" "$([ "$(jqs .palette.separation)" = 144 ]; echo $?)"

# ------------------------------------- run 4: pre-existing user css preserved
u4="$WORK/user/gtk-4.0/gtk.css"
mkdir -p "$WORK/user/gtk-4.0" "$WORK/user/gtk-3.0"
printf 'window { font-size: 15px; } /* mine */\n' > "$u4"
cp "$u4" "$WORK/user-original.css"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$u4" \
ACCORD_GTK3_CSS="$WORK/user/gtk-3.0/gtk.css" \
ACCORD_STATE_DIR="$WORK/state" \
ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart
assert "user css: apply exits 0" $?
assert "user css: original content survives after the block" \
  "$(grep -q 'font-size: 15px' "$u4" && [ "$(head -c 14 "$u4")" = "/* >>> accord:" ]; echo $?)"
assert "user css: one-time backup created with original bytes" \
  "$(cmp -s "$u4.accord-backup" "$WORK/user-original.css"; echo $?)"
assert "user css: reported merged" "$([ "$(jqs .files.gtk4.status)" = merged ]; echo $?)"

sleep 1.1
ACCORD_THEME_DIR="$HERE/fixtures/accord-light" \
ACCORD_GTK4_CSS="$u4" \
ACCORD_GTK3_CSS="$WORK/user/gtk-3.0/gtk.css" \
ACCORD_STATE_DIR="$WORK/state" \
ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart
assert "user css: theme switch replaces block, keeps user content once" \
  "$([ "$(grep -c 'font-size: 15px' "$u4")" = 1 ] && [ "$(grep -c '>>> accord:managed' "$u4")" = 1 ] && grep -q '#eff1f5' "$u4"; echo $?)"
assert "user css: backup still the untouched original" \
  "$(cmp -s "$u4.accord-backup" "$WORK/user-original.css"; echo $?)"

# ---------------------------------------------------------------- run 5: revert
ACCORD_THEME_DIR="$HERE/fixtures/accord-light" \
ACCORD_GTK4_CSS="$u4" \
ACCORD_GTK3_CSS="$WORK/user/gtk-3.0/gtk.css" \
ACCORD_STATE_DIR="$WORK/state" \
ACCORD_NO_GSETTINGS=1 "$APPLY" --revert
assert "revert: exits 0" $?
assert "revert: user file restored byte-identical" \
  "$(cmp -s "$u4" "$WORK/user-original.css"; echo $?)"
assert "revert: backup removed" "$([ ! -e "$u4.accord-backup" ]; echo $?)"
assert "revert: created-by-us file is deleted entirely" \
  "$([ ! -e "$WORK/user/gtk-3.0/gtk.css" ]; echo $?)"
assert "revert: state.json removed" "$([ ! -e "$state" ]; echo $?)"

# ------------------------------------------- run 6: missing/broken theme input
run_apply "$WORK/does-not-exist"
assert "missing theme dir: exits 0" $?
mkdir -p "$WORK/badtheme"
printf 'mode = [broken\n' > "$WORK/badtheme/colors.toml"
before_count=$(find "$WORK" -name 'gtk.css' | wc -l)
run_apply "$WORK/badtheme"
assert "malformed toml: exits 0" $?
assert "malformed toml: writes nothing new" \
  "$([ "$(find "$WORK" -name 'gtk.css' | wc -l)" = "$before_count" ]; echo $?)"
mkdir -p "$WORK/incomplete"
printf 'mode = "dark"\naccent = "#333333"\n' > "$WORK/incomplete/colors.toml"
run_apply "$WORK/incomplete"
assert "theme missing background/foreground: exits 0, no crash" $?

# ------------------------------- run 7: every stock theme produces sane output
STOCK=/usr/share/omarchy/themes
if [ -d "$STOCK" ]; then
  worst=999; worst_name=none; sweep_fail=0
  for t in "$STOCK"/*/; do
    name=$(basename "$t")
    [ -f "$t/colors.toml" ] || continue
    rm -f "$WORK/gtk-4.0/gtk.css" "$WORK/gtk-3.0/gtk.css"
    if ! run_apply "$t" >/dev/null 2>&1; then
      echo "     sweep: $name FAILED to apply"; sweep_fail=1; continue
    fi
    grep -q '@define-color accent_bg_color' "$css4" || { echo "     sweep: $name missing accent"; sweep_fail=1; }
    sep=$(jqs .palette.separation)
    [ -n "$sep" ] && [ "$sep" -lt "$worst" ] && { worst=$sep; worst_name=$name; }
    [ -n "$sep" ] && [ "$sep" -lt 60 ] && { echo "     sweep: $name separation $sep < 60"; sweep_fail=1; }
  done
  assert "all stock themes apply cleanly with on-accent separation >= 60 (worst: $worst_name=$worst)" "$sweep_fail"
else
  echo "skip - no stock themes dir on this machine"
fi

echo
if [ "$FAILED" = "0" ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "CHECKS FAILED"
  exit 1
fi
