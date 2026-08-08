# shellcheck shell=sh
# shellcheck disable=SC2154
# OpenCCU SSH adapter. Sourced by certificate-sync; referenced globals and
# helper functions are provided by the core after target validation.

adapter_validate_config() {
    : "${OPENCCU_SSH_USER:=root}"
    : "${OPENCCU_SSH_PORT:=22}"
    : "${OPENCCU_SSH_IDENTITY_FILE:=/etc/certificate-sync/openccu_ed25519}"
    : "${OPENCCU_SSH_KNOWN_HOSTS_FILE:=/etc/certificate-sync/openccu_known_hosts}"
    case "$OPENCCU_SSH_PORT" in
        ''|*[!0-9]*) die "OPENCCU_SSH_PORT must be a TCP port number" ;;
    esac
    require_file "$OPENCCU_SSH_IDENTITY_FILE"
    require_file "$OPENCCU_SSH_KNOWN_HOSTS_FILE"
}

adapter_prepare() {
    openccu_ssh_options="-o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$OPENCCU_SSH_KNOWN_HOSTS_FILE -o ConnectTimeout=10 -p $OPENCCU_SSH_PORT -i $OPENCCU_SSH_IDENTITY_FILE"
}

adapter_fetch_served() {
    fetch_tls_certificate "$1"
}

adapter_initialize_trust() {
    # SSH authentication and host-key pinning are independent of Web UI TLS.
    return 0
}

adapter_install() {
    install_cert=$1
    install_key=$2
    install_fingerprint=$3
    # OpenCCU lighttpd expects a combined private-key and certificate-chain PEM.
    # Both the fixed SSH options and the validated fingerprint expand locally.
    # shellcheck disable=SC2086,SC2029
    { cat "$install_key"; cat "$install_cert"; } \
        | ssh $openccu_ssh_options "$OPENCCU_SSH_USER@$CONNECT_IP" \
            "install $install_fingerprint"
}

adapter_rollback() {
    expected_backup_fingerprint=$1
    # Both the fixed SSH options and the validated fingerprint expand locally.
    # shellcheck disable=SC2086,SC2029
    ssh $openccu_ssh_options "$OPENCCU_SSH_USER@$CONNECT_IP" \
        "rollback $expected_backup_fingerprint"
}
