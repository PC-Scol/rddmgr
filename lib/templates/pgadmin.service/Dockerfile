# -*- coding: utf-8 mode: dockerfile -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8
FROM dpage/pgadmin4:8.2

ENV PGADMIN_DISABLE_POSTFIX=1
ENV PGADMIN_CONFIG_SERVER_MODE="False"
ENV PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED="False"
ENV PGADMIN_CONFIG_ENABLE_PSQL="True"
ENV PGADMIN_DEFAULT_EMAIL=pgadmin4@pgadmin.org
ENV PGADMIN_DEFAULT_PASSWORD=pgadmin4

COPY hook.sh rootfix.sh /
COPY sudoers /etc/sudoers.d/rootfix
ENTRYPOINT ["/hook.sh"]
