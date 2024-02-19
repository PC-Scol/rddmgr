#!/usr/bin/env python3
# -*- coding: utf-8 mode: python -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8

import os, sys, re, tempfile, argparse
from os import path

parser = argparse.ArgumentParser(
    usage="%(prog)s mypegase.env system.env user.env [tmpfile]",
    description="Aide à l'édition d'un fichier mypegase.env",
)
parser.add_argument("mypegase", nargs=1, metavar="mypegase.env", help="fichier de base mypegase.env")
parser.add_argument("system", nargs=1, metavar="system.env", help="fichier des paramètres système")
parser.add_argument("user", nargs=1, metavar="user.env", help="fichier des paramètres utilisateurs")
parser.add_argument("tmpfile", nargs="?", metavar="tmpfile", help="fichier temporaire vers lequel exporter ou depuis lequel importer")
parser.add_argument("-x", "--export", action="store_const", const="export", dest="action", help="Exporter les paramètres, pour édition par l'utilisateur")
parser.add_argument("-m", "--import", action="store_const", const="import", dest="action", help="Importer les paramètres après édition par l'utilisateur")
args = parser.parse_args()

mypegase_rows = []
mypegase_params = {}
with open(args.mypegase[0], "rt", encoding="utf-8") as inf:
    for line in inf.readlines():
        line = line.rstrip("\n")
        name = value = None
        mo = re.match(r'([a-zA-Z_][a-zA-Z0-9_]*)=(.*)', line)
        if mo is not None:
            name = mo.group(1)
            value = mo.group(2)
        mypegase_rows.append(dict(line=line, name=name, value=value))
        if name is not None: mypegase_params[name] = value

system_params = {}
with open(args.system[0], "rt", encoding="utf-8") as inf:
    for line in inf.readlines():
        line = line.rstrip("\n")
        name = value = None
        mo = re.match(r'([a-zA-Z_]+)=(.*)', line)
        if mo is not None:
            name = mo.group(1)
            value = mo.group(2)
        if name is not None: system_params[name] = value

user_rows = []
user_params = {}
with open(args.user[0], "rt", encoding="utf-8") as inf:
    for line in inf.readlines():
        line = line.rstrip("\n")
        name = value = None
        mo = re.match(r'([a-zA-Z_]+)=(.*)', line)
        if mo is not None:
            name = mo.group(1)
            value = mo.group(2)
        user_rows.append(dict(line=line, name=name, value=value))
        if name is None: pass
        elif name.startswith("_rddtools_"): pass
        else: user_params[name] = value

action = args.action or 'export'

if action == 'export':
    if args.tmpfile is None: outf = sys.stdout
    else: outf = open(args.tmpfile, "wt", encoding="utf-8")
    written_vars = {}
    for row in mypegase_rows:
        name = row["name"]
        if name is None:
            outf.write("%s\n" % row["line"])
        elif name in system_params:
            value = system_params[name]
            # masquer les mots de passe
            if name.startswith("PWD_"): value = "XXX"
            elif re.search(r'password', name, re.I) is not None: value = "XXX"
            outf.write("#%s=%s ### PARAMETRE NON MODIFIABLE\n" % (name, value))
            written_vars[name] = True
        else:
            value = user_params[name] if name in user_params else row["value"]
            outf.write("%s=%s\n" % (name, value))
            written_vars[name] = True
    # Variables supplémentaires
    first = True
    for (name, value) in user_params.items():
        if name in written_vars: continue
        if first:
            first = False
            outf.write("""
# ------------------------------------------------------------------------------
# Ces paramètres sont dans votre fichier d'environnements mais ne figurent pas
# ou plus dans mypegase.env
# Vérifiez que vous n'avez pas fait une erreur ou manqué une mise à jour!
""")
        outf.write("%s=%s\n" % (name, value))
            
elif action == 'import':
    if args.tmpfile is None:
        raise ValueError("Le fichier en entrée est requis")
    input_params = {}
    with open(args.tmpfile, "rt", encoding="utf-8") as inf:
        for line in inf.readlines():
            line = line.rstrip("\n")
            name = value = None
            mo = re.match(r'([a-zA-Z_]+)=(.*)', line)
            if mo is not None:
                name = mo.group(1)
                value = mo.group(2)
            if name is not None: input_params[name] = value
    read_vars = {}
    with tempfile.TemporaryFile("w+t", encoding="utf-8") as tmpf:
        for row in user_rows:
            name = row["name"]
            if name is None:
                tmpf.write("%s\n" % row["line"])
            elif name.startswith("_rddtools_"):
                tmpf.write("%s=%s\n" % (name, row["value"]))
            elif name in system_params:
                # ne pas permettre de modifier un paramètre système
                pass
            elif name in input_params:
                if name in mypegase_params:
                    if input_params[name] != mypegase_params[name]:
                        # n'écrire que si la valeur a changé
                        tmpf.write("%s=%s\n" % (name, input_params[name]))
                else:
                    # écrire la valeur telle quelle
                    tmpf.write("%s=%s\n" % (name, row["value"]))
                read_vars[name] = True
            else:
                # variable qui n'est plus dans le fichier temporaire. la
                # supprimer
                pass
        # ensuite, écrire toutes les nouvelles valeurs
        for (name, value) in input_params.items():
            if name in read_vars: continue
            if name in mypegase_params:
                if input_params[name] != mypegase_params[name]:
                    # n'écrire que si la valeur a changé
                    tmpf.write("%s=%s\n" % (name, input_params[name]))
            else:
                # écrire la valeur telle quelle
                tmpf.write("%s=%s\n" % (name, value))
        # enfin, écraser le fichier original
        tmpf.seek(0)
        with open(args.user[0], "wt", encoding="utf-8") as outf:
            outf.write(tmpf.read())

else:
    raise ValueError("%s: action invalide" % action)
