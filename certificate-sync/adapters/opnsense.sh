# shellcheck shell=sh
# shellcheck disable=SC2154
# OPNsense API adapter. Sourced by certificate-sync; referenced globals and
# helper functions are provided by the core after target validation.

adapter_validate_config() {
    : "${OPNSENSE_API_KEY_FILE:=/etc/certificate-sync/opnsense-api-key}"
    : "${OPNSENSE_API_SECRET_FILE:=/etc/certificate-sync/opnsense-api-secret}"
    : "${OPNSENSE_CERT_DESCRIPTION:=}"
    [ -n "$OPNSENSE_CERT_DESCRIPTION" ] \
        || die "OPNSENSE_CERT_DESCRIPTION must be configured"
    require_file "$OPNSENSE_API_KEY_FILE"
    require_file "$OPNSENSE_API_SECRET_FILE"
}

adapter_prepare() {
    opnsense_netrc=$tmp_dir/opnsense.netrc
    api_key=$(tr -d '\r\n' <"$OPNSENSE_API_KEY_FILE")
    api_secret=$(tr -d '\r\n' <"$OPNSENSE_API_SECRET_FILE")
    [ -n "$api_key" ] || die "OPNsense API key is empty"
    [ -n "$api_secret" ] || die "OPNsense API secret is empty"
    printf 'machine %s login %s password %s\n' \
        "$CERTIFICATE_HOSTNAME" "$api_key" "$api_secret" >"$opnsense_netrc"
    unset api_key api_secret
    opnsense_tls_mode=strict
    opnsense_active_pin=
    opnsense_base_url=https://$CERTIFICATE_HOSTNAME
    [ "$CONNECT_PORT" = 443 ] || opnsense_base_url=$opnsense_base_url:$CONNECT_PORT
}

adapter_fetch_served() {
    fetch_tls_certificate "$1"
}

adapter_initialize_trust() {
    strict_ok=$1
    served_pin=$2
    [ "$strict_ok" -eq 0 ] || return 0
    load_state
    if [ -n "$state_spki_pin" ] && [ "$state_spki_pin" = "$served_pin" ]; then
        opnsense_tls_mode=pinned
        opnsense_active_pin=$served_pin
        log "using the previously verified OPNsense SPKI pin"
    elif [ "$trust_current" -eq 1 ]; then
        opnsense_tls_mode=pinned
        opnsense_active_pin=$served_pin
        log "bootstrapping trust in the currently served OPNsense SPKI"
    else
        die "OPNsense TLS validation failed and its SPKI is not pinned"
    fi
}

opnsense_request() {
    request_method=$1
    request_path=$2
    request_output=$3
    request_data=${4:-}
    if [ "$opnsense_tls_mode" = pinned ]; then
        tls_args="--insecure --pinnedpubkey sha256//$opnsense_active_pin"
    else
        tls_args=
    fi
    if [ -n "$request_data" ]; then
        # shellcheck disable=SC2086
        curl --silent --show-error --fail --connect-timeout 5 --max-time 30 \
            --resolve "$CERTIFICATE_HOSTNAME:$CONNECT_PORT:$CONNECT_IP" \
            --netrc-file "$opnsense_netrc" $tls_args \
            --request "$request_method" --header 'Content-Type: application/json' \
            --data-binary "@$request_data" --output "$request_output" \
            "$opnsense_base_url$request_path"
    else
        # shellcheck disable=SC2086
        curl --silent --show-error --fail --connect-timeout 5 --max-time 30 \
            --resolve "$CERTIFICATE_HOSTNAME:$CONNECT_PORT:$CONNECT_IP" \
            --netrc-file "$opnsense_netrc" $tls_args \
            --request "$request_method" --output "$request_output" \
            "$opnsense_base_url$request_path"
    fi
}

adapter_install() {
    install_cert=$1
    install_key=$2
    search_json=$tmp_dir/cert-search.json
    backup_json=$tmp_dir/cert-backup.json
    opnsense_backup_cert=$tmp_dir/backup.crt
    opnsense_backup_key=$tmp_dir/backup.key
    update_json=$tmp_dir/cert-update.json
    response_json=$tmp_dir/response.json

    opnsense_request GET '/api/trust/cert/search?rowCount=-1' "$search_json" \
        || die "cannot search OPNsense certificates"
    opnsense_certificate_uuid=$(jq -r --arg description "$OPNSENSE_CERT_DESCRIPTION" '
        [.rows[] | select(.descr == $description and .in_use == "1")]
        | if length == 1 then .[0].uuid else empty end
    ' "$search_json")
    [ -n "$opnsense_certificate_uuid" ] \
        || die "expected exactly one in-use OPNsense certificate named $OPNSENSE_CERT_DESCRIPTION"

    opnsense_request GET "/api/trust/cert/get/$opnsense_certificate_uuid" "$backup_json" \
        || die "cannot back up the selected OPNsense certificate"
    jq -er '.cert.crt_payload' "$backup_json" >"$opnsense_backup_cert" \
        || die "OPNsense certificate backup has no certificate"
    jq -er '.cert.prv_payload' "$backup_json" >"$opnsense_backup_key" \
        || die "OPNsense certificate backup has no private key"
    opnsense_backup_fingerprint=$(certificate_fingerprint "$opnsense_backup_cert") \
        || die "cannot parse the OPNsense certificate backup"
    opnsense_backup_spki_pin=$(certificate_spki_pin "$opnsense_backup_cert") \
        || die "cannot parse the OPNsense backup public key"

    jq -n --arg description "$OPNSENSE_CERT_DESCRIPTION" \
        --rawfile certificate "$install_cert" --rawfile private_key "$install_key" '
        {cert: {action: "import", descr: $description,
          crt_payload: $certificate, prv_payload: $private_key}}
    ' >"$update_json"
    opnsense_request POST "/api/trust/cert/set/$opnsense_certificate_uuid" \
        "$response_json" "$update_json" || die "OPNsense rejected the certificate update"
    jq -e '.result == "saved"' "$response_json" >/dev/null \
        || die "OPNsense did not save the certificate update"

    empty_json=$tmp_dir/empty.json
    printf '{}\n' >"$empty_json"
    if ! opnsense_request POST '/api/core/service/restart/webgui' \
        "$response_json" "$empty_json"; then
        log "Web GUI restart closed the API connection; verification will continue"
    fi
}

adapter_rollback() {
    [ -s "${opnsense_backup_cert:-}" ] || return 1
    rollback_served=$tmp_dir/rollback-served.crt
    if adapter_fetch_served "$rollback_served"; then
        current_fingerprint=$(certificate_fingerprint "$rollback_served")
        if [ "$current_fingerprint" = "$desired_fingerprint" ]; then
            opnsense_tls_mode=pinned
            opnsense_active_pin=$desired_spki_pin
        elif [ "$current_fingerprint" = "$opnsense_backup_fingerprint" ]; then
            opnsense_tls_mode=pinned
            opnsense_active_pin=$opnsense_backup_spki_pin
        else
            return 1
        fi
    else
        return 1
    fi
    jq -n --arg description "$OPNSENSE_CERT_DESCRIPTION" \
        --rawfile certificate "$opnsense_backup_cert" \
        --rawfile private_key "$opnsense_backup_key" '
        {cert: {action: "import", descr: $description,
          crt_payload: $certificate, prv_payload: $private_key}}
    ' >"$update_json"
    opnsense_request POST "/api/trust/cert/set/$opnsense_certificate_uuid" \
        "$response_json" "$update_json" || return 1
    opnsense_request POST '/api/core/service/restart/webgui' \
        "$response_json" "$empty_json" || true
}
