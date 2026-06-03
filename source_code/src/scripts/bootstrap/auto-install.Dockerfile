FROM alpine:3.18
RUN apk add --no-cache curl bash ca-certificates
WORKDIR /scripts
COPY auto-install-http.sh /scripts/auto-install-http.sh
RUN chmod +x /scripts/auto-install-http.sh
ENTRYPOINT ["/bin/sh", "/scripts/auto-install-http.sh"]

