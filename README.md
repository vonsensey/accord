# Accord

**Omarchy themes your terminal, your editor, and its own shell beautifully.
Accord does the rest: GTK4, GTK3, and Qt apps follow your theme — light and
dark, live.**

Open Nautilus on a stock Omarchy box and it renders in default Adwaita,
ignoring your theme entirely. Switch to a light theme and every GTK and Qt app
*stays dark* — the installer sets `gtk-theme` and `color-scheme` once, on first
boot, and nothing ever updates them again. Your desktop moves; the app
ecosystem doesn't.

Accord closes that gap. Enable it once and every theme switch carries your
whole desktop with it:

- **GTK4 / libadwaita** apps (Nautilus, Calendar, Text Editor, Loupe, …) —
  themed through `~/.config/gtk-4.0/gtk.css`, the only user-level lever
  libadwaita honors.
- **GTK3** apps — themed through the classic named-color set in
  `~/.config/gtk-3.0/gtk.css`.
- **Qt 5 / Qt 6** apps — Omarchy ships `QT_QPA_PLATFORMTHEME=gtk3`, so Qt
  derives its palette from the GTK3 theme Accord just wrote. No qt5ct, no
  Kvantum, no extra machinery.
- **Light themes actually go light.** Accord flips `color-scheme` and
  `gtk-theme` to match the theme's declared mode — the half of the problem
  nobody sees until they try Catppuccin Latte.

## What you get

- A **service** that notices theme switches (including the symlink swap
  `omarchy-theme-set` performs, which file watchers miss) and re-applies
  within a few seconds.
- A **bar widget**: a dot wearing your current accent — read back from what
  was actually written, so the dot itself is proof the bridge ran. Click for
  the panel, right-click to re-apply.
- A **panel**: a live preview window painted from the exact palette on disk,
  swatches with hex values, and a list of every file and setting Accord
  touched, including which app daemons were restarted and which are pending.

## The craft bits

- **On-accent text is chosen by luma distance** — whichever of the theme's
  background/foreground sits farther from the accent in perceived brightness.
  A naive "is the accent dark?" test fails on light themes. The test suite
  sweeps all 22 stock themes and asserts a minimum separation of 60/255;
  the worst case is miasma at 87.
- **Your gtk.css survives.** Accord manages a clearly marked block, backs up
  any pre-existing file once (`gtk.css.accord-backup`), puts its block *first*
  so your rules win conflicts, and `--revert` restores your original bytes
  exactly.
- **App restarts are surgical.** GTK4 apps read the user stylesheet only at
  process startup, so windowless daemons (Nautilus's background service and
  friends) keep painting stale colors until restarted. Accord SIGTERMs only a
  short allowlist of D-Bus-activatable apps, and **never one that owns a
  visible window** — those repaint on their next launch and the panel says so.
- **Idempotent and quiet.** Re-applying an unchanged theme writes nothing —
  byte-compared before write, so file watchers see zero churn.

Measured on Omarchy 4.0.0 (2026-08): one apply is a single short-lived
process — ~40 ms wall, ~19 MB peak RSS — writing 2.2 KB + 1.1 KB of CSS.
The resident service is a QML timer polling one `readlink` every 3 s.

## Install

```sh
git clone https://github.com/vonsensey/accord \
  ~/.config/omarchy/plugins/io.github.vonsensey.accord \
  && omarchy plugin enable io.github.vonsensey.accord
```

Then add the **Accord** widget to your bar (Omarchy settings → Bar) if you
want the accent dot; the service themes your apps either way. Settings:
auto-apply on theme switch (On/Off) and restart of background GTK apps
(On/Off).

## Remove

```sh
~/.config/omarchy/plugins/io.github.vonsensey.accord/bin/accord-apply --revert \
  && omarchy plugin disable io.github.vonsensey.accord \
  && rm -rf ~/.config/omarchy/plugins/io.github.vonsensey.accord \
            ~/.local/state/omarchy/accord
```

`--revert` restores your original `gtk.css` files (byte-identical, from the
one-time backups), removes what Accord created, and restores the
`color-scheme`/`gtk-theme` values it found on first run.

## What it writes, and what it does not

- **Writes exactly:**
  - `~/.config/gtk-4.0/gtk.css` and `~/.config/gtk-3.0/gtk.css` — a marked,
    replaceable block; pre-existing content is backed up once and preserved.
  - Two GNOME settings: `org.gnome.desktop.interface color-scheme` and
    `gtk-theme` — originals saved to state for revert.
  - `~/.local/state/omarchy/accord/state.json` — what was applied, for the
    widget and panel.
- **Reads only** the active theme's `colors.toml`. Nothing else.
- **No network. Ever.** No elevation, no daemons, no writes anywhere else.
- The restart allowlist is exactly: nautilus, geary, gnome-calendar,
  gnome-text-editor, loupe, evince, snapshot — SIGTERM, windowless only.

## Limits, honestly

- **Qt apps pick the palette up at launch**, not live — qgtk3 reads the GTK
  theme when the app starts. Launch after a theme switch and it matches.
- **GTK3 recoloring covers apps that use the standard named colors**
  (anything Adwaita-based — the default on Omarchy). A GTK3 app shipping its
  own hand-rolled theme may only partially follow.
- **Flatpak apps** need the usual hole punched to see host GTK config:
  `flatpak override --user --filesystem=xdg-config/gtk-4.0:ro <app>`.
- Accord recolors stock Adwaita rather than swapping widget themes — that is
  what keeps it a 3 KB CSS bridge instead of a theme engine.

## Test

```sh
bash test/check.sh
```

48 plain-bash assertions: palette mapping for dark and light fixtures,
on-accent contrast across every stock theme, marker-block preservation of
pre-existing user css, byte-identical revert, idempotent reruns, and
graceful behavior on missing or malformed theme input.
