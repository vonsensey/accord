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
assert "missing theme dir: exits 3 (nothing applied)" "$([ $? = 3 ]; echo $?)"
mkdir -p "$WORK/badtheme"
printf 'mode = [broken\n' > "$WORK/badtheme/colors.toml"
before_count=$(find "$WORK" -name 'gtk.css' | wc -l)
run_apply "$WORK/badtheme"
assert "malformed toml: exits 3" "$([ $? = 3 ]; echo $?)"
assert "malformed toml: writes nothing new" \
  "$([ "$(find "$WORK" -name 'gtk.css' | wc -l)" = "$before_count" ]; echo $?)"
mkdir -p "$WORK/incomplete"
printf 'mode = "dark"\naccent = "#333333"\n' > "$WORK/incomplete/colors.toml"
run_apply "$WORK/incomplete"
assert "theme missing background/foreground: exits 3, no crash" "$([ $? = 3 ]; echo $?)"
assert "failed apply leaves lastError in state for the panel" \
  "$(jq -e '.lastError | length > 0' "$state" >/dev/null; echo $?)"

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


# ---------------------------------------- run 8: symlinked gtk.css (dotfiles)
DOT="$WORK/dotfiles"; LNK="$WORK/link/gtk-4.0"
mkdir -p "$DOT" "$LNK"
printf 'window { font-weight: bold; } /* dotfiles */\n' > "$DOT/gtk.css"
cp "$DOT/gtk.css" "$WORK/dotfiles-original.css"
ln -s "$DOT/gtk.css" "$LNK/gtk.css"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$LNK/gtk.css" \
ACCORD_GTK3_CSS="$WORK/link/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" \
ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart >/dev/null
assert "symlink: apply keeps the symlink intact" "$([ -L "$LNK/gtk.css" ]; echo $?)"
assert "symlink: backup created next to the TARGET, not the link" \
  "$([ -f "$DOT/gtk.css.accord-backup" ]; echo $?)"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$LNK/gtk.css" \
ACCORD_GTK3_CSS="$WORK/link/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" \
ACCORD_NO_GSETTINGS=1 "$APPLY" --revert >/dev/null
assert "symlink: revert keeps the symlink" "$([ -L "$LNK/gtk.css" ]; echo $?)"
assert "symlink: target restored byte-identical" \
  "$(cmp -s "$DOT/gtk.css" "$WORK/dotfiles-original.css"; echo $?)"
assert "symlink: backup consumed" "$([ ! -e "$DOT/gtk.css.accord-backup" ]; echo $?)"

# --------------------------- run 9: truncated marker block self-heals to one
TR="$WORK/trunc"; mkdir -p "$TR"
printf '%s\n@define-color window_bg_color #dead00;\n' \
  "/* >>> accord:managed >>> generated from the active Omarchy theme; edits inside this block are overwritten */" > "$TR/gtk.css"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$TR/gtk.css" \
ACCORD_GTK3_CSS="$TR/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" \
ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart >/dev/null
assert "truncated marker: exactly one managed block after apply" \
  "$([ "$(grep -c '>>> accord:managed' "$TR/gtk.css")" = 1 ]; echo $?)"
assert "truncated marker: stale color gone, no duplicate define wins" \
  "$([ "$(grep -c 'window_bg_color' "$TR/gtk.css")" = 1 ] && grep -q '#202020' "$TR/gtk.css"; echo $?)"

# ------------------- run 10: revert preserves user edits made after the merge
PM="$WORK/postmerge"; mkdir -p "$PM"
printf 'window { font-size: 11px; }\n' > "$PM/gtk.css"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$PM/gtk.css" ACCORD_GTK3_CSS="$PM/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart >/dev/null
printf 'label { color: red; } /* added after merge */\n' >> "$PM/gtk.css"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$PM/gtk.css" ACCORD_GTK3_CSS="$PM/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" ACCORD_NO_GSETTINGS=1 "$APPLY" --revert >/dev/null
assert "post-merge edits: revert keeps BOTH user rules, drops the block" \
  "$(grep -q 'font-size: 11px' "$PM/gtk.css" && grep -q 'added after merge' "$PM/gtk.css" \
     && ! grep -q 'accord:managed' "$PM/gtk.css"; echo $?)"
assert "post-merge edits: backup kept as reference" \
  "$([ -f "$PM/gtk.css.accord-backup" ]; echo $?)"

# ------------------------------- run 11: non-UTF-8 user css round-trips exact
NU="$WORK/nonutf8"; mkdir -p "$NU"
printf 'window { } /* caf\xe9 latin-1 */\n' > "$NU/gtk.css"
cp "$NU/gtk.css" "$WORK/nonutf8-original.css"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$NU/gtk.css" ACCORD_GTK3_CSS="$NU/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart >/dev/null
assert "non-utf8 css: apply succeeds and keeps the raw bytes" \
  "$(grep -q 'accord:managed' "$NU/gtk.css" && grep -qa 'latin-1' "$NU/gtk.css"; echo $?)"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$NU/gtk.css" ACCORD_GTK3_CSS="$NU/gtk3.css" \
ACCORD_STATE_DIR="$WORK/state" ACCORD_NO_GSETTINGS=1 "$APPLY" --revert >/dev/null
assert "non-utf8 css: revert restores byte-identical" \
  "$(cmp -s "$NU/gtk.css" "$WORK/nonutf8-original.css"; echo $?)"

# ----------------- run 12: gsettings capture/restore via fake shim (hermetic)
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
GSTATE="$WORK/fake-gsettings-state"
printf "color-scheme prefer-dark\ngtk-theme MyUserTheme\n" > "$GSTATE"
cat > "$FAKEBIN/gsettings" <<FAKE
#!/usr/bin/env bash
STATE="$GSTATE"
case "\$1" in
  get) awk -v k="\$3" '\$1==k {print "'"'"'" \$2 "'"'"'"}' "\$STATE" ;;
  set) grep -v "^\$3 " "\$STATE" > "\$STATE.n"; echo "\$3 \$4" >> "\$STATE.n"; mv "\$STATE.n" "\$STATE" ;;
esac
FAKE
chmod +x "$FAKEBIN/gsettings"
GS="$WORK/gsettings-run"; mkdir -p "$GS"
PATH="$FAKEBIN:$PATH" \
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$GS/gtk.css" ACCORD_GTK3_CSS="$GS/gtk3.css" \
ACCORD_STATE_DIR="$GS/state" "$APPLY" --no-restart >/dev/null
assert "gsettings: originals captured on first apply" \
  "$(jq -e '.gsettings.saved["gtk-theme"] == "MyUserTheme"' "$GS/state/state.json" >/dev/null; echo $?)"
assert "gsettings: dark theme applied Adwaita-dark to live settings" \
  "$(grep -q 'gtk-theme Adwaita-dark' "$GSTATE"; echo $?)"
PATH="$FAKEBIN:$PATH" \
ACCORD_THEME_DIR="$HERE/fixtures/accord-light" \
ACCORD_GTK4_CSS="$GS/gtk.css" ACCORD_GTK3_CSS="$GS/gtk3.css" \
ACCORD_STATE_DIR="$GS/state" "$APPLY" --no-restart >/dev/null
assert "gsettings: light theme flips to prefer-light + Adwaita" \
  "$(grep -q 'color-scheme prefer-light' "$GSTATE" && grep -q 'gtk-theme Adwaita$' "$GSTATE"; echo $?)"
assert "gsettings: originals NOT overwritten on second apply" \
  "$(jq -e '.gsettings.saved["gtk-theme"] == "MyUserTheme"' "$GS/state/state.json" >/dev/null; echo $?)"
PATH="$FAKEBIN:$PATH" \
ACCORD_THEME_DIR="$HERE/fixtures/accord-light" \
ACCORD_GTK4_CSS="$GS/gtk.css" ACCORD_GTK3_CSS="$GS/gtk3.css" \
ACCORD_STATE_DIR="$GS/state" "$APPLY" --revert >/dev/null
assert "gsettings: revert restores the user's original values" \
  "$(grep -q 'gtk-theme MyUserTheme' "$GSTATE" && grep -q 'color-scheme prefer-dark' "$GSTATE"; echo $?)"

# ------------------ run 13: poisoned None originals recover on the next apply
PO="$WORK/poison"; mkdir -p "$PO/state"
printf '{"schemaVersion":1,"gsettings":{"saved":{"color-scheme":null,"gtk-theme":null}}}\n' > "$PO/state/state.json"
printf "color-scheme prefer-dark\ngtk-theme RealTheme\n" > "$GSTATE"
PATH="$FAKEBIN:$PATH" \
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$PO/gtk.css" ACCORD_GTK3_CSS="$PO/gtk3.css" \
ACCORD_STATE_DIR="$PO/state" "$APPLY" --no-restart >/dev/null
assert "poisoned Nones: re-captured real originals instead of keeping nulls" \
  "$(jq -e '.gsettings.saved["gtk-theme"] == "RealTheme"' "$PO/state/state.json" >/dev/null; echo $?)"

# --------------------- run 14: restart pass via fake hyprctl/pgrep (hermetic)
sleep 300 & VICTIM=$!
sleep 300 & WINDOWED=$!
cat > "$FAKEBIN/hyprctl" <<FAKE
#!/usr/bin/env bash
echo '[{"pid": $WINDOWED, "title": "fake window"}]'
FAKE
cat > "$FAKEBIN/pgrep" <<FAKE
#!/usr/bin/env bash
name="\${@: -1}"
[ "\$name" = nautilus ] && { echo $VICTIM; exit 0; }
[ "\$name" = geary ] && { echo $WINDOWED; exit 0; }
exit 1
FAKE
chmod +x "$FAKEBIN/hyprctl" "$FAKEBIN/pgrep"
RS="$WORK/restart-run"; mkdir -p "$RS"
PATH="$FAKEBIN:$PATH" \
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$RS/gtk.css" ACCORD_GTK3_CSS="$RS/gtk3.css" \
ACCORD_STATE_DIR="$RS/state" ACCORD_NO_GSETTINGS=1 "$APPLY" >/dev/null
sleep 0.3
assert "restart: windowless allowlisted app was SIGTERMed" \
  "$(kill -0 $VICTIM 2>/dev/null; [ $? != 0 ]; echo $?)"
assert "restart: windowed app spared and reported pending" \
  "$(kill -0 $WINDOWED 2>/dev/null && jq -e '.restarts.pending == ["geary"]' "$RS/state/state.json" >/dev/null; echo $?)"
assert "restart: windowless app reported restarted" \
  "$(jq -e '.restarts.restarted == ["nautilus"]' "$RS/state/state.json" >/dev/null; echo $?)"
kill $WINDOWED 2>/dev/null
# hyprctl broken -> nothing killed, pending lists only RUNNING apps
sleep 300 & VICTIM2=$!
cat > "$FAKEBIN/hyprctl" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
cat > "$FAKEBIN/pgrep" <<FAKE
#!/usr/bin/env bash
name="\${@: -1}"
[ "\$name" = nautilus ] && { echo $VICTIM2; exit 0; }
exit 1
FAKE
chmod +x "$FAKEBIN/hyprctl" "$FAKEBIN/pgrep"
rm -f "$RS/gtk.css"
PATH="$FAKEBIN:$PATH" \
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$RS/gtk.css" ACCORD_GTK3_CSS="$RS/gtk3.css" \
ACCORD_STATE_DIR="$RS/state" ACCORD_NO_GSETTINGS=1 "$APPLY" >/dev/null
assert "restart: hyprctl broken -> nothing killed, pending only running apps" \
  "$(kill -0 $VICTIM2 2>/dev/null && jq -e '.restarts.pending == ["nautilus"] and .restarts.restarted == []' "$RS/state/state.json" >/dev/null; echo $?)"
kill $VICTIM2 2>/dev/null

# ------------------------- run 15: XDG_STATE_HOME honored when no override set
XS="$WORK/xdg-state"
ACCORD_THEME_DIR="$HERE/fixtures/accord-dark" \
ACCORD_GTK4_CSS="$WORK/xdg-gtk4.css" ACCORD_GTK3_CSS="$WORK/xdg-gtk3.css" \
XDG_STATE_HOME="$XS" ACCORD_NO_GSETTINGS=1 \
  env -u ACCORD_STATE_DIR "$APPLY" --no-restart >/dev/null
assert "XDG_STATE_HOME: state lands where the shell service watches" \
  "$(jq -e '.schemaVersion == 1' "$XS/omarchy/accord/state.json" >/dev/null; echo $?)"

# -------------------- run 15b: theme.name sibling names the theme (omarchy 4)
NM="$WORK/named/current"; mkdir -p "$NM/theme"
cp "$HERE/fixtures/accord-dark/colors.toml" "$NM/theme/"
printf 'ristretto\n' > "$NM/theme.name"
ACCORD_THEME_DIR="$NM/theme" \
ACCORD_GTK4_CSS="$WORK/named-gtk4.css" ACCORD_GTK3_CSS="$WORK/named-gtk3.css" \
ACCORD_STATE_DIR="$WORK/named-state" ACCORD_NO_GSETTINGS=1 "$APPLY" --no-restart >/dev/null
assert "theme.name sibling wins over the directory name" \
  "$([ "$(jq -r .theme "$WORK/named-state/state.json")" = ristretto ]; echo $?)"

# ------------------------------ run 16: define-set completeness is pinned
run_apply "$HERE/fixtures/accord-dark" >/dev/null
assert "gtk4 css defines exactly 47 colors" \
  "$([ "$(grep -c '@define-color' "$css4")" = 47 ]; echo $?)"
assert "gtk3 css defines exactly 22 colors" \
  "$([ "$(grep -c '@define-color' "$css3")" = 22 ]; echo $?)"

echo
if [ "$FAILED" = "0" ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "CHECKS FAILED"
  exit 1
fi
