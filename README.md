# kinoite-plus

Stock **Fedora Kinoite 45** (`quay.io/fedora-ostree-desktops/kinoite`) with
**RPM Fusion** as the main external source, media & gaming addons, and a few
sensible desktop defaults. Built, signed and published daily by GitHub Actions
as `ghcr.io/<user>/kinoite-plus`. Images are rechunked into per-package
layers, so updates only download what changed. No Steam Gaming Mode, same KDE
Plasma as Kinoite.

## What's added

| Area | Content |
|---|---|
| Repos | RPM Fusion free, nonfree, nonfree-steam and 1Password's repo, at build time only (not left on the system) |
| Apps | 1Password desktop app + `op` CLI (works with the preinstalled Firefox RPM) |
| Codecs | full `ffmpeg`, GStreamer libav/bad-freeworld/ugly |
| HW video | `mesa-va-drivers-freeworld` (H.264/HEVC on AMD); skipped for a day if RPM Fusion's build doesn't match Fedora's Mesa yet (warning in the build log) |
| Gaming | `steam`, `steam-devices`, `gamescope`, `mangohud` (+ i686) |
| Shell & CLI | `zsh`, `vim`, `btop`, `duf`, `fastfetch`, `glow`, `gum`, `jq`, `lsb_release`; archives: `lzip`, 7-Zip, `unrar` (RPM Fusion); `fuse-libs` for AppImages |
| Tools | `distrobox`, `libva-utils`, `vulkan-tools`, `ddcutil` (monitor control via DDC/CI), `nvtop` (GPU monitor), `compsize` (Btrfs on-disk size), Btrfs Assistant |
| Defaults | `ntsync` loaded, monthly Btrfs scrub, Fractal Adjust udev rule (WebHID), staged auto-updates (never auto-reboot), cosign signature policy, one-time switch to Flathub-only Flatpaks, image metadata in `/usr/share/image-info.json` |

### Homebrew & Zed

Neither can live in the image (`/home` is per machine):

- **Homebrew** is not part of the image. Install it yourself with the
  [official installer](https://brew.sh) (it works as-is on Kinoite);
  `/etc/profile.d/brew.sh` then puts `brew` on the `PATH`, no shell config
  needed. Use it for CLI toolchains (Go, Node, kubectl …) or `brew bundle`
  with your Mac `Brewfile`.
- `zed-install.service` (user, first login): runs Zed's official
  `install.sh` into `~/.local`. Zed updates itself. Retries every minute
  until the network is up. Runs once per user (stamp in
  `~/.local/state/zed-install.done`; delete it to re-run), so removing Zed
  with `zed --uninstall` is respected. Log: `journalctl --user -u zed-install`.

### 1Password

Installed from 1Password's official repo during the build, so every image
carries the current release; the repo itself is not left on the system.
Browser integration needs a native browser, so Firefox stays the Fedora RPM.
Because `/opt` lives in `/var` on atomic systems, the app is moved to
`/usr/lib/1Password` and linked back to `/opt/1Password` at boot. The
`onepassword` (1500), `onepassword-cli` (1600) and `onepassword-mcp` (1700)
groups have fixed GIDs via `sysusers.d`.

### Flathub-only Flatpaks

A fresh Kinoite install puts some KDE apps (Okular, Gwenview, KCalc, Elisa, …)
on the system as Flatpaks from Fedora's remote.
`flathub-migrate.service` runs once after the first boot with network:

1. adds and enables Flathub,
2. moves every Fedora-remote app to Flathub (app data is kept),
3. removes the Fedora runtime and the `fedora` / `fedora-testing` remotes,
4. installs Vorta (Borg backups), Chromium and Vermouth (Windows games via Proton)
   from Flathub,
5. writes `/var/lib/kinoite-plus/flathub-migrate.done` and never runs again.

While Flathub isn't reachable it retries every minute. If single apps fail to
install, the others still go ahead; the run is retried up to 5 times, then the
failed apps are listed in the log and the migration ends. Each app's runtime
is downloaded before the Fedora build is removed, and an app whose Flathub
install fails afterwards is retried on the next run. If an app is not on Flathub (or
can't be installed from there), the Fedora build and remote are kept. Check
progress with `journalctl -u flathub-migrate`.

## Setup (one time)

1. **Create the repo** on GitHub and push these files to `main`. The workflow
   builds on every push to `main` (except README-only changes), daily at
   04:20 UTC, and via *Run workflow*. The image is always named
   `kinoite-plus` (`IMAGE_NAME` in the workflow), whatever the repo is called.
2. **Signing key** – on any machine with cosign:
   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair   # press Enter, no password
   gh secret set SIGNING_SECRET < cosign.key      # or: Settings → Secrets → Actions
   git add cosign.pub && git commit -m "Add signing key" && git push
   ```
   Never commit `cosign.key` (it's in `.gitignore`). `cosign.pub` is required:
   the build fails without it.
3. **Actions** tab → enable workflows if prompted. After the first green run,
   set the package visibility to *public* (Profile → Packages → *image* →
   Package settings) so `rpm-ostree` can pull without credentials.

## Switching an existing Kinoite/Fedora Atomic install

```bash
# Drop layered packages and RPM Fusion release RPMs — the image ships them now
rpm-ostree reset

# 1st rebase: unverified (the signature policy isn't on the system yet)
rpm-ostree rebase ostree-unverified-registry:ghcr.io/<user>/kinoite-plus:latest
systemctl reboot

# 2nd rebase: switch to the signed transport (policy now ships in the image)
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<user>/kinoite-plus:latest
systemctl reboot
```
Pin to a release with `:45`, or to a specific day with `:45-YYYYMMDD`. Roll back with
`rpm-ostree rollback`.

## Customizing

- **Packages:** edit the matching script in `build_files/` (`10-media.sh`,
  `15-hardware.sh`, `18-cli.sh`, `20-gaming.sh`, `25-1password.sh`), or drop a
  new `NN-something.sh` there – all scripts run in numeric order.
- **Default Flathub apps:** edit `DEFAULT_APPS` in
  `system_files/usr/libexec/flathub-migrate`.
- **Static files:** anything under `system_files/` is copied 1:1 to `/`.
- **Fedora version bump:** change `FEDORA_VERSION` in `.github/workflows/build.yml`.

## Local test build

```bash
podman build -t kinoite-plus:test .
```

## Next steps worth considering

- **ISO** via `bootc-image-builder` for fresh installs.
- **Flatpaks** (Heroic for GOG/Epic, ProtonPlus, Flatseal) stay Flatpaks
  rather than going into the image.
