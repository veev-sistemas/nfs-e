FROM nginx:stable-alpine
RUN apk add --no-cache ca-certificates
ENV NFSE_API_HOST=nfse-nfse-api.0piict.easypanel.host
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY dist/ /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
