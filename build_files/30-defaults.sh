#!/usr/bin/env bash
# System defaults that keep the Kinoite experience intact.
# Static files (ntsync, units, scripts) come from system_files/.
set -euxo pipefail

# --- Automatic OS updates: download + stage in the background, apply on the
#     next reboot you do yourself (never reboots on its own).
if grep -qE '^#?AutomaticUpdatePolicy=' /etc/rpm-ostreed.conf; then
    sed -i -E 's/^#?AutomaticUpdatePolicy=.*/AutomaticUpdatePolicy=stage/' /etc/rpm-ostreed.conf
else
    printf '[Daemon]\nAutomaticUpdatePolicy=stage\n' >> /etc/rpm-ostreed.conf
fi
systemctl enable rpm-ostreed-automatic.timer

# --- Monthly Btrfs scrub (finds silent data corruption early)
systemctl enable btrfs-scrub-monthly.timer

# --- Zed (official script, per user on first login)
chmod 0755 /usr/libexec/zed-install
systemctl --global enable zed-install.service

# --- Flatpak: one-time switch from Fedora's remote to Flathub
#     (Discover keeps Flatpaks updated on its own)
chmod 0755 /usr/libexec/flathub-migrate
systemctl enable flathub-migrate.service

# --- Photos: KDE Photos (Koko, Flatpak from flathub-migrate) instead of
#     Gwenview. Plasma's defaults point every image type at Gwenview; switch
#     the types Koko handles to Koko and drop Gwenview from the rest (those
#     fall back to the next app that can open them).
MIMEAPPS=/usr/share/applications/kde-mimeapps.list
KOKO_TYPES="image/avif image/gif image/heif image/jpeg image/png image/bmp
    image/x-eps image/x-icns image/x-ico image/x-portable-bitmap
    image/x-portable-graymap image/x-portable-pixmap image/x-xbitmap
    image/x-xpixmap image/tiff image/x-psd image/x-webp image/webp image/svg+xml"
awk -v types="${KOKO_TYPES}" '
    BEGIN { n = split(types, t); for (i = 1; i <= n; i++) koko[t[i]] = 1 }
    /^[^#[].*=/ && /org\.kde\.gwenview\.desktop/ {
        key = substr($0, 1, index($0, "=") - 1)
        m = split(substr($0, index($0, "=") + 1), apps, ";")
        out = ""
        for (i = 1; i <= m; i++) {
            if (apps[i] == "") continue
            if (apps[i] == "org.kde.gwenview.desktop") {
                if (!(key in koko)) continue
                apps[i] = "org.kde.koko.desktop"
            }
            out = out (out == "" ? "" : ";") apps[i]
        }
        if (out != "") print key "=" out
        next
    }
    { print }' "${MIMEAPPS}" > /tmp/kde-mimeapps.list
# (`! grep` would not trip set -e, hence the explicit check)
if grep -q 'org\.kde\.gwenview\.desktop' /tmp/kde-mimeapps.list; then
    echo "Gwenview still referenced in ${MIMEAPPS}" >&2; exit 1
fi
grep -qx 'image/jpeg=org.kde.koko.desktop' /tmp/kde-mimeapps.list
install -m0644 /tmp/kde-mimeapps.list "${MIMEAPPS}"

# --- Signature policy so `bootc upgrade` verifies our cosign signatures
dnf5 -y install jq
REPO="${IMAGE_REGISTRY}/${IMAGE_NAME}"
KEY="/etc/pki/containers/${IMAGE_NAME}.pub"

install -Dm0644 "${CTX}/../cosign.pub" "${KEY}"

# Fedora ships the default in /usr/share; /etc overrides it if present.
POLICY=/etc/containers/policy.json
SRC="${POLICY}"
[ -f "${SRC}" ] || SRC=/usr/share/containers/policy.json
# rpm-ostree/bootc refuse signed pulls (ostree-image-signed) while the
# *default* rule is insecureAcceptAnything, even with a rule for our repo.
# So: default = reject, plus a transport-wide "" rule that keeps accepting
# everything else (podman, toolbox, distrobox behave as before). More
# specific scopes (our repo, Red Hat's registries) still require signatures.
jq --arg repo "${REPO}" --arg key "${KEY}" \
   '.default = [{"type": "reject"}]
    | .transports.docker[$repo] = [{
        "type": "sigstoreSigned",
        "keyPath": $key,
        "signedIdentity": {"type": "matchRepository"}
    }]
    | reduce ("docker", "docker-archive", "docker-daemon", "containers-storage",
              "oci", "oci-archive", "dir") as $t
        (.; .transports[$t][""] //= [{"type": "insecureAcceptAnything"}])' \
   "${SRC}" > /tmp/policy.json
jq -e '.default[0].type == "reject"' /tmp/policy.json >/dev/null
install -Dm0644 /tmp/policy.json "${POLICY}"

install -d /etc/containers/registries.d
cat > "/etc/containers/registries.d/${IMAGE_NAME}.yaml" <<EOF
docker:
  ${REPO}:
    use-sigstore-attachments: true
EOF

# --- Image metadata (handy for `cat /usr/share/image-info.json`)
cat > /usr/share/image-info.json <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-ref": "ostree-image-signed:docker://${REPO}",
  "base-image": "quay.io/fedora-ostree-desktops/kinoite",
  "fedora-version": "$(rpm -E %fedora)"
}
EOF
