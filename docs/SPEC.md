# Accord — build spec (2026-08-20)

**One-liner:** Omarchy themes fifteen applications beautifully. Accord does the rest —
GTK4, GTK3, and Qt apps follow your theme, light and dark, live.

Competition entry #3 (deadline: submit Sat Aug 22). Fixes basecamp/omarchy #7557
(21 reactions/24h, #2 most-reacted open issue) + the structural light-theme bug.

## Verified ground truth (all proven on THIS machine, 2026-08-20 — do not re-litigate)

1. `@define-color` in `~/.config/gtk-4.0/gtk.css` overrides libadwaita named colors.
   Sentinel #123456 → rgb(18,52,86) via Adw.init + lookup_color. PROVEN.
2. Same for `~/.config/gtk-3.0/gtk.css` + GTK3 named colors (`theme_bg_color` etc.). PROVEN.
3. `QT_QPA_PLATFORMTHEME=gtk3` is set by Omarchy → qgtk3 derives Qt palettes from GTK3.
   Qt apps pick palette at launch (verify visually with kdenlive/obs at the end).
4. `omarchy-theme-set` NEVER touches gsettings. `gtk-theme=Adwaita-dark` +
   `color-scheme=prefer-dark` are set once by first-run `gnome-theme.sh`. The 5 light
   themes (catppuccin-latte, flexoki-light, lupine, rose-pine, white) leave every
   GTK/Qt app dark. Accord fixes this by setting both keys per theme `mode`.
5. All 22 stock themes ship `colors.toml` with identical key shape (mode, accent,
   selection, muted, background ×4 tints, foreground ×4, ANSI ramp).
6. libadwaita reads user gtk.css ONLY at process start → running GTK4 daemons
   (nautilus etc.) must be SIGTERMed to repaint (D-Bus activatable, safe respawn).
7. System python is /usr/bin/python3 (3.14, tomllib built in). MUST hardcode
   `#!/usr/bin/python3` — mise shadows `python3` on PATH (known Omarchy issue class).
8. Active theme lives at `~/.local/state/omarchy/current/theme/` (symlink). Theme
   switch REPLACES the symlink — a file watcher on the resolved path can miss it;
   poll realpath+mtime as fallback.

## Deliverables

Repo `~/Projects/omarchy/competition/accord` = plugin (installable straight into
`~/.config/omarchy/plugins/io.github.vonsensey.accord`).

### manifest.json
- id `io.github.vonsensey.accord`, name "Accord", version 1.0.0, MIT, author vonsensey
- kinds: `["service","bar-widget","panel"]` (same proven multi-kind shape as omavet)
- keepLoaded true; barWidget block with schema:
  - `autoApply` enum On/Off default On — apply automatically on theme switch
  - `restartApps` enum On/Off default On — restart running GTK4 daemons after apply
- schemaVersion 1 (JSON number)

### bin/accord-apply (python3, #!/usr/bin/python3, zero deps beyond stdlib)
Reads active theme colors.toml → writes:
1. `~/.config/gtk-4.0/gtk.css` — libadwaita @define-color set:
   window_bg/fg, view_bg/fg, headerbar_bg/fg + backdrop, sidebar_bg + backdrop,
   card_bg/fg, dialog_bg, popover_bg/fg, accent_bg/accent_fg/accent_color,
   destructive_*, success_*, warning_*, error_*, borders, shade_color,
   scrollbar_outline. Mapping: window=background, view=dark_background (dark) /
   background (light: keep view lightest, window=dark_background), headerbar=
   darker_background, card/popover=lighter_background, accent=accent,
   destructive/error=red, success=green, warning=yellow.
2. `~/.config/gtk-3.0/gtk.css` — theme_bg_color, theme_fg_color, theme_base_color,
   theme_text_color, theme_selected_bg_color(accent), theme_selected_fg_color
   (on-accent), insensitive_bg/fg, borders, link_color(accent),
   success/warning/error_color + the wm_* set.
3. gsettings: `color-scheme` prefer-dark/prefer-light and `gtk-theme`
   Adwaita-dark/Adwaita per theme mode. First run saves prior values into state
   for revert. Skipped when $ACCORD_NO_GSETTINGS=1 (tests).
4. `~/.local/state/omarchy/accord/state.json` — schemaVersion, theme name, mode,
   resolved palette incl. on-accent + its luma separation, targets written,
   restarted apps, timestamps, saved prior gsettings.
5. Restart pass (unless --no-restart / setting Off): pgrep -x over allowlist
   {nautilus, geary, gnome-calendar, gnome-text-editor, loupe, evince, snapshot} →
   SIGTERM. Never anything else.

Behavior contracts:
- **On-accent contrast**: luma-distance test — pick whichever of theme
  background/foreground is farther from accent in perceived luma
  (0.299R+0.587G+0.114B). A naive "accent is dark" test fails on light themes.
  Test asserts separation ≥ 60/255 for all 22 stock themes (miasma known worst ~86).
- **User CSS preservation**: manage a marker block
  `/* >>> accord managed >>> */ ... /* <<< accord managed <<< */`. File absent →
  create with block only. File present without marker → one-time backup to
  `gtk.css.accord-backup`, write block FIRST then original content (user rules win).
  Rerun → replace block only, byte-identical if palette unchanged (no rewrite churn).
- `--revert` removes the block (restores backup if we made one) and restores saved
  gsettings. This is the uninstall story.
- Env overrides for tests: ACCORD_THEME_DIR, ACCORD_GTK4_CSS, ACCORD_GTK3_CSS,
  ACCORD_STATE_DIR, ACCORD_NO_GSETTINGS, ACCORD_NO_RESTART.
- Exit 0 with nothing written if colors.toml missing/unparseable (log to stderr).

### Service.qml
- Injected `manifest`; pattern-match mission-control Service.qml (proven).
- Timer poll 3s: Process runs `readlink -f theme-dir && stat -c %Y colors.toml`;
  on change (and autoApply) → run accord-apply (`--no-restart` when restartApps Off).
- Exposes: state (parsed state.json via FileView watch), applying bool, lastError.
- Receives settings pushed by BarWidget (services get no settings — verified contract).
- NO synchronous file reads in QML on the poll path.

### BarWidget.qml
- Compact glyph (palette icon) tinted with CURRENT accent from state.json — the
  widget itself is a live proof. Tooltip: "Accord — GTK & Qt follow <theme>" (literal
  strings only — PanelToolTip is AutoText; never interpolate file-derived text
  beyond the theme name... theme name comes from dir name; sanitize to [A-Za-z0-9 _-]).
- Click → summon panel. Right-click → apply now.
- All four bar orientations; Color singleton only; no Qt.darker for dimming (opacity).

### Panel.qml (the craft showcase)
- Header: "Accord" + theme name + mode chip + live accent swatch.
- Palette strip: swatches with hex labels (bg, view, headerbar, card, fg, accent,
  on-accent) — rendered FROM state.json, i.e. shows what was actually written.
- Targets list: GTK4 ✓ path / GTK3 ✓ path / Qt "via qgtk3, applies at app launch" /
  color-scheme value. Each row shows the real path written.
- Mock gallery: QML mockup of a libadwaita window (headerbar + sidebar + content +
  suggested-action button + entry + switch) painted with the generated palette —
  makes the mapping visible without launching anything.
- Actions row: "Apply now", "Restart apps" (with the allowlist shown), "Revert all".
- Esc closes; theme via Color singleton; borders via Border.surfaceSpec (see omavet).

### test/check.sh (plain bash asserts, no framework — house style from omavet/omarewind)
Fixtures: 2 synthetic themes (dark + light) + run against ALL 22 stock themes read-only.
Assert: correct CSS colors dark+light; on-accent choice correct on a light fixture
where naive test fails; separation ≥60 for all 22 stock themes; marker block
preserves pre-existing user css + backup created once; idempotent rerun byte-identical;
state.json valid + schemaVersion; --revert restores original file exactly;
missing colors.toml → exit 0, no writes; gsettings skipped under ACCORD_NO_GSETTINGS.
Target: 45+ assertions, all passing via `bash test/check.sh`.

### Docs
README: hero pitch, before/after, install (git clone + omarchy plugin add), keybind
suggestion, **"What it writes, and what it does not"** (exhaustive: 2 css files
w/ marker blocks, 2 gsettings keys w/ saved originals, 1 state dir; reads theme dir
only; zero network; restart allowlist named), Limits section (Qt at launch; GTK3
apps with hand-rolled CSS may partially follow; flatpak apps need
--filesystem=xdg-config/gtk-4.0 note), Remove section (plugin disable + accord-apply
--revert + rm state), measured numbers (apply wall-time, helper peak RSS).
LICENSE MIT. .gitignore.

## Acceptance (in order — do not skip)
1. `bash test/check.sh` all green.
2. `omarchy plugin validate` clean after deploy to ~/.config/omarchy/plugins/.
3. LIVE: deploy, enable, apply → screenshot nautilus BEFORE and AFTER on current
   theme (ristretto per state; verify) — colors must visibly match the palette.
4. LIVE: `omarchy theme set catppuccin-latte` → nautilus turns LIGHT (the bug no one
   else can fix); screenshot; switch back.
5. Qt spot-check: launch obs or kdenlive after apply — palette follows (screenshot).
6. Widget visible in bar, panel opens, gallery matches real nautilus colors.
7. Restart shell before any screenshot used publicly (staleness lesson).

## Style rules
- Follow existing omavet/omarewind repo idioms (commit style, README voice, check.sh).
- Deliberate-simplification comments: keep the caveat sentence, NO "ponytail:" label.
- Never hardcode colors in QML — Color singleton + state.json palette only.
- Shortest working diff; no speculative options.
