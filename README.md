# rddmgr

rddmgr est un environnement qui facilite l'utilisation des rdd-tools

## Pré-requis

rddmgr est développé et testé sur Debian 11. Il devrait fonctionner sur
n'importe quel système Linux, pourvu que les pré-requis soient respectés.

* Installation des [pré-requis pour Debian](documentation/prerequis-linux.md)
  et autres distributions Linux.
* Installation des [pré-requis pour WSL](documentation/prerequis-wsl.md)

## Démarrage rapide

Ouvrez un terminal et clonez le dépôt
~~~sh
git clone https://github.com/PC-Scol/rddmgr.git
~~~
~~~sh
cd rddmgr
~~~

Il faut d'abord construire les images utilisées par l'application. Commencer en
faisant une copie de `build.env` depuis `.build.env.dist`
~~~sh
cp lib/.build.env.dist lib/build.env
~~~
Il FAUT consulter `lib/build.env` et l'éditer AVANT de continuer. Notamment, les
variables suivantes doivent être configurées le cas échéant:

`APT_PROXY`
: proxy pour l'installation des paquets Debian

`APT_MIRROR`
`SEC_MIRROR`
: miroirs à utiliser. Il n'est généralement pas nécessaire de modifier ces
  valeurs

`TIMEZONE`
: Fuseau horaire, si vous n'êtes pas en France métropolitaine

`PRIVAREG`
: nom d'un registry docker interne vers lequel les images pourraient être
  poussées. Il n'est pas nécessaire de modifier ce paramètre.

Une fois le fichier configuré, les images peuvent être construites
~~~sh
./lib/sbin/build
~~~

Créer les modèles de fichiers de configuration:
~~~sh
./rddmgr --init
~~~

Les fichiers de configuration suivants sont créés avec des valeurs par défaut:

config/secrets.conf
: mots de passe traefik et pgadmin, comptes de la base pivot

config/pegase.yml
: configuration de l'établissement et des instances PEGASE.

  NB: le support de la lecture des mots de passe depuis le fichier Keepass2
  n'est pas encore implémenté. Il faut donc spécifier les mots de passe
  directement dans le fichier de configuration

config/sources.yml
: configuration des sources de données pour le déversement

config/lib-ext/
: répertoire des librairies nécessaires à l'accès aux sources de données. Copier
  le fichier `ojdbc8.jar` à cet endroit.

config/rddmgr.conf
: configurations diverses pour rddmgr

IL FAUT vérifier et renseigner ces fichiers AVANT de continuer. Ne pas oublier
de copier le fichier `ojdbc8.jar` dans le répertoire `config/lib-ext/`

Une fois la configuration mise à jour, relancer l'initialisation:
~~~sh
./rddmgr --init
~~~

On peut maintenant démarrer le frontal web et pgadmin (--start est l'option par
défaut)
~~~sh
./rddmgr
~~~

Dans la configuration par défaut, quand le frontal web est démarré, il est
accessible à l'adresse <http://localhost:7080/> avec le compte admin et le mot
de passe défini dans `config/secrets.conf`

## Création d'un atelier

Il faut maintenant créer un atelier. Il est possible d'avoir une vue d'ensemble
des options disponibles avec l'option --help
~~~sh
./rddmgr --help
~~~

Dans l'exemple suivant, on crée l'atelier pour les rdd-tools 22.0.0, et dont la
source de données est apogee:
~~~sh
./rddmgr -c 22 apogee
~~~
Les fichiers nécessaires sont téléchargés depuis l'espace partagé de PC-SCOL

L'alternative est de télécharger manuellement tous les fichiers nécessaires puis
de spécifier le répertoire qui les contient. Dans l'exemple suivant, la source
de données est APOGEE, on ne télécharge donc que le fichier init et transcos
pour APOGEE:
~~~console
$ ls path/to/dl
rdd-tools_22.0.0.tar
mypegase_22.0.0.env
rdd-tools-pivot_22.0.0.tar.gz
RDD-scripts-externes_22.0.0.zip
RDD-init-habilitations-personnes_V22.zip
RDD-init-transco-apogee_22.0.0.zip

$ ./rddmgr -c 22 path/to/dl
~~~

L'atelier `v22.wks` est créé, et la base pivot associée est démarrée. Il
faut maintenant créer un environnement.

Si on lance rddtools sans arguments:
* S'il existe des environnements et qu'aucun n'est sélectionné, le premier est
  automatiquement sélectionné
* S'il n'existe aucun environnement, un environnement est automatiquement créé
  et sélectionné

L'option -e permet de sélectionner un environnement, qui sera créé s'il n'existe
pas déjà.

L'option -c force la création d'un nouvel environnement

Dans l'exemple suivant, on crée un environnement qui sera nommé en fonction de
l'instance PEGASE cible sélectionnée:
~~~sh
cd v22.wks
~~~
~~~sh
./rddtools -c
~~~

Lors de la création de l'environnement, il faut choisir:
- l'instance PEGASE qui sera attaqué par cet environnement et dans lequel seront
  faites les injections
- la source de données qui sera utilisée pour les déversements, ainsi que le
  profil de connexion
- le nom final de l'environnement est toujours préfixé du nom de l'instance
  PEGASE.

IMPORTANT: Il est possible de créer autant d'environnements que nécessaire.
Cependant, dans cette version de rddmgr, tous les environnements d'un atelier
partagent la même base pivot. Leur intérêt se limite donc à préparer des
données à injecter à l'identique dans plusieurs instances.

## Création d'un atelier pour une version de développement

Parfois, PC-SCOL livre une version de développement à un établissement, pour
vérifier la validité d'un correctif par exemple. La particularité de ce genre de
livraison est que les version de l'image, du fichier d'environnement et de la
base pivot ne sont pas forcément les mêmes.

Par exemple, l'image de version 0.1.0-dev.894 utilise le fichier d'environnement
de la version 22.0.0

On peut créer un atelier basé sur un autre, ce qui permet de récupérer tout ce
qui ne change pas. Par exemple, la commande suivante crée un atelier pour
l'image de version 0.1.0-dev.894, tout en copiant le fichier d'environnement et
la définition de la base pivot depuis l'atelier v22.wks existant:
~~~sh
./rddmgr -c dev894 v22.wks
~~~
Le résultat est un atelier avec une image de version 0.1.0-dev.894 téléchargé
depuis l'espace partagé PC-Scol, un fichier mypegase.env de version 22.0.0 copié
depuis v22.wks et une base pivot de version 22.0.0 copié aussi depuis v22.wks

Voici un autre exemple: ici, les versions de l'image de dev et du fichier
d'environnement sont différents. Les autres fichiers sont copiés depuis
l'atelier courant existant.
~~~sh
./rddmgr -c dev911 mypegase-911.env
~~~
Dans cet exemple, on part du principe que la commande a été lancée après la
précédente. L'atelier courant est donc dev894.wks. Le résultat est un atelier
avec une image de version 0.1.0-dev.911 téléchargé depuis l'espace partagé
PC-Scol, un fichier mypegase.env de version 0.1.0-dev.911 téléchargé depuis
l'espace partagé PC-Scol et une base pivot de version 22.0.0 copié depuis
dev894.wks

Comme démontré dans l'exemple précédent, par défaut, l'atelier courant est
sélectionné comme source. L'atelier courant est, dans cet ordre:
* soit l'atelier de la dernière image de développement
* soit l'atelier de la dernière release

# Notions et architectures

## rddmgr

Une installation de rddmgr contient des services (frontal, pgAdmin), un ou
plusieurs ateliers, et des données partagées

frontal.service
: frontal web qui permet de servir tous les services de l'installation sur une
  unique adresse IP

pgadmin.service
: installation de pgAdmin en mode desktop qui permet d'accéder à toutes les
  bases pivot définies

fichiers-init-transco/
: Fichiers d'initialisation et de transcodifications, commun à tous les ateliers

scripts-externes/
: Scripts externes utilisables par rddtools, commun à tous les ateliers

backups/
: Sauvegardes de la base pivot classées par atelier

## Atelier

Un atelier est caractérisé par une version d'image de rddtools, une version de
mypegase.env et une version de la base pivot. Il est dans un répertoire de la
forme `MONATELIER.wks`

envs/
: fichier de paramètres pour les environnements

logs/
: logs d'exécution des tâches

## Environnement

Dans un atelier, un environnement est caractérisé par ses paramètres, notament
instance PEGASE qu'il attaque, source de données pour le déversement, et
paramétrages divers nécessaires au déversement et à l'injection.

IMPORTANT: à terme, chaque environnement pourra avoir sa propre base pivot. Ce
n'est pas le cas dans cette version de rddmgr.

# Exploitation

## frontal

le frontal permet d'accéder à pgAdmin ainsi qu'à des informations sur les
ateliers actuellement existants.

Dans le fichier `config/rddmgr.conf`, le paramètre `LBHOST` permet de définir le
nom d'hôte sur lequel attaquer le frontal.

Si la configuration par défaut n'est pas modifiée, l'adresse du frontal est
<http://localhost:7080/> avec le compte `admin` et le mot de passe défini dans
`config/secrets.conf`

D'autres utilisateur peuvent être rajoutés en éditant le fichier
`frontal.service/config/apache/users.ht` et en adaptant la liste des
utilisateurs autorisés dans `frontal.service/config/apache/authnz.conf`

Pour activer la connexion par CAS
* commenter `-auth_cas` dans le fichier
  `frontal.service/config/apache/setup.conf`
  ~~~sh
  ENMODS=(
      #-auth_cas
      ...
  )
  ~~~
* configurer l'adresse du serveur CAS dans le fichier
  `frontal.service/config/apache/mods-available/auth_cas.conf`
* Suivre les instructions du fichier
  `frontal.service/config/apache/authnz.conf`
  pour commenter ou supprimer la section authentification basique et décommenter
  la section authentification CAS.
  Dans ce même fichier, indiquer la liste des utilisateurs autorisés à la place
  de `<authusers...>`
* puis relancer le frontal
  ~~~sh
  ./rddmgr -r frontal
  ~~~

## pgAdmin

pgAdmin permet d'accéder aux bases de données pivot des ateliers. Le lien est
disponible sur le frontal. (Pour information, si la configuration par défaut
n'est pas modifiée, l'adresse de pgAdmin est <http://localhost:7080/pgadmin/>
avec le compte `admin` et le mot de passe défini dans `config/secrets.conf`)

A partir de là, il n'y a plus besoin de mot de passe. Si un mot de passe est
demandé, il s'agit du mot de passe de `pcscolpipvot`, mais il est plus probable
que ce soit l'hôte qui ne soit pas accessible (par exemple parce que la base
pivot n'est pas démarrée)

-*- coding: utf-8 mode: markdown -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8:noeol:binary