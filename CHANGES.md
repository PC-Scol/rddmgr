## Version 0.4.0 du 24/01/2024-23:53

* `19e8f05` Intégration de la branche wip/misc
  * `0f6d87a` rddtools: création, duplication, suppression d'environnement
  * `cae49d7` maj doc
  * `3a29244` rddmgr: après --init, suggérer --start
  * `cdbdb92` si recreate, redémarrer la base pivot
  * `be54fbd` si reinit, redémarrer traefik et/ou pgadmin
  * `edbcd90` créer backups et wksdir/logs dès l'initialisation
  * `4f95de9` wks: placer le lien vers l'environnement courant dans envs/
  * `c1bcde9` rddmgr -k arrête par défaut les services de TOUS les ateliers
  * `433952f` fix: les urls des instances doivent être en minuscule
  * `39d379f` wks: laisser la création éventuelle de config/ à l'utilisateur
* `05a0043` renommer dump-config.py en env_dump-config.py

## Version 0.3.0 du 12/01/2024-18:23

* `49a0f3f` Intégration de la branche wip/techdoc
  * `dd15fff` ajouter la documentatio technique
  * `654d041` renommer espace de rdd en atelier
* `c3dd2b4` améliorer les messages lors de la création d'un environnement

## Version 0.2.0 du 09/01/2024-00:58

* `df41343` améliorer le support des versions sources
* `f085f8a` améliorer les messages
* `c22d36e` support de préfixes pour spécifier le type d'argument
* `c2ff472` si composer.lock est mis à jour, forcer bootstrap
* `7d1c2f1` maj doc
* `744d75c` améliorer le processus de création: un environnement est préfixé du nom de l'instance
* `5479da8` modifs.mineures sans commentaires

## Version 0.1.0 du 16/12/2023-10:35

* `c36e53e` frontend simple pour rddtools
