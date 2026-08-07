#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
sync_script=$script_dir/opnsense-cert-sync
test_dir=$(mktemp -d /tmp/opnsense-cert-sync-test.XXXXXX)
server_pid=

cleanup() {
    [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
    rm -rf -- "$test_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_dir/bin" "$test_dir/state"
# Intentionally shorter than MINIMUM_VALID_DAYS: an already-live certificate
# remains healthy while cert-manager prepares its replacement.
openssl req -x509 -newkey rsa:2048 -nodes -days 14 \
    -subj '/CN=opnsense.example.com' \
    -addext 'subjectAltName=DNS:opnsense.example.com' \
    -keyout "$test_dir/tls.key" -out "$test_dir/tls.crt" >/dev/null 2>&1

certificate=$(base64 <"$test_dir/tls.crt" | tr -d '\r\n')
private_key=$(base64 <"$test_dir/tls.key" | tr -d '\r\n')
jq -n --arg certificate "$certificate" --arg private_key "$private_key" '
    {
      type: "kubernetes.io/tls",
      metadata: {resourceVersion: "42"},
      data: {"tls.crt": $certificate, "tls.key": $private_key}
    }
' >"$test_dir/kube-secret.json"

cat >"$test_dir/bin/curl" <<'EOF'
#!/bin/sh
output=
url=
previous=
for argument do
    if [ "$previous" = output ]; then
        output=$argument
    fi
    case "$argument" in
        --output) previous=output; continue ;;
        https://*) url=$argument ;;
    esac
    previous=
done
printf '%s\n' "$url" >>"$CURL_CALL_LOG"
case "$url" in
    */api/v1/namespaces/*/secrets/*)
        cp "$KUBE_SECRET_FIXTURE" "$output"
        exit 0
        ;;
esac
exec "$REAL_CURL" "$@"
EOF
chmod 755 "$test_dir/bin/curl"

printf 'test-token\n' >"$test_dir/kube-token"
printf 'test-key\n' >"$test_dir/opnsense-api-key"
printf 'test-secret\n' >"$test_dir/opnsense-api-secret"
: >"$test_dir/curl-calls"
real_curl=$(command -v curl)

port=${OPNSENSE_CERT_SYNC_TEST_PORT:-18443}
openssl s_server -quiet -www -accept "$port" \
    -cert "$test_dir/tls.crt" -key "$test_dir/tls.key" \
    >"$test_dir/server.log" 2>&1 &
server_pid=$!
sleep 1

cat >"$test_dir/config" <<EOF
KUBE_API_SERVER="https://kube.test"
KUBE_NAMESPACE="certificates"
KUBE_SECRET_NAME="opnsense-webgui-tls"
KUBE_CA_FILE="$test_dir/tls.crt"
KUBE_TOKEN_FILE="$test_dir/kube-token"
OPNSENSE_CONNECT_IP="127.0.0.1"
OPNSENSE_PORT="$port"
OPNSENSE_API_KEY_FILE="$test_dir/opnsense-api-key"
OPNSENSE_API_SECRET_FILE="$test_dir/opnsense-api-secret"
OPNSENSE_CERT_DESCRIPTION="opnsense-webgui"
CERTIFICATE_HOSTNAME="opnsense.example.com"
MINIMUM_VALID_DAYS="21"
STATE_DIR="$test_dir/state"
LOCK_DIR="$test_dir/lock"
EOF

PATH="$test_dir/bin:$PATH" \
REAL_CURL="$real_curl" \
CURL_CALL_LOG="$test_dir/curl-calls" \
KUBE_SECRET_FIXTURE="$test_dir/kube-secret.json" \
CURL_CA_BUNDLE="$test_dir/tls.crt" \
HTTPS_PROXY='' HTTP_PROXY='' ALL_PROXY='' NO_PROXY='opnsense.example.com,kube.test' \
OPNSENSE_CERT_SYNC_CONFIG="$test_dir/config" \
    "$sync_script"

grep -qx 'success=1' "$test_dir/state/state"
grep -qx 'resource_version=42' "$test_dir/state/state"
test "$(stat -c '%a' "$test_dir/state")" = 755
test "$(stat -c '%a' "$test_dir/state/state")" = 644
OPNSENSE_CERT_SYNC_CONFIG="$test_dir/does-not-exist" \
OPNSENSE_CERT_SYNC_METRICS_STATE="$test_dir/state/state" \
    "$sync_script" --metrics \
    | grep -q '^opnsense_cert_sync configured=1i,success=1i,'
test "$(wc -l <"$test_dir/curl-calls")" -eq 2
grep -q '/api/v1/namespaces/certificates/secrets/opnsense-webgui-tls$' \
    "$test_dir/curl-calls"
grep -q "https://opnsense.example.com:$port/$" "$test_dir/curl-calls"

echo 'opnsense-cert-sync no-op smoke test passed'
