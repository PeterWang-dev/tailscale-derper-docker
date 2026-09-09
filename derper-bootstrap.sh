#!/bin/sh
# derper-bootstrap.sh: detect the cert mode from DERP_HOST, then exec derper.
#
# Cert mode selection:
#   - DERP_HOST is an IP literal -> manual (self-signed cert, sha256-raw pinning in DERPMap)
#   - DERP_HOST is a domain      -> letsencrypt (ACME)
#   - DERP_CERTMODE=manual|letsencrypt forces a mode; "auto" (default) enables the detection above
#
# Per-mode defaults (overridable via DERP_ADDR / DERP_HTTP_PORT):
#   manual:      addr :12345, http-port -1
#   letsencrypt: addr :443,  http-port 80 (ACME HTTP-01 challenge)

set -eu

detect_certmode() {
	case "$1" in
	*:*) echo manual ;; # IPv6 literal
	*[!0-9.]*) echo letsencrypt ;; # anything but digits/dots -> domain
	*) echo manual ;; # IPv4 literal
	esac
}

certmode="${DERP_CERTMODE:-auto}"
if [ "$certmode" = auto ]; then
	certmode="$(detect_certmode "${DERP_HOST:?DERP_HOST must be set}")"
fi

if [ "$certmode" = letsencrypt ]; then
	addr="${DERP_ADDR:-:443}"
	http_port="${DERP_HTTP_PORT:-80}"
else
	addr="${DERP_ADDR:-:12345}"
	http_port="${DERP_HTTP_PORT:--1}"
fi

exec derper \
	--hostname="$DERP_HOST" \
	--certmode="$certmode" \
	--certdir="${DERP_CERTS:-/app/certs}" \
	--stun="${DERP_STUN:-true}" \
	--a="$addr" \
	--http-port="$http_port" \
	--verify-clients="${DERP_VERIFY_CLIENTS:-false}"
