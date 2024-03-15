XXX Cette documentation est obsolète depuis la version `0.8.0`.
Elle sera mise à jour dès que possible

# Documentation technique

Cette documentation détaille le fonctionnement de rddmgr

## Gestion des services et des ateliers

Les services et les ateliers sont gérés par le script rddmgr situé à la racine

Une aide succinte est disponible avec l'option --help
~~~sh
./rddmgr --help
~~~

### lib/sbin/bootstrap

A chaque lancement de rddmgr, le script `lib/sbin/bootstrap` est invoqué pour
vérifier s'il ne faut pas installer les librairies PHP nécessaires

Ce script vérifie si les librairies sont installées et à jour dans `lib/vendor`
et le cas échéant, lance `lib/sbin/composer.phar i` pour télécharger et
installer les librairies.

Le script `lib/sbin/rundk` est utilisé pour wrapper ces invocations dans un
container qui contient une installation de PHP avec les librairies nécessaires.

Au 11/01/2024, le container créé par rundk l'est à partir de l'image docker
publique `pubdocker.univ-reunion.fr/image/php:d11` qui est une Debian 11 avec
PHP 7.4

Quand/si l'image rdd-tools passera à Debian 12, l'image ci-dessous sera mise à
jour en fonction

### lib/sbin/rundk

rundk lance un script dans un container où sont copiés les informations de
l'utilisateur courant des fichiers `/etc/passwd` et `/etc/group` de l'hôte. De
plus, le répertoire `$HOME` est automatiquement monté dans le container.

De cette façon, le script peut tourner dans les mêmes conditions que s'il était
lancé directement, mais l'utilisation du container permet de s'assurer que les
outils nécessaires sont présents (la bonne version de PHP notamment)

### rddmgr --init

L'utilisateur doit lancer rddmgr avec l'option --init au moins deux fois lors de
l'installation initiale:

la première fois, le répertoire `config` est créé et les fichiers suivants y
sont copiés:
* `lib/templates/config/pegase.yml` contient un modèle de paramétrage des
  instances PEGASE qui peuvent être attaquées par la RDD
* `lib/templates/config/source.yml` contient un modèle de paramétrage des
  sources de données à partir desquelles sont faites le déversement.
* `lib/templates/secrets.conf` contient les mots de passe de traefik et pgAdmin,
  ainsi que les mots de passe des utilisateurs `pcscol` et `pcscolpivot` pour la
  création de la base pivot. ce fichier est copié avec `lib/sbin/regen-secrets`
  qui y remplace toutes les occurrences de la chaine `XXXRANDOMXXX` par une
  chaine au hasard

de plus, `lib/rddmgr.conf` contient la configuration *par défaut* de rddmgr. une
copie de ce fichier est faite dans le répertoire `config` en commentant toutes
les valeurs. cele sert donc de documentation des valeurs par défaut pour
l'utilisateur, et cela lui permet aussi de voir d'un seul coup d'oeil ce qui a
été changé par rapport aux valeurs par défaut.

L'utilisateur doit examiner et modifier le cas échéant la configuration avant de
lancer rddmgr --init une deuxième fois.
* Les réseaux docker `$DBNET` et `$LBNET` configurés dans rddmgr.conf sont créés
* Le répertoire `lib/templates/traefik.service` est copié, et les variables
  définies dans rddmgr.conf et secrets.conf sont interpolées dans ses fichiers.
* Le répertoire `lib/templates/pgadmin.service` est copié, et les variables
  définies dans `rddmgr.conf` et `secrets.conf` sont interpolées dans ses
  fichiers.

l'interpolation des variables se fait en remplaçant toutes les occurrences de
`@@VARIABLE@@` par la valeur correspondante `$VARIABLE`

ATTENTION: Les modifications éventuelles faites dans les répertoires
`traefik.service` et `pgadmin.service` sont susceptible d'être écrasées si
rddmgr est relancé avec l'option --init

### traefik.service

Ce redirecteur web sert à donner accès à tous les services web sur la même
adresse IP. Il faut cependant créer les noms DNS correspondant aux services.

Si rddmgr est déployé sur une machine distante et doit être utilisé par
plusieurs personnes, la mise à jour de la zone DNS de l'organisme est
nécessaire. Si rddmgr.conf contient `LBHOST=myhost.domain.tld`, il s'agit
d'ajouter deux entrées de la forme
~~~
; cet exemple est dans une zone d'origine domain.tld
myhost   IN A     x.y.z.t
*.myhost IN CNAME myhost
~~~
`x.y.z.t` est l'adresse IP de la machine hébergeant rddmgr.
dans les conditions de cet exemple, et avec la configuration par défaut
* la console traefik est accessible à l'adresse http://traefik.myhost.domain.tld:7080
* pgAdmin est à l'adresse http://pgadmin.myhost.domain.tld:7080

Si rddmgr est lancé sur la machine locale, on peut se contenter de mettre à jour
/etc/hosts avec des entrées de la forme
~~~
127.0.2.1 traefik.localhost pgadmin.localhost
~~~
L'inconvénient de cette méthode est qu'il faut manuellement rajouter le nom pour
chaque service et chaque atelier, mais au 11/01/2024, ce n'est pas un problème
puisque les seuls services sont traefik et pgadmin, et que rddweb n'est pas
implémenté

A terme, les instances rddweb de chaque atelier seront accessibles
automatiquement grâce à traefik, pourvu bien entendu que le nom puisse être
résolu via le DNS ou `/etc/hosts`. pour reprendre l'exemple ci-dessus, si
l'atelier s'appelle MONATELIER.wks, l'instance rddweb sera accessible à
l'adresse http://MONATELIER.myhost.domain.tld:7080

Les configurations nécessaire pour l'accès en https sont présentes, mais elles
ne seront pleinement testées et documentées que lorsque rddweb sera disponible.

### pgadmin.service

ce service est une instance de pgAdmin en mode "desktop"

à chaque création d'atelier, le script `lib/sbin/update-pgadmin` est lancé:
* le fichier `pgadmin.service/private/servers.json` est mis à jour avec la liste
  des ateliers
* un ordre est envoyé à pgAdmin pour recharger la liste des serveurs.

### rddmgr.conf

Les variables suivantes sont utilisées pour configurer les services et les
ateliers, via l'interpolation des variables dans les fichiers:
* `LBNET`: nom du réseau docker dans lequel tournent traefik et les instances de
  rddweb
* `DBNET`: nom du réseau docker dans lequel tournent les instances de la base
  pivot.
* `LBVIP`: adresse d'écoute des services web. une valeur vide indique qu'il faut
  écouter sur toutes les interfaces, et dans ce cas les services web (pgAdmin et
  les instances de rddweb) sont accessibles depuis toutes les machines du réseau
* `DBVIP`, `PGSQL_PORT`: adresse d'écoute et port des serveurs postgresql pour
  l'accès direct aux bases pivot (ce qui peut être nécessaire dans certains
  cas). la valeur par défaut est 127.0.0.1 c'est à dire qu'ils ne sont
  accessibles que depuis la machine locale.

  dans la configuration par défaut, si le port d'écoute n'est pas modifié, il
  est possible de rendre accessible en direct une seule base pivot à la fois, en
  modifiant le fichier rddtools.docker-compose.yml dans le répertoire d'atelier

  A terme ce paramètre sera utilisé pour donner accès à une instance de
  pgBouncer qui permettra d'accéder à toutes les bases pivot
* `LBHOST`, `HTTP_PORT`, `HTTPS_PORT`: nom d'hôte du frontal web, et ports
  d'écoute
* `PGADMIN_LBHOST`, `TRAEFIK_LBHOST`: noms d'hôtes pour accéder à pgAdmin et à
  la console traefik. ces valeurs sont par défaut construites à partir de
  `$LBHOST`
* `USE_HTTPS`: activer l'écoute en https. les détails de la façon d'installer
  les certificats seront fournis lors de la livraison de rddweb
* `USE_LETSENC`: utiliser let's encrypt pour la génération des certificats. cela
  nécessite que le serveur soit accessible depuis internet. (n'activer que si on
  sait ce qu'on fait)
* `SHARED_URL`: URL de l'espace partagé PC-SCOL depuis lequel sont téléchargés
  les images, les fichiers d'environnements, etc.

### rddmgr --create

La création d'un atelier permet de mettre en place l'environnement nécessaire
pour utiliser une certaine version de rdd-tools

La création se fait en spécifiant une version et éventuellement un répertoire
source. si nécessaire, les fichiers correspondant à la version spécifiée sont
téléchargés depuis l'espace partagé. si la source est un atelier existant,
les environnements sont copiés aussi.

Les fichiers sources sont traités différemment selon leur nature:
* `rdd-tools_*.tar`: l'image est importée avec `docker load`
* `mypegase_*.env`: le fichier est copié dans le répertoire `init` de l'atelier
* `rdd-tools-pivot_*.tar.gz`: l'archive est décompressée dans le répertoire
  `init` de l'atelier
* `RDD-scripts-externes_*.zip`: l'archive est décompressée dans le répertoire
  `scripts-externes` à la racine de rddmgr, si ce répertoire n'existe pas
  déjà. si le répertoire existe déjà, et qu'une nouvelle version de ce fichier
  est livrée, il faudra faire l'intégration manuellement.
* `RDD-init-transco-*.zip` et `RDD-init-habilitations-personnes_*.zip`: ces
  archives sont décompressées dans le répertoire `fichiers-init-transco` à la
  racine de rddmgr, si ce répertoire n'existe pas déjà. si le répertoire existe
  déjà, et qu'une nouvelle version de ces fichiers est livrée, il faudra faire
  l'intégration manuellement.

les répertoires `scripts-externes` et `fichiers-init-transco` sont donc partagés
par tous les ateliers. si le besoin est exprimé, il est possible assez
facilement de modifier rddmgr pour que ces répertoires puissent si nécessaire
être locaux aux ateliers, mais dans le cadre de la RDD pour *un* établissement,
l'intérêt est limité.

Lors de la création d'un atelier, le répertoire `lib/templates/workshop` est
copié, et l'interpolation des variables de `rddmgr.conf` et `secrets.conf` est
effectuée dans les fichiers.

Notamment, dans le répertoire d'atelier:
* le fichier `.env` est mis à jour avec différentes informations comme la
  version de l'image, du fichier d'environnement et de la base pivot. il
  contient aussi les mots de passe pour l'accès à la base pivot.
* le script `init/rdd-tools-pivot_VERSION/scripts/000_user.sql` est modifié pour
  intégrer le mot de passe `$PCSCOLPIVOT_PASSWORD` défini dans `secrets.conf`

Ensuite la base pivot est démarrée. Elle est configurée pour démarrer
automatiquement au démarrage de la machine, sauf si elle est arrêtée
explicitement.

Enfin la mise à jour de la liste des ateliers est faite avec le script
`lib/sbin/update-pgadmin` afin que pgAdmin puisse accéder à la nouvelle base
pivot.

## Exploitation d'un atelier de RDD

Dans un atelier, le script rddtools permet de lancer les commandes pour faire la
RDD dans l'environnement configuré. Chaque atelier est indépendant des autres,
et ils peuvent être utilisés en parallèle.

Le script est conçu pour utiliser rdd-tools de la façon la plus transparente
possible. Cependant, il a certaines options spécifique. Il est possible
d'afficher ces options spécifiques avec l'option --help
~~~sh
./rddtools --help
~~~

Un environnement peut être créé avec l'option --create, ou sélectionné avec
l'option --env

Un environnement sélectionné devient l'environnement par défaut: il n'est donc
pas nécessaire de spécifier l'environnement à chaque invocation du script

Le répertoire d'atelier `init` contient le fichier mypegase.env ainsi que les
scripts de création de la base pivot.

Le répertoire d'atelier `envs` contient les fichiers d'environnement. Soit un
environnement nommé "myenv":
* le fichier `envs/myenv.env` contient les paramètres utilisateurs, et est prévu
  pour être consulté et modifié par l'utilisateur.

  ce fichier contient notamment le nom de l'instance PEGASE attaquée (Prod,
  Test, RDD, etc.) ainsi que le profil de connexion à la source de données
* le fichier `envs/.myenv.env` contient les paramètres de connexion à l'instance
  PEGASE, à la base pivot, et à la source de données. ce fichier est généré
  automatiquement, et n'est pas censé être modifié par l'utilisateur.

  ce fichier est généré par le script `lib/sbin/env_dump-config.py` à partir de
  `config/pegase.yml` et `config/source.yml` dans la racine de rddmgr et `.env`
  dans le répertoire d'atelier.

  `lib/sbin/env_dump-config.py` supporte aussi une option où le fichier
  `.myenv.env` est généré avec des mots de passe bidons, afin qu'il puisse être
  inclus dans une sauvegarde ou pour transmission à PC-SCOL pour débug

Quand rdd-tools est lancé:
* les 3 fichiers d'environnement `init/mypegase.env`, `envs/.myenv.env` et
  `envs/myenv.env` sont chargés dans cet ordre
* si l'option --debug est utilisée, la valeur du paramètre `debug_job` est
  forcée à `O`
* les répertoires `fichiers-init-transco`, `scripts-externes`, `backups` et
  `config/lib-ext` à la racine de rddmgr sont montés respectivement sur
  `/files`, `/files/scripts-externes`, `/files/backup` et `/lib-ext`
* le répertoire `logs/<YYYmmdd>T<HHMMSS>` est monté sur `/logs`. De cette façon,
  tous les logs de l'invocation courante sont dans un répertoire daté. Il est
  donc plus facile de les récupérer si nécessaire.

-*- coding: utf-8 mode: markdown -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8:noeol:binary