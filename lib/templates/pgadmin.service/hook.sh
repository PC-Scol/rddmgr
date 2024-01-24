#!/bin/sh
# -*- coding: utf-8 mode: sh -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8

sudo /rootfix.sh
if [ -f /var/lib/pgadmin/pgadmin4.db ]; then
    # Mettre à jour la liste des serveurs au démarrage
    /venv/bin/python /pgadmin4/setup.py load-servers /pgadmin4/servers.json --replace
fi
exec /entrypoint.sh "$@"
