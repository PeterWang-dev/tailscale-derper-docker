# ip_derper

[![build](https://github.com/PeterWang-dev/ip_derper/actions/workflows/build.yml/badge.svg)](https://github.com/PeterWang-dev/ip_derper/actions/workflows/build.yml)

Deploy a self-hosted [Tailscale DERP server](https://tailscale.com/kb/1232/derp-servers) on a **bare IP address or a domain** — built from the official, unmodified `derper`.

- **IP mode**: works without any domain or DNS record; a self-signed certificate is generated automatically and clients pin it by fingerprint (`sha256-raw`).
- **Domain mode**: obtains and renews a Let's Encrypt certificate automatically (ACME).
- The mode is detected from `DERP_HOST`; no configuration branches, no patches.

## Background

This project started as a fork that patched `cmd/derper/cert.go` to skip the TLS SNI check so a DERP server could run on a bare IP. Since [v1.100.0 (Dec 2024)](https://github.com/tailscale/tailscale/releases/tag/v1.100.0) upstream derper natively supports this:

- `--hostname` accepts an IP literal with `--certmode=manual`, skipping SNI checks
- a self-signed certificate for the IP is generated automatically on first start

The patch, the `tailscale` submodule and the helper scripts are therefore gone. The image is now built with the official distribution path (`go install tailscale.com/cmd/derper@latest`, per [`cmd/derper/README.md`](https://github.com/tailscale/tailscale/blob/main/cmd/derper/README.md)) on top of the official Tailscale container image.

## Requirements

- Docker Engine 23+ (BuildKit) with the compose plugin
- Inbound access: `12345/tcp` (IP mode), `443/tcp` + `80/tcp` (domain mode), `3478/udp` (STUN)

## Quick start

```bash
# IP mode — no domain needed
DERP_HOST=203.0.113.10 docker compose up -d --build

# Domain mode — Let's Encrypt
DERP_HOST=derp.example.com docker compose up -d --build
```

On first start in IP mode, derper prints a ready-to-use DERPMap node with the certificate fingerprint:

```console
$ docker compose logs
Using self-signed certificate for IP address "203.0.113.10". Configure it in DERPMap using:
  {"Name":"custom","RegionID":900,"HostName":"203.0.113.10","CertName":"sha256-raw:ab12..."}
```

## Configuration

All configuration is via environment variables (compose `environment:` or a `.env` file).

| Variable | Default | Description |
| --- | --- | --- |
| `DERP_HOST` | **required** | Public IP literal or domain. Drives cert-mode detection. |
| `DERP_CERTMODE` | `auto` | `auto` \| `manual` \| `letsencrypt`. `auto` picks from `DERP_HOST`: IP literal → `manual`, domain → `letsencrypt`. |
| `DERP_ADDR` | `:12345` / `:443` | DERP listen address, per mode. `letsencrypt` requires `:443` (autocert). |
| `DERP_HTTP_PORT` | `-1` / `80` | Plain HTTP port, per mode. `-1` disables; `letsencrypt` needs `80` for the ACME HTTP-01 challenge. |
| `DERP_CERTS` | `/app/certs` | Certificate directory (bind-mounted from `./certs`). |
| `DERP_STUN` | `true` | Run the STUN server on `3478/udp`. |
| `DERP_VERIFY_CLIENTS` | `false` | Verify clients via a local `tailscaled`. Not supported by this deployment as-is. |

### Ports

| Port | Protocol | Used by |
| --- | --- | --- |
| 12345 | tcp | DERP over TLS, manual (IP) mode |
| 443 | tcp | DERP over TLS, letsencrypt (domain) mode |
| 80 | tcp | ACME HTTP-01 challenge |
| 3478 | udp | STUN |

### Custom certificates

Mount your own certificate instead of self-signed / ACME ones by placing files in `./certs` on the host, named after the hostname:

```bash
mkdir -p certs
cp derp.example.com.crt derp.example.com.key certs/
DERP_HOST=derp.example.com DERP_CERTMODE=manual docker compose up -d
```

## Client configuration

Add the server to your tailnet DERPMap.

### IP mode

Copy the node JSON from the startup log (it already contains the `sha256-raw` fingerprint clients use to trust the self-signed certificate):

```json
{
  "Config": { "Version": 1 },
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "myderp",
      "RegionName": "My DERP",
      "Nodes": [{
        "Name": "1",
        "RegionID": 900,
        "HostName": "203.0.113.10",
        "DERPPort": 12345,
        "CertName": "sha256-raw:ab12..."
      }]
    }
  }
}
```

Apply it with `tailscale set --derp-map=derpmap.json` (or the equivalent setting in your coordination server).

### Domain mode

```json
{
  "Config": { "Version": 1 },
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "myderp",
      "RegionName": "My DERP",
      "Nodes": [{
        "Name": "1",
        "RegionID": 900,
        "HostName": "derp.example.com"
      }]
    }
  }
}
```

## How it works

- [`Dockerfile`](Dockerfile) — two stages: `go install tailscale.com/cmd/derper@latest` (cross-compiled via `TARGETARCH`), then the binary and [`derper-bootstrap.sh`](derper-bootstrap.sh) are copied onto the official Tailscale image.
- `derper-bootstrap.sh` — resolves the cert mode from `DERP_HOST` (POSIX `case`: contains `:` → IPv6 literal → `manual`; anything but digits and dots → domain → `letsencrypt`; otherwise IPv4 → `manual`), applies per-mode defaults and `exec`s derper as PID 1.
- `./certs` is bind-mounted, so the self-signed certificate (and its fingerprint) survives restarts and rebuilds.

## CI image

A [weekly workflow](.github/workflows/build.yml) rebuilds the image (everything floats on `latest`) and pushes it to `ghcr.io/peterwang-dev/ip_derper:latest` using the official Docker GitHub Actions.

To run the CI image instead of building on the host, replace `build: .` with the registry image in `docker-compose.yml`:

```yaml
    image: ghcr.io/peterwang-dev/ip_derper:latest
```

## Upgrading

Everything (Go, derper, base image) floats on `latest` and layer caching would keep stale binaries, so force a rebuild:

```bash
docker compose build --no-cache && docker compose up -d
```

## Troubleshooting

- **Clients fail with cert errors after a rebuild** — the `./certs` directory was recreated. Restore the old certificate (and keep the `sha256-raw` fingerprint in the DERPMap in sync) or update the DERPMap with the new fingerprint from the startup log.
- **Domain mode never gets a certificate** — the ACME HTTP-01 challenge needs port `80` reachable from the internet and a DNS record pointing `DERP_HOST` at this server.
- **`letsencrypt` on a non-443 port** — not possible; autocert binds `:443`. Use `manual` mode for custom ports.
- **Which mode was detected?** — check the resolved flags: `docker compose logs`.
- **DERP should not sit behind an HTTP proxy or global load balancer** — see the [derper README caveats](https://github.com/tailscale/tailscale/blob/main/cmd/derper/README.md).

## License

Upstream [yangchuansheng/ip_derper](https://github.com/yangchuansheng/ip_derper) is MIT-licensed; this repository carries no separate license file yet.
