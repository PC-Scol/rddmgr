## Version 0.6.2 du 29/02/2024-18:17

* `2a92315` édition: mettre les variables supplémentaires au début

## Version 0.6.1 du 29/02/2024-15:28

* `7a8f3f0` maj doc

## Version 0.6.0 du 28/02/2024-17:51

* `0d3b59e` Intégration de la branche wip/vn
  * `8cb5fc7` maj doc
  * `b276963` sélection automatique de l'atelier courant comme source
  * `26f5e90` améliorer la découverte de fichiers locaux
  * `a380d58` support de la convention de nommage mypegase-MMM.env

## Version 0.5.1 du 19/02/2024-15:48

* `176089b` correction de l'édition des paramètres
* `23d4e40` identifier dernière release et dernière image de dev
* `5205c38` maj doc

## Version 0.5.0 du 16/02/2024-17:28

* `77d74c4` Intégration de la branche wip/misc
  * `ebd2547` améliorer l'édition du fichier d'environnement
  * `34b2f36` documenter la nécessité de python 3
  * `582b9c4` ajout des prérequis dans la documentation
  * `0aa38f2` vérification des pré-requis
  * `039c504` FICHIERS_INIT_TRANSCO et SCRIPTS_EXTERNES sont maintenant configurables

## Version 0.4.3 du 14/02/2024-10:39

* `1e485ec` maj version pgAdmin

## Version 0.4.2 du 14/02/2024-07:59

* `529bd95` regen-secrets: initialiser le générateur aléatoire

## Version 0.4.1 du 30/01/2024-00:26

* `068f746` Intégration de la branche wip/misc
  * `62b1651` provision contre l'initialisation incomplète d'un atelier
  * `6659780` curl: max 10 tentatives en cas d'erreur 18
  * `2a6c541` curl: tenter de continuer le téléchargement en cas de code erreur 18
  * `b68e447` afficher le statut de la base pivot dans la liste des ateliers
  * `d27260e` corriger l'affichage de SHARED_URL
  * `26a654b` stop_pivotbdd uniquement si le fichier existe
* `0640967` curl: retry, continue, progress bar

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
