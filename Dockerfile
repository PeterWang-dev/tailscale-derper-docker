FROM golang:latest AS builder

# official distribution path per cmd/derper/README.md
ARG TARGETARCH
RUN CGO_ENABLED=0 GOARCH=$TARGETARCH GOBIN=/out go install tailscale.com/cmd/derper@latest

FROM ghcr.io/tailscale/tailscale:latest

COPY --from=builder /out/derper /usr/local/bin/derper
COPY --chmod=0755 derper-bootstrap.sh /usr/local/bin/derper-bootstrap.sh

ENTRYPOINT ["/usr/local/bin/derper-bootstrap.sh"]
