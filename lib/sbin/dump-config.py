#!/usr/bin/env python3
# -*- coding: utf-8 mode: python -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8

import os, sys, argparse
from os import path
from urllib.parse import urlparse

sys.path.append(path.join(path.dirname(__file__), "../python3"))
import yaml

def split_proxy(url):
    o = urlparse(url)
    return [o.hostname, o.port]

parser = argparse.ArgumentParser(
    usage="%(prog)s -s INSTANCE -d apogee|scolarix|sve|non -p PROFILE pegase.yml sources.yml [.env]",
    description="Extraire les données de pegase.yml de sources.yml",
)
parser.add_argument("pegase", nargs="?", metavar="pegase.yml", help="Fichier de configuration des instances PEGASE")
parser.add_argument("sources", nargs="?", metavar="sources.yml", help="Fichier contenant les définitions des sources de données")
parser.add_argument("envfile", nargs="?", metavar=".env", help="Fichier d'environnement contenant les mots de passe de la base pivot")
parser.add_argument("-l", "--list", action="store_const", const="list", dest="action", help="Lister les instances, sources et profils définis")
parser.add_argument("--postgres", action="store_const", const="postgres", dest="action", help="Afficher les mots de passe de la base pivot")
parser.add_argument("--local-vars", action="store_true", help="Ajouter la définition des variables locales pour les options --list et --postgres")
parser.add_argument("-m", "--fake-passwords", action="store_true", help="Générer des mots de passe bidons lors de l'export")

parser.add_argument("-s", "--instance", help="Sélectionner une instance")
parser.add_argument("-P", "--prod-instance", dest="instance", action="store_const", const="prod", help="Sélectionner l'instance PROD")
parser.add_argument("-T", "--test-instance", dest="instance", action="store_const", const="test", help="Sélectionner l'instance TEST")
parser.add_argument("-R", "--rdd-instance", dest="instance", action="store_const", const="rdd", help="Sélectionner l'instance RDD")
parser.add_argument("-L", "--pilote-instance", dest="instance", action="store_const", const="pilote", help="Sélectionner l'instance PILOTE")

parser.add_argument("-d", "--source", help="Sélectionner une source")
parser.add_argument("-A", "--apogee-source", dest="source", action="store_const", const="apogee", help="Sélectionner la source APOGEE")
parser.add_argument("-X", "--scolarix-source", dest="source", action="store_const", const="scolarix", help="Sélectionner la source SCOLARIX")
parser.add_argument("-E", "--sve-source", dest="source", action="store_const", const="sve", help="Sélectionner la source SVE")
parser.add_argument("-M", "--no-source", dest="source", action="store_const", const="none", help="Indiquer que le déversement sera manuel (il n'y a pas de source de données supportée)")

parser.add_argument("-p", "--profile", help="Sélectionner un profil de source de données")
parser.add_argument("-G", "--prod-profile", dest="profile", action="store_const", const="prod", help="Sélectionner le profil prod")
parser.add_argument("-H", "--test-profile", dest="profile", action="store_const", const="test", help="Sélectionner le profil test")
args = parser.parse_args()

if not args.pegase and not args.sources and not args.envfile:
    raise ValueError("Vous devez spécifier un des fichiers pegase.yml, sources.yml ou .env")

pdata = {}
if args.pegase:
    with open(args.pegase, "rb") as inf:
        pdata = yaml.load(inf, Loader=yaml.Loader)

sdata = {}
if args.sources:
    with open(args.sources, "rb") as inf:
        sdata = yaml.load(inf, Loader=yaml.Loader)

postgres_host = "db"
postgres_password = None
pcscolpivot_password = "password"
if args.fake_passwords:
    postgres_password = "XXX"
    pcscolpivot_password = "XXX"
elif args.envfile:
    with open(args.envfile, "r", encoding="utf-8") as inf:
        for line in inf:
            line = line.strip()
            if line.startswith("POSTGRES_HOST="):
                postgres_host = line[len("POSTGRES_HOST="):]
            elif line.startswith("POSTGRES_PASSWORD="):
                postgres_password = line[len("POSTGRES_PASSWORD="):]
            elif line.startswith("PCSCOLPIVOT_PASSWORD="):
                pcscolpivot_password = line[len("PCSCOLPIVOT_PASSWORD="):]

if args.action == "list":
    local_var = "local -a " if args.local_vars else ""
    print("%sinstances=(%s)" % (local_var, " ".join(list(pdata["instances"]))))
    print("%ssources=(%s)" % (local_var, " ".join(list(sdata))))
    for source in sdata.keys():
        print("%s%s_profiles=(%s)" % (local_var, source, " ".join(list(sdata[source]))))

elif args.action == "postgres":
    local_var = "local " if args.local_vars else ""
    print("%spostgres_host='%s'" % (local_var, postgres_host))
    print("%spostgres_password='%s'" % (local_var, postgres_password))
    print("%spcscolpivot_password='%s'" % (local_var, pcscolpivot_password))

else:
    ################################################################################
    # pegase.yml

    if pdata:
        instances = pdata.get("instances")
        if not instances: raise ValueError("Vous devez spécifier la liste des instances")

        first_instance = list(instances)[:1]
        first_instance = first_instance[0] if first_instance else None
        instance = args.instance or first_instance
        if instance not in instances:
            raise ValueError("%s: instance invalide" % instance)

        domaine = pdata.get("domaine_etab")
        if not domaine: raise ValueError("Vous devez spécifier le domaine")
        host = "%s%s.pc-scol.fr" % ("%s-" % instance if instance != "prod" else "", domaine)

        uai = pdata.get("uai_etab")
        if not uai: raise ValueError("Vous devez spécifier l'UAI de l'établissement")

        timezone = pdata.get("timezone") or "Europe/Paris"

        http_proxy = pdata.get("http_proxy") or os.getenv("HTTP_PROXY")
        https_proxy = pdata.get("https_proxy") or os.getenv("HTTPS_PROXY")
        no_proxy = pdata.get("no_proxy") or os.getenv("NO_PROXY")

        # à partir d'ici, instance est un dict
        instance = instances[instance] or {}

        urls = instance.get("urls") or {}
        authn_app = urls.get("authn-app", "https://authn-app.%s/cas/v1/tickets" % host)
        authz = urls.get("authz", "https://authz.%s" % host)
        ref = urls.get("ref", "https://ref.%s" % host)
        cof = urls.get("cof", "https://cof.%s" % host)
        mof = urls.get("mof", "https://mof.%s" % host)
        ins = urls.get("ins", "https://ins.%s" % host)
        chc = urls.get("chc", "https://chc.%s" % host)
        coc = urls.get("coc", "https://coc.%s" % host)

        if args.fake_passwords:
            svc_rdd = "XXX"
            svc_authz = "XXX"
        else:
            accounts = instance.get("accounts") or {}
            svc_rdd = accounts.get("svc-rdd") or ""
            svc_authz = accounts.get("svc-authz-admin") or ""

        print("URL_AUTHN_APP=%s" % authn_app)
        print("URL_AUTHZ=%s" % authz)
        print("URL_REF=%s" % ref)
        print("URL_COF=%s" % cof)
        print("URL_MOF=%s" % mof)
        print("URL_INS=%s" % ins)
        print("URL_CHC=%s" % chc)
        print("URL_COC=%s" % coc)
        if svc_rdd: print("PWD_SVC_RDD=%s" % svc_rdd)
        if svc_authz: print("PWD_SVC_AUTHZ=%s" % svc_authz)

        print("cnx_pivot_Server=%s" % postgres_host)
        if postgres_password: print("cnx_pivot_AdminPassword=%s" % postgres_password)
        if pcscolpivot_password: print("cnx_pivot_Password=%s" % pcscolpivot_password)

        print("uai_etablissement=%s" % uai)

        jvm_options = ["-Duser.timezone=%s" % timezone]
        if http_proxy:
            print("http_proxy=%s" % http_proxy)
            [host, port] = split_proxy(http_proxy)
            jvm_options.append("-Dhttp.proxyHost=%s -Dhttp.proxyPort=%s" % (host, port))
        if https_proxy:
            print("https_proxy=%s" % https_proxy)
            [host, port] = split_proxy(https_proxy)
            jvm_options.append("-Dhttps.proxyHost=%s -Dhttps.proxyPort=%s" % (host, port))
        if no_proxy:
            print("no_proxy=%s" % no_proxy)
            jvm_options.append("-DnonProxyHosts='%s'" % no_proxy.replace(",", "|"))
        print("jvm_option_timezone=%s" % " ".join(jvm_options))

    ################################################################################
    # sources.yml

    SOURCE_ALIASES = dict(
        apogee=("apogee", "apg", "a"),
        scolarix=("scolarix", "slx", "x"),
        sve=("sve", "e"),
        none=("vierge", "v", "none", "non", "no", "n"),
    )

    if sdata:
        source = args.source or list(sdata)[0]
        for (src, aliases) in SOURCE_ALIASES.items():
            if source in aliases:
                source = src
                break
        if source != "none":
            if source not in sdata:
                raise ValueError("%s: source invalide" % source)
            profile = args.profile or list(sdata[source])[0]
            if profile not in sdata[source]:
                raise ValueError("%s: %s: profil invalide" % (source, profile))
            c = sdata[source][profile]

            password = c["password"] if not args.fake_passwords else "XXX"
            if source == "apogee":
                print("cnx_sourceApg_Server=%s" % c["server"])
                print("cnx_sourceApg_Port=%s" % c["port"])
                print("cnx_sourceApg_Database=%s" % c["database"])
                print("cnx_sourceApg_Login=%s" % c["login"])
                print("cnx_sourceApg_Password=%s" % password)
            elif source == "scolarix":
                print("cnx_sourceSlx_Server=%s" % c["server"])
                print("cnx_sourceSlx_Port=%s" % c["port"])
                print("cnx_sourceSlx_Database=%s" % c["database"])
                print("cnx_sourceSlx_Schema=%s" % c["schema"])
                print("cnx_sourceSlx_Login=%s" % c["login"])
                print("cnx_sourceSlx_Password=%s" % password)
            elif source == "sve":
                print("cnx_sourceSve_Server=%s" % c["server"])
                print("cnx_sourceSve_Port=%s" % c["port"])
                print("cnx_sourceSve_Database=%s" % c["database"])
                print("cnx_sourceSve_Schema=%s" % c["schema"])
                print("cnx_sourceSve_Login=%s" % c["login"])
                print("cnx_sourceSve_Password=%s" % password)
            else:
                raise ValueError("%s: source non supportée" % source)
