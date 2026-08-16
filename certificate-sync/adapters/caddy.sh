# shellcheck shell=sh
# shellcheck disable=SC2154
# Local Caddy adapter. Installs the synchronized certificate as PEM files for
# a Caddy vhost on this host and restarts the service. Sourced by
# certificate-sync; referenced globals and helper functions are provided by
# the core after target validation.

adapter_validate_config() {
    : "${CADDY_CERT_FILE:=/etc/ssl/homehub/tls.crt}"
    : "${CADDY_KEY_FILE:=/etc/ssl/homehub/tls.key}"
    : "${CADDY_SERVICE:=caddy}"
    : "${CADDY_FILE_OWNER:=root:caddy}"
    command -v rc-service >/dev/null || die "rc-service is not available"
}

adapter_prepare() {
    :
}

adapter_fetch_served() {
    fetch_tls_certificate "$1"
}

# The install path writes local files as root; TLS trust in the served
# certificate is not used as an authentication channel, so both the strict
# and the bootstrap case proceed.
adapter_initialize_trust() {
    return 0
}

adapter_install() {
    install_cert=$1
    install_key=$2
    caddy_backup_cert=$tmp_dir/caddy-backup.crt
    caddy_backup_key=$tmp_dir/caddy-backup.key
    if [ -s "$CADDY_CERT_FILE" ] && [ -s "$CADDY_KEY_FILE" ]; then
        cp "$CADDY_CERT_FILE" "$caddy_backup_cert"
        cp "$CADDY_KEY_FILE" "$caddy_backup_key"
    fi
    install -o "${CADDY_FILE_OWNER%%:*}" -g "${CADDY_FILE_OWNER##*:}" -m 0640 \
        "$install_cert" "$CADDY_CERT_FILE" \
        || die "cannot install the Caddy certificate"
    install -o "${CADDY_FILE_OWNER%%:*}" -g "${CADDY_FILE_OWNER##*:}" -m 0640 \
        "$install_key" "$CADDY_KEY_FILE" \
        || die "cannot install the Caddy private key"
    rc-service "$CADDY_SERVICE" restart >/dev/null \
        || die "cannot restart $CADDY_SERVICE"
    caddy_wait_ready || die "$CADDY_SERVICE did not come back after restart"
    # Persist the rotated certificate across reboots on the diskless root.
    command -v lbu >/dev/null && lbu commit >/dev/null 2>&1 || true
}

caddy_wait_ready() {
    caddy_wait=0
    while [ "$caddy_wait" -lt 15 ]; do
        if nc -z -w1 "$CONNECT_IP" "$CONNECT_PORT" 2>/dev/null; then
            return 0
        fi
        caddy_wait=$((caddy_wait + 1))
        sleep 1
    done
    return 1
}

adapter_rollback() {
    [ -s "${caddy_backup_cert:-}" ] || return 1
    install -o "${CADDY_FILE_OWNER%%:*}" -g "${CADDY_FILE_OWNER##*:}" -m 0640 \
        "$caddy_backup_cert" "$CADDY_CERT_FILE" || return 1
    install -o "${CADDY_FILE_OWNER%%:*}" -g "${CADDY_FILE_OWNER##*:}" -m 0640 \
        "$caddy_backup_key" "$CADDY_KEY_FILE" || return 1
    rc-service "$CADDY_SERVICE" restart >/dev/null || return 1
    caddy_wait_ready
}
