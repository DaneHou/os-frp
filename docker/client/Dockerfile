FROM alpine:3.19

ARG FRP_VERSION=0.67.0
ARG HYSTERIA2_VERSION=2.5.1
ARG SHADOW_TLS_VERSION=0.2.25
ARG TARGETARCH

# Install dependencies
RUN apk add --no-cache \
    curl \
    jq \
    iproute2 \
    ca-certificates \
    && mkdir -p /usr/local/bin /etc/frp /etc/hysteria2 /var/lib/frp /var/log/frp /scripts

# Download FRP client
RUN curl -fSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${TARGETARCH}.tar.gz" \
    -o /tmp/frp.tar.gz \
    && tar -xzf /tmp/frp.tar.gz -C /tmp \
    && cp /tmp/frp_${FRP_VERSION}_linux_${TARGETARCH}/frpc /usr/local/bin/frpc \
    && chmod +x /usr/local/bin/frpc \
    && rm -rf /tmp/frp*

# Download Hysteria2
RUN curl -fSL "https://github.com/apernet/hysteria/releases/download/app%2Fv${HYSTERIA2_VERSION}/hysteria-linux-${TARGETARCH}" \
    -o /usr/local/bin/hysteria2 \
    && chmod +x /usr/local/bin/hysteria2 \
    || echo "WARN: Hysteria2 download failed, feature will be unavailable"

# Download shadow-tls (map TARGETARCH to shadow-tls naming)
RUN STLS_ARCH=$(case "${TARGETARCH}" in arm64) echo "aarch64";; *) echo "x86_64";; esac) \
    && curl -fSL "https://github.com/ihciah/shadow-tls/releases/download/v${SHADOW_TLS_VERSION}/shadow-tls-${STLS_ARCH}-unknown-linux-musl" \
    -o /usr/local/bin/shadow-tls \
    && chmod +x /usr/local/bin/shadow-tls \
    || echo "WARN: shadow-tls download failed, feature will be unavailable"

# Copy shared scripts
COPY shared/entrypoint.sh /scripts/entrypoint.sh
COPY shared/scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENV FRP_MODE=client

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD /scripts/healthcheck.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
