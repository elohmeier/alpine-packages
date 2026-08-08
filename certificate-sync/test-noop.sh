#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
sync_script=$script_dir/certificate-sync
test_dir=$(mktemp -d /tmp/certificate-sync-test.XXXXXX)
server_pid=

cleanup() {
    [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
    rm -rf -- "$test_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_dir/bin" "$test_dir/adapters" "$test_dir/targets" "$test_dir/state"
openssl req -x509 -newkey rsa:2048 -nodes -days 14 \
    -subj '/CN=gateway.example.com' \
    -addext 'subjectAltName=DNS:gateway.example.com' \
    -keyout "$test_dir/tls.key" -out "$test_dir/tls.crt" >/dev/null 2>&1

certificate=$(base64 <"$test_dir/tls.crt" | tr -d '\r\n')
private_key=$(base64 <"$test_dir/tls.key" | tr -d '\r\n')
jq -n --arg certificate "$certificate" --arg private_key "$private_key" '
    {type: "kubernetes.io/tls", metadata: {resourceVersion: "42"},
     data: {"tls.crt": $certificate, "tls.key": $private_key}}
' >"$test_dir/kube-secret.json"

cat >"$test_dir/bin/curl" <<'EOF'
#!/bin/sh
output=
url=
previous=
for argument do
    if [ "$previous" = output ]; then output=$argument; fi
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

cat >"$test_dir/adapters/noop.sh" <<'EOF'
adapter_validate_config() { :; }
adapter_prepare() { :; }
adapter_fetch_served() { fetch_tls_certificate "$1"; }
adapter_initialize_trust() { :; }
adapter_install() { return 99; }
adapter_rollback() { return 99; }
EOF

printf 'test-token\n' >"$test_dir/kube-token"
: >"$test_dir/curl-calls"
port=${CERTIFICATE_SYNC_TEST_PORT:-18444}
openssl s_server -quiet -www -accept "$port" \
    -cert "$test_dir/tls.crt" -key "$test_dir/tls.key" \
    >"$test_dir/server.log" 2>&1 &
server_pid=$!
sleep 1

cat >"$test_dir/common.conf" <<EOF
KUBE_API_SERVER="https://kube.test"
KUBE_CA_FILE="$test_dir/tls.crt"
KUBE_TOKEN_FILE="$test_dir/kube-token"
TARGET_CONFIG_DIR="$test_dir/targets"
ADAPTER_DIR="$test_dir/adapters"
STATE_BASE_DIR="$test_dir/state"
LOCK_BASE_DIR="$test_dir/lock"
EOF

cat >"$test_dir/targets/gateway.conf" <<EOF
ADAPTER="noop"
KUBE_NAMESPACE="certificates"
KUBE_SECRET_NAME="gateway-tls"
CERTIFICATE_HOSTNAME="gateway.example.com"
CONNECT_IP="127.0.0.1"
CONNECT_PORT="$port"
MINIMUM_VALID_DAYS="21"
EOF

real_curl=$(command -v curl)
PATH="$test_dir/bin:$PATH" \
REAL_CURL="$real_curl" \
CURL_CALL_LOG="$test_dir/curl-calls" \
KUBE_SECRET_FIXTURE="$test_dir/kube-secret.json" \
CURL_CA_BUNDLE="$test_dir/tls.crt" \
HTTPS_PROXY='' HTTP_PROXY='' ALL_PROXY='' NO_PROXY='gateway.example.com,kube.test' \
CERTIFICATE_SYNC_CONFIG="$test_dir/common.conf" \
    "$sync_script" --target gateway

grep -qx 'success=1' "$test_dir/state/gateway/state"
grep -qx 'resource_version=42' "$test_dir/state/gateway/state"
test "$(stat -c '%a' "$test_dir/state/gateway")" = 755
test "$(stat -c '%a' "$test_dir/state/gateway/state")" = 644
CERTIFICATE_SYNC_CONFIG="$test_dir/common.conf" \
    "$sync_script" --metrics \
    | grep -q '^certificate_sync,target=gateway,hostname=gateway.example.com configured=1i,success=1i,'
test "$(wc -l <"$test_dir/curl-calls")" -eq 2
grep -q '/api/v1/namespaces/certificates/secrets/gateway-tls$' "$test_dir/curl-calls"
grep -q "https://gateway.example.com:$port/$" "$test_dir/curl-calls"

echo 'certificate-sync generic no-op smoke test passed'
