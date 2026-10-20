FROM ubuntu:26.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgcc-s1 libpq5 zlib1g curl libxml2-dev libxslt1-dev openssl-provider-legacy python3 python3-cryptography python3-reportlab fonts-liberation \
    && ln -s /usr/lib/x86_64-linux-gnu/libpq.so.5 /usr/lib/x86_64-linux-gnu/libpq.so \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY NfseBackend /app/NfseBackend
RUN chmod 755 /app/NfseBackend
COPY schemas /app/schemas
COPY openssl-pfx.cnf /app/openssl-pfx.cnf
COPY download-danfse.sh /app/download-danfse.sh
COPY render-danfse.py /app/render-danfse.py
COPY manage-certificate.py /app/manage-certificate.py
COPY danfse-assets /app/danfse-assets
RUN mkdir -p /var/lib/nfse/certificados /run/nfse-certificates \
    && chown -R 10001:10001 /var/lib/nfse \
    && chmod 700 /var/lib/nfse /var/lib/nfse/certificados
USER 10001:10001
ENV NFSE_BIND=0.0.0.0 NFSE_PORT=9000
ENV NFSE_ENABLE_HOMOLOGATION=0 NFSE_SCHEMAS_DIR=/app/schemas NFSE_DATA_DIR=/var/lib/nfse NFSE_CERTIFICATES_DIR=/var/lib/nfse/certificados
ENV OPENSSL_CONF=/app/openssl-pfx.cnf OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules
EXPOSE 9000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl --fail --silent http://127.0.0.1:9000/health || exit 1
ENTRYPOINT ["/bin/bash", "-c", "umask 077; exec /app/NfseBackend"]
