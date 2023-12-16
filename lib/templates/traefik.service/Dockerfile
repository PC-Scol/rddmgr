# -*- coding: utf-8 mode: dockerfile -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8
FROM traefik:v2.10

COPY config/traefik.toml /etc/traefik/traefik.toml
COPY config/common.toml /etc/traefik/dynamic/
COPY config/routes.toml /etc/traefik/dynamic/
COPY config/certs/ /certs/
COPY config/certs.toml /etc/traefik/dynamic/
