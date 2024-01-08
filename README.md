# rddmgr

rddmgr est un environnement qui facilite l'utilisation des rdd-tools

## Démarrage rapide

Créer les modèles de fichiers de configuration:
~~~sh
./rddmgr --init
~~~

Les fichiers de configuration suivants sont créés avec des valeurs par défaut:

config/secrets.conf
: mots de passe traefik, pgadmin, comptes de la base pivot

config/pegase.yml
: configuration de l'établissement et des instances PEGASE

config/sources.yml
: configuration des sources de données pour le déversement

config/lib-ext/
: répertoire des librairies nécessaires à l'accès aux sources de données. Copier
  le fichier `ojdbc8.jar` à cet endroit.

config/rddmgr.conf
: configurations diverses pour rddmgr

IL FAUT vérifier et renseigner ces fichiers AVANT de continuer. Ne pas oublier
de copier le fichier `ojdbc8.jar` dans le répertoire config/lib-ext/

Une fois la configuration mise à jour, relancer l'initialisation:
~~~sh
./rddmgr --init
~~~

On peut maintenant démarrer traefik et pgadmin
~~~sh
./rddmgr
~~~

## Création d'un espace de travail

Il faut maintenant créer un espace de travail.

Dans l'exemple suivant, on crée l'espace de travail pour les rdd-tools 22.0.0:
~~~sh
./rddmgr -c 22
~~~
Les fichiers nécessaires sont téléchargés depuis l'espace partagé de PC-SCOL

L'alternative est de télécharger manuellement tous les fichiers nécessaires puis
de spécifier le répertoire qui les contient. Dans l'exemple suivant, la source
de données est APOGEE, on ne télécharge donc que le fichier init et transcos
pour APOGEE:
~~~sh
$ ls path/to/dl
rdd-tools_22.0.0.tar
mypegase_22.0.0.env
rdd-tools-pivot_22.0.0.tar.gz
RDD-scripts-externes_22.0.0.zip
RDD-init-habilitations-personnes_V22.zip
RDD-init-transco-apogee_22.0.0.zip

$ ./rddmgr -c 22 path/to/dl
~~~

L'espace de travail `v22.works` est créé, et la base pivot associée est
démarrée. Il faut maintenant créer un environnement.

Lancer rddtools sans argument crée un environnement par défaut s'il n'en existe
pas déjà un. L'option -c force la création d'un nouvel environnement.
L'option -e permet de sélectionner un environnement, qui sera créé s'il n'existe
pas déjà. Dans cet exemple, on crée un environnement nommé 'rdd':
~~~sh
cd v22.works

./rddtools -e rdd
~~~

Lors de la création de l'environnement, il faut choisir:
- l'instance PEGASE qui sera attaqué par cet environnement et dans lequel seront
  faites les injections
- la source de données qui sera utilisée pour les déversements, ainsi que le
  profil de connexion
- le nom final de l'environnement est toujours préfixé du nom de l'instance
  pegase.

IMPORTANT: Il est possible de créer autant d'environnements que nécessaire.
Cependant, dans cette version de rddmgr, tous les environnements partagent la
même base pivot.  Leur intérêt se limite donc à préparer des données à injecter
à l'identique dans plusieurs instances.

## Création d'un espace de travail pour une version de développement

Parfois, PC-SCOL livre une version de développement à un établissement, pour
vérifier la validité d'un correctif par exemple. La particularité de ce genre de
livraison est que les version de l'image, du fichier d'environnement et de la
base pivot ne sont pas forcément les mêmes.

Par exemple, l'image de version 0.1.0-dev.894 utilise un fichier d'environnement
de la version 22.0.0

On peut créer un espace de travail basé sur un autre, ce qui permet de récupérer
tout ce qui ne change pas. Par exemple, la commande suivante crée un espace de
travail pour l'image de version 0.1.0-dev.894, tout en copiant le fichier
d'environnement et la définition de la base pivot depuis l'espace de travail
v22.works existant:
~~~sh
./rddmgr -c dev894 v22.works
~~~

Dans l'exemple suivant, les versions de l'image et du fichier d'environnement
sont différents. Dans ce cas, il est nécessaire de spécifier chacun des
fichiers en plus de la source le cas échéant:
~~~sh
./rddmgr -c rdd-tools_0.1.0-dev.875.tar mypegase_0.1.0-dev.870.env v22.works
~~~

# Notions et architectures

## rddmgr

Une installation de rddmgr contient des services (traefik, pgAdmin), un ou
plusieurs espaces de travail, et des données partagées

traefik.service
: frontal web qui permet de servir tous les services de l'installation sur une
  unique adresse IP

pgAdmin.service
: installation de pgAdmin en mode desktop qui permet d'accéder à toutes les
  bases pivot définies

fichiers-transco/
: Fichiers d'initialisation et de transcodifications, commun à tous les espaces
  de travail

scripts-externes/
: Scripts externes utilisables par rddtools, commun à tous les espaces de
  travail

backups/
: Sauvegardes de la base pivot classées par espace de travail

## Espace de travail

Un espace de travail est caractérisé par une version d'image de rddtools, une
version de mypegase.env et une version de la base pivot. Il est dans un
répertoire de la forme `MON-ESPACE.works`

envs/
: fichier de paramètres pour les environnements

logs/
: logs d'exécution des tâches

## Environnement

Dans un espace de travail, un environnement est caractérisé par ses paramètres,
notament instance PEGASE qu'il attaque, source de données pour le déversement,
et paramétrages divers nécessaires au déversement et à l'injection.

IMPORTANT: à terme, chaque environnement pourra avoir sa propre base pivot. Ce
n'est pas le cas dans cette version de rddmgr.

# Exploitation

## pgAdmin

pgAdmin est lancé par défaut par rddmgr. Il permet d'accéder aux bases de
données pivot des espaces de travail.

Dans le fichier config/rddmgr.conf, le paramètre `PGADMIN_LBHOST` permet de
définir le nom d'hôte sur lequel attaquer pgAdmin. Bien entendu, il faut que ce
nom existe au niveau du DNS et doit pointer sur l'adresse IP `LBVIP`

Si la configuration par défaut n'est pas modifiée, pgAdmin doit être attaqué à
l'adresse `pgadmin.localhost` sur le port `7080`. Il est possible de modifier
le fichier /etc/hosts pour faire un test rapidement:
~~~sh
cat <<EOF | sudo tee -a /etc/hosts
127.0.2.1 traefik.localhost pgadmin.localhost
EOF
~~~

Ensuite, se connecter sur <http://pgadmin.localhost:7080> avec le compte
`pgadmin` et le mot de passe défini dans config/secrets.conf

A partir de là, il n'y a plus besoin de mot de passe. Si un mot de passe est
demandé, il s'agit du mot de passe de `pcscolpipvot`, mais il est plus probable
que ce soit l'hôte qui ne soit pas accessible (par exemple parce que la base
pivot n'est pas démarrée)

-*- coding: utf-8 mode: markdown -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8:noeol:binary