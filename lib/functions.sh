# -*- coding: utf-8 mode: sh -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8
# Fonctions de support pour rddmgr

SHARED_URL=https://share.pc-scol.fr/d/614ecc4ab7e845429c08
RDDTOOLS_IMAGE=docker.pc-scol.fr/pcscol/rdd-tools
FICHIERS_INIT_TRANSCO=fichiers-init-transco
SCRIPTS_EXTERNES=scripts-externes
BACKUPS=backups
: "${EDITOR:=nano}"

inspath "$RDDMGR/lib/sbin"

################################################################################
# fonctions communes
################################################################################

function load_config() {
    local config="$1"; shift
    [ -n "$config" ] || config="$RDDMGR/config/rddmgr.conf"
    source "$RDDMGR/lib/rddmgr.conf"
    source "$config" || die
    source "$RDDMGR/config/secrets.conf" || die
    for config in "$@"; do
        source "$config" || die
    done
}

################################################################################
# fonctions rddmgr
################################################################################

function verifix_config() {
    mkdir -p "$RDDMGR/config/lib-ext"

    [ -f "$RDDMGR/config/secrets.conf" ] || regen-secrets

    local -a configs; local config
    setx -a configs=ls_files "$RDDMGR/lib/templates/config"
    for config in "${configs[@]}"; do
        if [ ! -f "$RDDMGR/config/$config" ]; then
            cp "$RDDMGR/lib/templates/config/$config" "$RDDMGR/config"
            chmod 600 "$RDDMGR/config/$config"
            eimportant "Vous devez examiner et renseigner le fichier config/$config"
        fi
    done

    if [ ! -f "$RDDMGR/config/rddmgr.conf" ]; then
        einfo "installation du fichier config/rddmgr.conf par défaut"
        awk <"$RDDMGR/lib/rddmgr.conf" >"$RDDMGR/config/rddmgr.conf" '{
  if ($0 ~ /^[A-Za-z0-9_]+=[^$]*$/) {
    print "#" $0
  } else {
    print
  }
}'

        if ask_yesno "Voulez-vous examiner la configuration par défaut?" O; then
            less -F "$RDDMGR/config/rddmgr.conf"
            enote "\
Le cas échéant, modifiez la configuration avant de relancer ce script:
    $EDITOR config/rddmgr.conf
    ./rddmgr"
            exit
        fi
    fi
}

function init_system() {
    esection "Initialisation de l'environnement docker"

    if [ -n "$InitNetworks" ]; then
        # Création des réseaux
        for net in "$DBNET" "$LBNET"; do
            if [ -z "$(dklsnet "$net")" ]; then
                estep "Création du réseau $net"
                docker network create --attachable "$net"
            fi
        done
    fi

    local start_traefik
    if [ -n "$InitTraefik" ]; then
        # image traefik
        if [ -d "$RDDMGR/traefik.service" -a -z "$Reinit" ]; then
            ewarn "le répertoire traefik.service existe: il ne sera pas écrasé"
        else
            if dkrunning rddmgr/traefik-main; then
                stop_services traefik.service
                start_traefik=1
            fi

            estep "Copie du répertoire traefik.service"
            rsync -a "$RDDMGR/lib/templates/traefik.service/" "$RDDMGR/traefik.service" || die

            estep "Mise à jour des variables dans les fichiers de traefik.service"
            merge_vars "$RDDMGR/traefik.service"

            if [ -n "$start_traefik" ]; then
                start_services traefik.service
            fi
        fi
    fi

    local start_pgadmin
    if [ -n "$InitPgadmin" ]; then
        # image pgadmin
        if [ -d "$RDDMGR/pgadmin.service" -a -z "$Reinit" ]; then
            ewarn "le répertoire pgadmin.service existe: il ne sera pas écrasé"
        else
            if dkrunning rddmgr/pgadmin-main; then
                stop_services pgadmin.service
                start_pgadmin=1
            fi

            estep "Copie du répertoire pgadmin.service"
            rsync -a "$RDDMGR/lib/templates/pgadmin.service/" "$RDDMGR/pgadmin.service" || die

            estep "Mise à jour des variables dans les fichiers de pgadmin.service"
            merge_vars "$RDDMGR/pgadmin.service"

            if [ -n "$start_pgadmin" ]; then
                start_services pgadmin.service
            fi
        fi

        estep "Mise à jour de la liste des serveurs"
        update-pgadmin
    fi

    if [ -z "$start_traefik" -a -z "$start_pgadmin" ]; then
        enote "Utilisez rddmgr --start pour démarrer les services"
    fi
}

function check_system() {
    edebug "Vérification de l'environnement docker et des ateliers"

    edebug "Vérification des réseaux"
    [ -n "$(dklsnet "$DBNET")" ] || die_use_init "Réseau $DBNET introuvable"
    [ -n "$(dklsnet "$LBNET")" ] || die_use_init "Réseau $DBNET introuvable"

    edebug "Vérification des services"
    [ -d "$RDDMGR/traefik.service" ] || die_use_init "traefik n'a pas été configuré"
    [ -d "$RDDMGR/pgadmin.service" ] || die_use_init "pgAdmin n'a pas été configuré"
}

function list_workshops() {
    local -a wksdirs; local wksdir default composefile status
    setx -a wksdirs=ls_dirs "$RDDMGR" "*.wks"
    if [ ${#wksdirs[*]} -gt 0 ]; then
        if [ -d "$RDDMGR/default.wks" -a -L "$RDDMGR/default.wks" ]; then
            setx default=readlink "$RDDMGR/default.wks"
        else
            default="${wksdirs[0]}"
        fi
        esection "Liste des ateliers"
        for wksdir in "${wksdirs[@]}"; do
            [ "$wksdir" == default.wks -a -L "$RDDMGR/$wksdir" ] && continue
            composefile="$RDDMGR/$wksdir/rddtools.docker-compose.yml"
            if [ ! -f "$composefile" ]; then
                status=" -- ${COULEUR_ROUGE}non initialisé${COULEUR_NORMALE}"
            elif dcrunning "$composefile"; then
                status=" -- base pivot ${COULEUR_VERTE}démarrée${COULEUR_NORMALE}"
            else
                status=" -- base pivot arrêtée"
            fi
            if [ "$wksdir" == "$default" ]; then
                estep "$wksdir (atelier par défaut)$status"
            else
                estep "$wksdir$status"
            fi
        done
    else
        echo_no_workshops
    fi
}

function create_workshop() {
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## analyse des arguments
    local arg argname
    local version vxx devxx dvrddtools dvmypegase dvpivotbdd
    local wksdir source_wksdir shareddir rddtools mypegase pivotbdd scriptx source initsrc initph
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            # répertoires
            setx argname=basename "$arg"
            if [[ "$argname" == *.wks ]]; then
                if [ -z "$wksdir" -a -z "$version" ]; then
                    wksdir="$arg"
                elif [ -z "$source_wksdir" ]; then
                    source_wksdir="$arg"
                elif [ -z "$wksdir" ]; then
                    wksdir="$arg"
                else
                    die "$arg: il ne faut spécifier que deux ateliers maximum: celui à créer et la source"
                fi
            elif [ -n "$shareddir" ]; then
                die "$arg: il ne faut spécifier le répertoire partagé qu'une seule fois"
            else
                shareddir="$arg"
            fi
        elif [ -f "$arg" ]; then
            # fichiers
            setx filename=basename "$arg"
            case "$filename" in
            rdd-tools_*.tar)
                [ -n "$rddtools" ] && die "$arg: il ne faut spécifier qu'un seul fichier image"
                rddtools="$arg"
                ;;
            mypegase_*.env)
                [ -n "$mypegase" ] && die "$arg: il ne faut spécifier qu'un seul fichier d'environnement"
                mypegase="$arg"
                ;;
            rdd-tools-pivot_*.tar.gz)
                [ -n "$pivotbdd" ] && die "$arg: il ne faut spécifier qu'une seule définition de base pivot"
                pivotbdd="$arg"
                ;;
            RDD-scripts-externes_*.zip)
                [ -n "$scriptx" ] && die "$arg: il ne faut spécifier qu'un seul fichier de scripts externes"
                scriptx="$arg"
                ;;
            RDD-init-transco-apogee_*.zip|RDD-init-transco-scolarix_*.zip|RDD-init-transco-sve_*.zip|RDD-init-transco-vierge_*.zip)
                [ -n "$initsrc" ] && die "$arg: il ne faut spécifier qu'un seul fichier d'initialisation et de transcodification"
                initsrc="$arg"
                source="${arg#RDD-init-transco-}"
                source="${source%_*}"
                ;;
            RDD-init-habilitations-personnes_*.zip)
                [ -n "$initph" ] && die "$arg: il ne faut spécifier qu'un seul fichier d'initialisation des personnes et des habilitations"
                initph="$arg"
                ;;
            *) die "$arg: fichier non reconnu";;
            esac
        else
            # autres
            local major minor patch
            case "$arg" in
            c=*|create=*)
                if [ "${arg#c=}" != "$arg" ]; then arg="${arg#c=}"
                elif [ "${arg#create=}" != "$arg" ]; then arg="${arg#create=}"
                fi
                [ -n "$wksdir" ] && ewarn "$arg: écrasement de la valeur précédente de la destination"
                wksdir="$arg"
                ;;
            s=*|source=)
                if [ "${arg#s=}" != "$arg" ]; then arg="${arg#s=}"
                elif [ "${arg#source=}" != "$arg" ]; then arg="${arg#source=}"
                fi
                [ -n "$source_wksdir" ] && ewarn "$arg: écrasement de la valeur précédente de la source"
                source_wksdir="$arg"
                ;;
            r=*|shared=)
                if [ "${arg#r=}" != "$arg" ]; then arg="${arg#r=}"
                elif [ "${arg#shared=}" != "$arg" ]; then arg="${arg#shared=}"
                fi
                [ -n "$shareddir" ] && ewarn "$arg: écrasement de la valeur précédente du répertoire partagé"
                shareddir="$arg"
                ;;
            v=*|version=)
                if [ "${arg#v=}" != "$arg" ]; then arg="${arg#v=}"
                elif [ "${arg#version=}" != "$arg" ]; then arg="${arg#version=}"
                fi
                if is_version "$arg"; then
                    set_version "$arg"
                elif is_vxx "$arg"; then
                    set_vxx "$arg"
                elif is_devxx "$arg"; then
                    set_devxx "$arg"
                else
                    set_version "$arg"
                fi
                ;;
            i=*|image=*)
                if [ "${arg#i=}" != "$arg" ]; then arg="${arg#i=}"
                elif [ "${arg#image=}" != "$arg" ]; then arg="${arg#image=}"
                fi
                [ -n "$rddtools" ] && ewarn "$arg: écrasement de la valeur précédente du fichier image"
                rddtools="$arg"
                ;;
            e=*|m=*|env=*|mypegase=*)
                if [ "${arg#e=}" != "$arg" ]; then arg="${arg#e=}"
                elif [ "${arg#m=}" != "$arg" ]; then arg="${arg#m=}"
                elif [ "${arg#env=}" != "$arg" ]; then arg="${arg#env=}"
                elif [ "${arg#mypegase=}" != "$arg" ]; then arg="${arg#mypegase=}"
                fi
                [ -n "$mypegase" ] && ewarn "$arg: écrasement de la valeur précédente du fichier d'environnement"
                mypegase="$arg"
                ;;
            p=*|b=*|pivot=*|bdd=*|pivotbdd=*)
                if [ "${arg#p=}" != "$arg" ]; then arg="${arg#p=}"
                elif [ "${arg#b=}" != "$arg" ]; then arg="${arg#b=}"
                elif [ "${arg#pivot=}" != "$arg" ]; then arg="${arg#pivot=}"
                elif [ "${arg#bdd=}" != "$arg" ]; then arg="${arg#bdd=}"
                elif [ "${arg#pivotbdd=}" != "$arg" ]; then arg="${arg#pivotbdd=}"
                fi
                [ -n "$pivotbdd" ] && ewarn "$arg: écrasement de la valeur précédente de la définition de base pivot"
                pivotbdd="$arg"
                ;;
            apogee|scolarix|sve|vierge)
                source="$arg"
                ;;
            *)
                if [ -d "$RDDMGR/$arg" ]; then
                    if [ -z "$wksdir" -a -z "$version" ]; then
                        wksdir="$arg"
                    elif [ -z "$source_wksdir" ]; then
                        source_wksdir="$arg"
                    elif [ -z "$wksdir" ]; then
                        wksdir="$arg"
                    else
                        die "$arg: il ne faut spécifier que deux ateliers maximum: celui à créer et la source"
                    fi
                elif [ -d "$RDDMGR/$arg.wks" ]; then
                    arg="$arg.wks"
                    if [ -z "$wksdir" -a -z "$version" ]; then
                        wksdir="$arg"
                    elif [ -z "$source_wksdir" ]; then
                        source_wksdir="$arg"
                    elif [ -z "$wksdir" ]; then
                        wksdir="$arg"
                    else
                        die "$arg: il ne faut spécifier que deux ateliers maximum: celui à créer et la source"
                    fi
                elif is_version "$arg"; then
                    set_version "$arg"
                elif is_vxx "$arg"; then
                    set_vxx "$arg"
                elif is_devxx "$arg"; then
                    set_devxx "$arg"
                elif [[ "$arg" == *.*.* ]]; then
                    check_version "$arg"
                    set_version "$arg"
                elif [[ "$arg" == 0.1.0-dev.* ]]; then
                    check_devxx "$arg"
                    set_devxx "$arg"
                elif [[ "$arg" == dev.* ]] && ispnum "${arg#dev.}"; then
                    arg=0.1.0-dev."${arg#dev.}"
                    check_devxx "$arg"
                    set_devxx "$arg"
                elif [[ "$arg" == dev* ]] && ispnum "${arg#dev}"; then
                    arg=0.1.0-dev."${arg#dev}"
                    check_devxx "$arg"
                    set_devxx "$arg"
                elif [ -z "$wksdir" ]; then
                    wksdir="$arg"
                else
                    die "$arg: version/valeur non reconnue"
                fi
                ;;
            esac
        fi
    done

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## calcul de la version

    if [ -n "$source_wksdir" ]; then
        setx source_wksdir=abspath "$source_wksdir" "$RDDMGR"
        [ "${source_wksdir#$RDDMGR/}" != "$source_wksdir" ] || die "$source_wksdir: l'atelier doit être dans le répertoire rddmgr"
        setx source_wksdir=basename "$source_wksdir"
        source_wksdir="${source_wksdir%.wks}.wks"

        # si on a un répertoire source, calculer les versions par défaut depuis
        # ce répertoire
        eval "$(
          source "$RDDMGR/$source_wksdir/.env"
          echo_setv svrddtools="$RDDTOOLS_VERSION"
          echo_setv svmypegase="$MYPEGASE_VERSION"
          echo_setv svpivotbdd="$PIVOTBDD_VERSION"
        )"
    fi

    if [ -z "$wksdir" ]; then
        if [ -n "$devxx" ]; then
            wksdir="dev$devxx"
        elif [ -n "$version" ]; then
            wksdir="v${version%%.*}"
        elif [ -n "$rddtools" ]; then
            setx arg=basename "$rddtools"
            arg="${arg#rdd-tools_}"
            arg="${arg%.tar}"
            if is_devxx "$arg"; then
                set_devxx "$arg"
                wksdir="dev$devxx"
            else
                set_version "$arg"
                wksdir="v${version%%.*}"
            fi
        else
            die "Vous devez spécifier la version de l'image"
        fi
        [ -n "$wksdir" ] && enote "Sélection automatique de $wksdir.wks d'après la version $version"
    fi

    [ -n "$wksdir" ] || die "vous devez spécifier le nom de l'atelier à créer"
    setx wksdir=abspath "$wksdir" "$RDDMGR"
    [ "${wksdir#$RDDMGR/}" != "$wksdir" ] || die "$wksdir: l'atelier doit être dans le répertoire rddmgr"
    setx wksdir=basename "$wksdir"
    wksdir="${wksdir%.wks}.wks"

    WKSDIR="$RDDMGR/$wksdir"
    [ -d "$WKSDIR" -a -z "$Recreate" ] && die "$wksdir: cet atelier existe déjà"

    if [ -z "$version" ]; then
        version="$svrddtools"
        [ -n "$version" ] || die "Vous devez spécifier la version de l'image"
        set_version "$version"
    fi

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## Calcul des sources

    local -a files; local file v
    if [ -z "$rddtools" ]; then
        v="$version"
        files=()
        [ -n "$source_wksdir" ] && files+=("$source_wksdir/init/rdd-tools_$v.tar")
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools/,}"rdd-tools_$v.tar")
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                rddtools="$file"
                break
            fi
        done
    fi
    if [ -z "$mypegase" ]; then
        [ -n "$devxx" ] && v="$svmypegase" || v="$version"
        files=()
        [ -n "$source_wksdir" ] && files+=("$source_wksdir/init/mypegase_$v.env")
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools/,}"mypegase_$v.env")
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                mypegase="$file"
                break
            fi
        done
    fi
    if [ -z "$pivotbdd" ]; then
        [ -n "$devxx" ] && v="$svpivotbdd" || v="$version"
        files=()
        [ -n "$source_wksdir" ] && files+=("$source_wksdir/init/rdd-tools-pivot_$v"{/,.tar.gz})
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools-pivot/,}"rdd-tools-pivot_$v.tar.gz")
        for file in "${files[@]}"; do
            if [ -d "$file" ]; then
                pivotbdd="${file%/}"
                break
            elif [ -f "$file" ]; then
                pivotbdd="$file"
                break
            fi
        done
    fi
    if [ -z "$scriptx" ]; then
        files=()
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools-pivot/,}"RDD-scripts-externes_$version.zip")
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                scriptx="$file"
                break
            fi
        done
    fi
    if [ -z "$initsrc" ]; then
        files=()
        if [ -n "$shareddir" ]; then
            if [ -n "$source" ]; then
                files+=("$shareddir/"{fichiers_init_et_transcos/,}"RDD-init-transco-${source}_$version.zip")
            else
                files+=("$shareddir/"{fichiers_init_et_transcos/,}"RDD-init-transco-"{apogee,scolarix,sve,vierge}"_$version.zip")
            fi
        fi
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                initsrc="$file"
                if [ -z "$source" ]; then
                    setx source=basename "$file"
                    source="${source#RDD-init-transco-}"
                    source="${source%_*}"
                fi
                break
            fi
        done
    fi
    if [ -z "$initph" ]; then
        files=()
        [ -n "$shareddir" ] && files+=("$shareddir/"{fichiers_init_et_transcos/,}"RDD-init-habilitations-personnes_$vxx.zip")
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                initph="$file"
                break
            fi
        done
    fi

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## Calcul des fichiers à copier/télécharger
    esection "Résumé des actions"

    if [ -d "$WKSDIR" ]; then
        enote "$wksdir: ce répertoire existe déjà"
    else
        estep "$wksdir: ce répertoire sera créé"
    fi

    if [ -n "$rddtools" ]; then
        setx rddtoolsname=basename "$rddtools"
        rddtools_version="${rddtoolsname#rdd-tools_}"
        rddtools_version="${rddtools_version%.tar}"
    else
        rddtoolsname="rdd-tools_$version.tar"
        rddtools_version="$version"
    fi
    if [ -n "$(dklsimg "$rddtools_version")" ]; then
        # l'image est déjà importée
        if [ -n "$rddtools" ]; then
            ewarn "$rddtools: ce fichier sera ignoré, l'image est déjà importée"
        else
            enote "$RDDTOOLS_IMAGE:$rddtools_version: l'image est déjà importée"
        fi
    elif [ -n "$rddtools" ]; then
        estep "$rddtools: ce fichier sera copié et importé"
    else
        estep "le fichier rdd-tools_$version.tar sera téléchargé et importé"
    fi

    if [ -n "$mypegase" ]; then
        setx mypegasename=basename "$mypegase"
        mypegase_version="${mypegasename#mypegase_}"
        mypegase_version="${mypegase_version%.env}"
    else
        mypegasename="mypegase_$version.env"
        mypegase_version="$version"
    fi
    if [ -f "$WKSDIR/init/$mypegasename" ]; then
        if [ -n "$mypegase" ]; then
            ewarn "$mypegase: ce fichier sera ignoré, le fichier est déjà présent"
        else
            enote "$mypegasename: le fichier est présent"
        fi
    elif [ -n "$mypegase" ]; then
        estep "$mypegase: ce fichier sera copié"
    else
        estep "$mypegasename: ce fichier sera téléchargé"
    fi

    if [ -n "$pivotbdd" ]; then
        setx pivotbddname=basename "$pivotbdd"
        pivotbdd_version="${pivotbddname#rdd-tools-pivot_}"
        pivotbdd_version="${pivotbdd_version%.tar.gz}"
    else
        pivotbddname="rdd-tools-pivot_$version.tar.gz"
        pivotbdd_version="$version"
    fi
    pivotbdddir="rdd-tools-pivot_$pivotbdd_version"
    if [ -d "$WKSDIR/init/$pivotbdddir" ]; then
        if [ -n "$pivotbdd" ]; then
            ewarn "$pivotbdd: ce fichier sera ignoré, le répertoire est déjà présent"
        else
            enote "$pivotbdddir: le répertoire est présent"
        fi
    elif [ -n "$pivotbdd" ]; then
        estep "$pivotbdd: ce fichier sera copié"
    else
        estep "$pivotbddname: ce fichier sera téléchargé"
    fi

    if [ -d "$RDDMGR/$SCRIPTS_EXTERNES" ]; then
        enote "$SCRIPTS_EXTERNES: le répertoire est présent"
        [ -n "$scriptx" ] && ewarn "$scriptx: ce fichier sera ignoré, le répertoire est déjà présent"
    else
        if [ -n "$scriptx" ]; then
            setx scriptxname=basename "$scriptx"
            tversion="${scriptxname#RDD-scripts-externes_}"
            tversion="${tversion%.zip}"
        else
            scriptxname="RDD-scripts-externes_$version.zip"
            tversion="$version"
        fi
        if [ -n "$scriptx" ]; then
            estep "$scriptx: ce fichier sera copié"
        else
            estep "$scriptxname: ce fichier sera téléchargé"
        fi
    fi

    if [ -d "$RDDMGR/$FICHIERS_INIT_TRANSCO" ]; then
        enote "$FICHIERS_INIT_TRANSCO: le répertoire est présent"
        [ -n "$initsrc" ] && ewarn "$initsrc: ce fichier sera ignoré, le répertoire est déjà présent"
        [ -n "$initph" ] && ewarn "$initph: ce fichier sera ignoré, le répertoire est déjà présent"
    elif [ -z "$source" ]; then
        ewarn "Vous n'avez pas spécifié la source (apogee, scolarix, sve, vierge). Aucun fichier d'initialisation ne sera traité"
    else
        if [ -n "$initsrc" ]; then
            setx initsrcname=basename "$initsrc"
            tversion="${initsrcname#RDD-init-transco-${source}_}"
            tversion="${tversion%.zip}"
        else
            initsrcname="RDD-init-transco-${source}_$version.zip"
            tversion="$version"
        fi
        initsrcdir="RDD-init-transco-${source}_$tversion"
        if [ -n "$initsrc" ]; then
            estep "$initsrc: ce fichier sera copié"
        else
            estep "$initsrcname: ce fichier sera téléchargé"
        fi

        if [ -n "$initph" ]; then
            setx initphname=basename "$initph"
            tversion="${initphname#RDD-init-habilitations-personnes_}"
            tversion="${tversion%.zip}"
        else
            initphname="RDD-init-habilitations-personnes_$vxx.zip"
            tversion="$vxx"
        fi
        initphdir="RDD-init-habilitations-personnes_$tversion"
        if [ -n "$initph" ]; then
            estep "$initph: ce fichier sera copié"
        else
            estep "$initphname: ce fichier sera téléchargé"
        fi
    fi

    ask_yesno "Confirmez-vous ces opérations?" O || die

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # Initialiser l'environnement

    esection "Création $wksdir"

    stop_pivotbdd

    estep "Copie du répertoire${Recreate:+ avec écrasement}"
    rsync -a "$RDDMGR/lib/templates/workshop/" "$WKSDIR/" || die

    scripts_externes="$RDDMGR/$SCRIPTS_EXTERNES"
    fichiers_init_transco="$RDDMGR/$FICHIERS_INIT_TRANSCO"
    backupsdir="$RDDMGR/$BACKUPS"
    mkdir -p "$backupsdir" || die
    chmod 775 "$backupsdir"

    wksdirinit="$WKSDIR/init"
    logsdir="$WKSDIR/logs"
    mkdir -p "$wksdirinit" || die
    mkdir -p "$logsdir" || die
    chmod 775 "$logsdir"

    etitle "Image: $RDDTOOLS_IMAGE:$rddtools_version"
    import=1
    if [ -n "$(dklsimg "$version")" ]; then
        estep "L'image a déjà été importée"
        import=
    elif [ -n "$rddtools" ]; then
        copy_any "$rddtools" "$wksdirinit" || die
        rddtools="$wksdirinit/$rddtoolsname"
    else
        rddtools="$wksdirinit/$rddtoolsname"
        if is_devxx "$rddtoolsname" rdd-tools_ .tar; then
            download_shared "/RDD/rdd-tools/temp/$rddtoolsname" "$rddtools" || die
        else
            download_shared "/RDD/rdd-tools/$rddtoolsname" "$rddtools" || die
        fi
    fi
    if [ -n "$import" ]; then
        estep "Importation de l'image"
        docker load -i "$rddtools" || die

        #estep "Suppression de l'archive source"
        #rm "$rddtools" || die
    fi
    eend

    etitle "Fichier environnement: $mypegasename"
    fixmypegase=1
    if [ -f "$wksdirinit/$mypegasename" ]; then
        estep "Le fichier est déjà présent"
        mypegase="$wksdirinit/$mypegasename"
        fixmypegase=
    elif [ -n "$mypegase" ]; then
        copy_any "$mypegase" "$wksdirinit" || die
        mypegase="$wksdirinit/$mypegasename"
    else
        mypegase="$wksdirinit/$mypegasename"
        if is_devxx "$mypegasename" mypegase_ .env; then
            download_shared "/RDD/rdd-tools/temp/$mypegasename" "$mypegase" || die
        else
            download_shared "/RDD/rdd-tools/$mypegasename" "$mypegase" || die
        fi
    fi
    if [ -n "$fixmypegase" ]; then
        #estep "Correction du fichier"
        : #XXX s'assurer que le fichier a les fins de lignes unix
    fi
    eend

    etitle "Définition base pivot: $pivotbdddir"
    fixpivotbdd=1
    if [ -d "$wksdirinit/$pivotbdddir" ]; then
        estep "Le répertoire est déjà présent"
        fixpivotbdd=
    elif [ -f "$wksdirinit/$pivotbddname" ]; then
        estep "Le fichier est présent"
        pivotbdd="$wksdirinit/$pivotbddname"
    elif [ -n "$pivotbdd" ]; then
        copy_any "$pivotbdd" "$wksdirinit" || die
        pivotbdd="$wksdirinit/$pivotbddname"
    else
        pivotbdd="$wksdirinit/$pivotbddname"
        if is_devxx "$pivotbddname" rdd-tools-pivot_ .tar.gz; then
            download_shared "/RDD/rdd-tools/temp/$pivotbddname" "$pivotbdd" || die
        else
            download_shared "/RDD/rdd-tools-pivot/$pivotbddname" "$pivotbdd" || die
        fi
    fi
    if [ -n "$fixpivotbdd" ]; then
        if [ -f "$pivotbdd" ]; then
            estep "Extraction de l'archive"
            tar xzf "$pivotbdd" -C "$wksdirinit" || die

            #estep "Suppression de l'archive source"
            #rm "$pivotbdd" || die
        fi

        estep "Correction du mot de passe pcscolpivot"
        sed -i \
            "s/PASSWORD 'password'/PASSWORD '${PCSCOLPIVOT_PASSWORD//\//\\\/}'/" \
            "$wksdirinit/$pivotbdddir/scripts/000_user.sql"
    fi
    eend

    etitle "Scripts externes: $SCRIPTS_EXTERNES"
    fixscriptx=1
    if [ -d "$scripts_externes" ]; then
        estep "Le répertoire est déjà présent"
        fixscriptx=
    elif [ -f "$wksdirinit/$scriptxname" ]; then
        estep "Le fichier est présent"
        scriptx="$wksdirinit/$scriptxname"
    elif [ -n "$scriptx" ]; then
        copy_any "$scriptx" "$wksdirinit" || die
        scriptx="$wksdirinit/$scriptxname"
    else
        scriptx="$wksdirinit/$scriptxname"
        if is_devxx "$scriptxname" RDD-scripts-externes_ .zip; then
            download_shared "/RDD/rdd-tools/temp/$scriptxname" "$scriptx" || die
        else
            download_shared "/RDD/rdd-tools-pivot/$scriptxname" "$scriptx" || die
        fi
    fi
    if [ -n "$fixscriptx" ]; then
        if [ -f "$scriptx" ]; then
            estep "Extraction de l'archive"
            mkdir -p "$scripts_externes" || die
            unzip -q -j "$scriptx" -d "$scripts_externes" || die

            #estep "Suppression de l'archive source"
            #rm "$scriptx" || die
        fi
    fi
    eend

    if [ -d "$fichiers_init_transco" ]; then
        etitle "Fichiers init, transco, personnes et habilitations: $FICHIERS_INIT_TRANSCO"
        estep "Le répertoire est déjà présent"
        eend
    else
        etitle "Fichiers init et transco: $initsrcdir"
        fixinitsrc=1
        if [ -d "$wksdirinit/$initsrcdir" ]; then
            estep "Le répertoire est déjà présent"
            fixinitsrc=
        elif [ -f "$wksdirinit/$initsrcname" ]; then
            estep "Le fichier est présent"
            initsrc="$wksdirinit/$initsrcname"
        elif [ -n "$initsrc" ]; then
            copy_any "$initsrc" "$wksdirinit" || die
            initsrc="$wksdirinit/$initsrcname"
        else
            initsrc="$wksdirinit/$initsrcname"
            download_shared "/RDD/fichiers_init_et_transcos/$initsrcname" "$initsrc" || die
        fi
        if [ -n "$fixinitsrc" ]; then
            if [ -f "$initsrc" ]; then
                estep "Extraction de l'archive"
                mkdir -p "$fichiers_init_transco" || die
                unzip -q -j "$initsrc" -d "$fichiers_init_transco" || die
                mkdir -p "$fichiers_init_transco/$initsrcdir"

                #estep "Suppression de l'archive source"
                #rm "$initsrc" || die
            fi
        fi
        eend

        etitle "Fichiers personnes et habilitations: $initphdir"
        fixinitph=1
        if [ -d "$wksdirinit/$initphdir" ]; then
            estep "Le répertoire est déjà présent"
            fixinitph=
        elif [ -f "$wksdirinit/$initphname" ]; then
            estep "Le fichier est présent"
            initph="$wksdirinit/$initphname"
        elif [ -n "$initph" ]; then
            copy_any "$initph" "$wksdirinit" || die
            initph="$wksdirinit/$initphname"
        else
            initph="$wksdirinit/$initphname"
            download_shared "/RDD/fichiers_init_et_transcos/$initphname" "$initph" || die
        fi
        if [ -n "$fixinitph" ]; then
            if [ -f "$initph" ]; then
                estep "Extraction de l'archive"
                mkdir -p "$fichiers_init_transco" || die
                unzip -q -j "$initph" -d "$fichiers_init_transco" || die
                mkdir -p "$fichiers_init_transco/$initphdir"

                #estep "Suppression de l'archive source"
                #rm "$initph" || die
            fi
        fi
        eend
    fi

    estep "Mise à jour des variables"
    WKSNAME="${wksdir%.wks}"
    RDDTOOLS_VERSION="$rddtools_version"
    MYPEGASE_VERSION="$mypegase_version"
    PIVOTBDD_VERSION="$pivotbdd_version"
    merge_vars "$WKSDIR"

    if [ -n "$source_wksdir" -a -d "$RDDMGR/$source_wksdir/envs" ]; then
        estep "Copie des environnements depuis $source_wksdir"
        cp -a "$RDDMGR/$source_wksdir/envs" "$WKSDIR"
    fi

    if [ -z "$devxx" ]; then
        # Pour une version majeure, toujours sélectionner comme atelier par
        # défaut
        enote "Autosélection de $wksdir comme atelier par défaut"
        ln -sfT "$wksdir" "$RDDMGR/default.wks"
    fi

    #estep "Démarrage de la base pivot"
    start_pivotbdd

    estep "Mise à jour de la liste des serveurs"
    update-pgadmin

    enote "Vous pouvez maintenant aller dans l'atelier et commencer à utiliser rddtools
    cd $wksdir
    ./rddtools"
}

function delete_workshop() {
    local wksdir showwarn
    for wksdir in "$@"; do
        setx wksdir=abspath "$wksdir"
        [ "${wksdir#$RDDMGR/}" != "$wksdir" ] || die "$wksdir: l'atelier doit être dans le répertoire rddmgr"
        setx wksdirname=basename "$wksdir"
        [[ "$wksdirname" == *.wks ]] || die "$wksdirname: n'est pas un atelier"
        [ -d "$wksdir" ] || die "$wksdirname: atelier non trouvé"

        ask_yesno "Etes-vous certain de vouloir supprimer $wksdirname?" || continue
        if [ -z "$showwarn" ]; then
            eimportant "La suppression des ateliers est uniquement manuelle"
            showwarn=1
        fi
        einfo "Si vous êtes CERTAIN que l'atelier ne contient plus de données à sauvegarder,
- assurez-vous que rddweb ne tourne pas dans cet atelier
    $(qvals "./$wksdirname/rddtools" -k)
- puis vous pouvez le supprimer avec une commande comme celle-ci:
    $(qvals sudo rm -rf "$wksdirname")
- puis mettez à jour la configuration
    $(qvals ./lib/sbin/update-pgadmin)"
    done
}

function set_default_workshop() {
    local default; local -a wksdirs
    if [ -d "$RDDMGR/default.wks" -a -L "$RDDMGR/default.wks" ]; then
        setx default=readlink "$RDDMGR/default.wks"
    else
        setx -a wksdirs=ls_dirs "$RDDMGR" "*.wks"
        default="${wksdirs[0]}"
        if [ -n "$default" ]; then
            enote "Autosélection de $default comme atelier par défaut"
            ln -s "$default" "$RDDMGR/default.wks"
        fi
    fi
    upvar default "$default"
}

function _set_services() {
    if [ $# -eq 0 -a -n "$default_all_services" ]; then
        # aucun service n'est spécifié: les prendre tous par défaut
        setx -a services=ls_dirs "$RDDMGR" traefik.service pgadmin.service "*.wks"
        set -- "${services[@]}"
        services=()
    fi
    for service in "$@"; do
        setx service=basename "$service"
        auto=
        case "$service" in
        traefik|traefik.service) traefik=1;;
        pgadmin|pgadmin.service) pgadmin=1;;
        default|default.wks) default=1;;
        *)
            service="${service%.wks}.wks"
            [ -d "$RDDMGR/$service" ] || die "$service: service invalide"
            services+=("$service")
            ;;
        esac
    done
    if [ -n "$auto" ]; then
        traefik=1
        pgadmin=1
        default=1
    fi
}

function start_services() {
    local service traefik pgadmin default
    local auto=1 default_all_services=
    local -a services; _set_services "$@"

    if [ -n "$traefik" ]; then
        cd "$RDDMGR/traefik.service"
        if dkrunning rddmgr/traefik-main; then
            enote "traefik est démarré. la console est accessible à l'adresse http://$TRAEFIK_LBHOST:$HTTP_PORT/"
        else
            estep "Démarrage de traefik"
            docker compose up ${BuildBefore:+--build} -d || die
            enote "la console traefik est accessible à l'adresse http://$TRAEFIK_LBHOST:$HTTP_PORT/"
        fi
    fi

    if [ -n "$pgadmin" ]; then
        cd "$RDDMGR/pgadmin.service"
        if dkrunning rddmgr/pgadmin-main; then
            enote "pgAdmin est démarré et accessible à l'adresse http://$PGADMIN_LBHOST:$HTTP_PORT/"
        else
            estep "Démarrage de pgAdmin"
            docker compose up ${BuildBefore:+--build} -d || die
            enote "pgAdmin est accessible à l'adresse http://$PGADMIN_LBHOST:$HTTP_PORT/"
        fi
    fi

    if [ -n "$default" ]; then
        set_default_workshop
        if [ -n "$default" ]; then
            "$RDDMGR/$default/rddtools" -s || die
        elif [ -n "$auto" ]; then
            echo_no_workshops
        fi
    fi

    for service in "${services[@]}"; do
        "$RDDMGR/$service/rddtools" -s || die
    done
}

function stop_services() {
    local service traefik pgadmin default
    local auto=1 default_all_services=1
    local -a services; _set_services "$@"

    for service in "${services[@]}"; do
        "$RDDMGR/$service/rddtools" -k || die
    done

    if [ -n "$default" ]; then
        set_default_workshop
        if [ -n "$default" ]; then
            "$RDDMGR/$default/rddtools" -k || die
        fi
    fi

    if [ -n "$pgadmin" ]; then
        cd "$RDDMGR/pgadmin.service"
        if dkrunning rddmgr/pgadmin-main; then
            estep "Arrêt de pgAdmin"
            docker compose down || die
        fi
    fi

    if [ -n "$traefik" ]; then
        cd "$RDDMGR/traefik.service"
        if dkrunning rddmgr/traefik-main; then
            estep "Arrêt de traefik"
            docker compose down || die
        fi
    fi
}

function restart_services() {
    local service traefik pgadmin default
    local auto=1 default_all_services=
    local -a services; _set_services "$@"
    set -- "${services[@]}"
    services=()

    stop_services "$@"
    start_services "$@"
}

################################################################################
# fonctions rddtools
################################################################################

function start_pivotbdd() {
    local composefile="$WKSDIR/rddtools.docker-compose.yml"
    [ -f "$composefile" ] || die "$composefile: fichier introuvable"
    if dcrunning "$composefile"; then
        enote "la base pivot est démarrée"
    else
        estep "Démarrage de la base pivot"
        docker compose -f "$composefile" up ${BuildBefore:+--build} -d --wait || die
    fi
}

function stop_pivotbdd() {
    local composefile="$WKSDIR/rddtools.docker-compose.yml"
    [ -f "$composefile" ] || return 0
    if dcrunning "$composefile"; then
        estep "Arrêt de le base pivot"
        docker compose -f "$composefile" down || die
    fi
}

function restart_pivotbdd() {
    stop_pivotbdd "$@"
    start_pivotbdd "$@"
}

function list_envs() {
    local -a envnames; local envname current
    if [ -L "$WKSDIR/envs/current" ]; then
        current="$(readlink "$WKSDIR/envs/current")"
    fi
    setx -a envnames=ls_files "$WKSDIR/envs" "*.env"
    if [ ${#envnames[*]} -gt 0 ]; then
        esection "Liste des environnements"
        for envname in "${envnames[@]}"; do
            if [ "$envname" == "$current" ]; then
                estep "$envname (environnement courant)"
            else
                estep "$envname"
            fi
        done
    else
        ewarn "Il n'y a pas d'environnement pour le moment. Utilisez l'option -c pour en créer un"
    fi
}

function ensure_system_ymls() {
    if [ -f "$WKSDIR/config/pegase.yml" ]; then
        pegase_yml="$WKSDIR/config/pegase.yml"
    elif [ -f "$RDDMGR/config/pegase.yml" ]; then
        pegase_yml="$RDDMGR/config/pegase.yml"
    else
        die "le fichier config/pegase.yml est requis"
    fi
    if [ -f "$WKSDIR/config/sources.yml" ]; then
        sources_yml="$WKSDIR/config/sources.yml"
    elif [ -f "$RDDMGR/config/sources.yml" ]; then
        sources_yml="$RDDMGR/config/sources.yml"
    else
        die "le fichier config/sources.yml est requis"
    fi
}

function _eval_env() {
    eval "$(cat "$WKSDIR/envs/$1" | grep '^_rddtools_' | sed 's/^_rddtools_//')"
}
function _set_previous_env() {
    if [ -L "$WKSDIR/envs/current" -a -f "$WKSDIR/envs/current" ]; then
        previous="$(readlink "$WKSDIR/envs/current")"
        _eval_env current
    fi
}
function _verifix_env() {
    [ -n "$Envname" ] && Envname="${Envname%.env}.env"
}
function ensure_user_env() {
    mkdir -p "$WKSDIR/envs"

    local previous; _set_previous_env
    if [ -z "$ForceCreate" ]; then
        local -a envnames
        [ -n "$Envname" ] || Envname="$previous"
        if [ -z "$Envname" ]; then
            # prendre le premier environnement
            setx -a envnames=ls_files "$WKSDIR/envs" "*.env"
            [ ${#envnames[*]} -gt 0 ] && Envname="${envnames[0]}"
        elif [ ! -f "$WKSDIR/envs/$Envname" ]; then
            # essayer quelques corrections standard
            if [ -f "$WKSDIR/envs/$Envname.env" ]; then
                # nom d'environnement sans extension
                Envname="$Envname.env"
            elif [[ "$Envname" != *_* ]]; then
                # nom sans préfixe: essayer de trouver un environnement avec un
                # préfixe quelconque, mais ne le sélectionner que s'il y a
                # unique correspondance
                _verifix_env
                setx -a envnames=ls_files "$WKSDIR/envs" "*_$Envname"
                if [ ${#envnames[*]} -eq 1 ]; then
                    Envname="${envnames[0]}"
                elif [ ${#envnames[*]} -gt 1 ]; then
                    die "Plusieurs environnements *_$Envname ont été trouvés:
    $(echo "${envnames[*]}")
Soyez plus spécifique dans votre sélection"
                fi
            fi
        fi
        [ -n "$Envname" ] || ewarn "Aucun environnement n'est défini ou sélectionné"
    fi

    _verifix_env
    if [ -n "$ForceCreate" -o -z "$Envname" -o ! -f "$WKSDIR/envs/$Envname" ]; then
        einfo "Il faut créer un nouvel environnement"
        eval "$(env_dump-config.py "$pegase_yml" "$sources_yml" -l --local-vars)"

        [ -n "$instance" ] || instance="${instances[0]}"
        simple_menu instance instances -t "Choix de l'instance PEGASE" -m "Veuillez choisir l'instance attaquée pour les injections"

        sources+=("pas de source")
        [ "$source" == none ] && source="pas de source"
        simple_menu source sources -t "Choix de la source" -m "Veuillez choisir la source des données pour les déversements"
        [ "$source" == "pas de source" ] && source=none

        if [ "$source" != none ]; then
            source_profiles="${source}_profiles[@]"; source_profiles=("${!source_profiles}")
            [ -n "$source_profile" ] || source_profile="${source_profiles[0]}"
            simple_menu source_profile source_profiles -t "Choix du profil ${source^^}" -m "Veuillez choisir le profil de la source de données"
        else
            source_profile=
        fi

        if [ -z "$Envname" ]; then
            Envname="${instance,,}.env"
            enote "Le nom de l'environnement sera $Envname"
        elif [[ "$Envname" != *_* ]]; then
            Envname="${instance,,}_${Envname}"
            enote "Le nom de l'environnement a été changé en $Envname sur la base de l'instance PEGASE"
        fi
        ask_yesno "Voulez-vous créer le nouvel environnement $Envname?" O || die

        echo >"$WKSDIR/envs/$Envname" "\
# Ces paramètres servent à sélectionner la source des données pour les
# déversements, ainsi que l'instance de PEGASE pour les injections
# Ne pas modifier ces valeurs
_rddtools_instance=$instance
_rddtools_source=$source
_rddtools_source_profile=$source_profile

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Ajouter vos paramètres à partir d'ici"
    fi

    user_env="$WKSDIR/envs/$Envname"
    [ -f "$user_env" ] || die "$Envname: environnemnt invalide"

    # rendre courant l'environnement sélectionné
    if [ "$Envname" != "$previous" ]; then
        enote "Sélection de l'environnement $Envname"
        ln -sfT "$Envname" "$WKSDIR/envs/current"
    fi

    eval "$(cat "$user_env" | grep '^_rddtools_' | sed 's/^_rddtools_//')"
}

function create_env() {
    local ForceCreate=1
    [ -z "$Envname" -a $# -gt 0 ] && Envname="$1"

    local pegase_yml sources_yml
    ensure_system_ymls

    local mypegase_env system_env user_env instance source source_profile
    ensure_user_env
}

function duplicate_env() {
    [ -z "$Envname" -a $# -gt 0 ] && Envname="$1"
    [ -n "$Envname" ] || die "Vous devez spécifier l'environnement à dupliquer"
    _verifix_env

    local Source="$Envname"
    local src_env="$WKSDIR/envs/$Source"
    [ -f "$src_env" ] || die "$Source: environnement invalide"
    _eval_env "$Source"

    [ $# -gt 1 ] && Envname="$2" || Envname=
    _verifix_env
    if [ -z "$Envname" ]; then
        Envname="${instance,,}.env"
        [ "$Envname" != "$Source" ] || die "$Source: impossible de dupliquer un environnement sur lui-même"
        enote "Le nom du nouvel environnement sera $Envname"
    elif [[ "$Envname" != *_* ]]; then
        Envname="${instance,,}_${Envname}"
        [ "$Envname" != "$Source" ] || die "$Source: impossible de dupliquer un environnement sur lui-même"
        enote "Le nom du nouvel environnement a été changé en $Envname sur la base de l'instance PEGASE"
    fi
    dest_env="$WKSDIR/envs/$Envname"
    [ -f "$dest_env" ] && die "$Envname: cet environnement existe déjà"

    ask_yesno "Voulez-vous dupliquer $Source vers $Envname?" O || die

    cp "$src_env" "$dest_env" || die
    if [ -f "$WKSDIR/envs/.$Source" ]; then
        cp "$WKSDIR/envs/.$Source" "$WKSDIR/envs/.$Envname" || die
    fi
    enote "Copie de $Source vers $Envname effectuée avec succès"
}

function delete_env() {
    [ -z "$Envname" -a $# -gt 0 ] && Envname="$1"
    [ -n "$Envname" ] || die "Vous devez spécifier l'environnement à supprimer"

    local previous; _set_previous_env
    _verifix_env

    [ -f "$WKSDIR/envs/$Envname" ] && enote "Suppression de l'environnement $Envname"
    rm -f "$WKSDIR/envs/$Envname" "$WKSDIR/envs/.$Envname"
    [ "$previous" == "$Envname" ] && rm -f "$WKSDIR/envs/current"
}

function edit_env() {
    [ -z "$Envname" -a $# -gt 0 ] && Envname="$1"

    local pegase_yml sources_yml
    ensure_system_ymls

    local mypegase_env system_env user_env instance source source_profile
    ensure_user_env

    "$EDITOR" "$WKSDIR/envs/$Envname"
}

function run_rddtools() {
    local pegase_yml sources_yml
    ensure_system_ymls

    local mypegase_env system_env user_env instance source source_profile
    ensure_user_env

    mypegase_env="$WKSDIR/init/mypegase_$MYPEGASE_VERSION.env"
    [ -f "$mypegase_env" ] || die "Le fichier ${mypegase_env#$WKSDIR/} est requis"

    system_env="$WKSDIR/envs/.$Envname"
    if should_update "$system_env" "$pegase_yml" "$sources_yml" "$WKSDIR/.env"; then
        env_dump-config.py \
            -s "$instance" \
            -d "$source" -p "$source_profile" \
            "$pegase_yml" "$sources_yml" "$WKSDIR/.env" >"$system_env"
    fi

    local -a run
    # arguments de base
    run=(run -it --rm --net "$DBNET")
    # environnements
    run+=(--env-file "$mypegase_env" --env-file "$system_env" --env-file "$user_env")
    [ -n "$Debug" ] && run+=(-e debug_job=O)
    # points de montage
    local filesdir="$RDDMGR/$FICHIERS_INIT_TRANSCO"
    local scriptxsdir="$RDDMGR/$SCRIPTS_EXTERNES"
    local backupsdir="$RDDMGR/$BACKUPS"
    local logsdir="$WKSDIR/logs/$(date +%Y%m%dT%H%M%S)"

    run+=(-v "$RDDMGR/config/lib-ext:/lib-ext:ro")
    run+=(-v "$filesdir:/files")
    run+=(-v "$scriptxsdir:/files/scripts-externes")
    run+=(-v "$backupsdir:/files/backup")
    run+=(-v "$logsdir:/logs")
    # image
    run+=("$RDDTOOLS_IMAGE:$RDDTOOLS_VERSION")

    # lancement de la commande
    docker "${run[@]}" "$@"; local r=$?

    # y a-t-il des logs?
    setx -a logs=ls_all "$logsdir"
    if [ ${#logs[*]} -gt 0 ]; then
        enote "Les logs sont dans le répertoire ${logsdir#$WKSDIR/} (code de retour $r)"
    else
        rmdir "$logsdir"
    fi

    [ -n "$CleanAfter" ] && rm "$system_env"
    return $r
}

################################################################################
# fonctions utilitaires
################################################################################

function dklsnet() {
    docker network ls --no-trunc --format '{{.Name}}' -f name="$1" 2>/dev/null
}
function dklsimg() {
    local version="$1" image="${2:-$RDDTOOLS_IMAGE}"
    docker image ls --no-trunc --format '{{.Repository}}:{{.Tag}}' "$image${version:+:$version}" 2>/dev/null
}
function dklsct() {
    # afficher le container dont l'image correspondante est $1
    docker ps --no-trunc --format '{{.Image}} {{.Names}}' | awk -v image="$1" '$1 == image { print $2 }'
}
function dkrunning() {
    # vérifier si le container d'image $1 tourne
    [ -n "$(dklsct "$@")" ]
}
function dclsct() {
    # afficher les containers correspondant à $1(=docker-compose.yml)
    docker compose ${1:+-f "$1"} ps -q
}
function dcrunning() {
    # vérifier si les containers correspondant à $1(=docker-compose.yml) tournent
    # si $2 est spécifié, c'est le nombre de service qui doit tourner
    if [ -n "$2" ]; then
        [ "$(dclsct "${@:1:1}" | wc -l)" -eq "$2" ]
    else
        [ -n "$(dclsct "${@:1:1}")" ]
    fi
}

function die_use() {
    eerror "$1"
    die "Utilisez rddmgr $2"
}
function die_use_init() {
    die_use "$1" "--init pour initialiser l'environnement"
}
function echo_no_workshops() {
    ewarn "Il n'y a pas d'atelier pour le moment. Utilisez rddmgr --create pour en créer un"
}

function should_update() {
    # faut-il mettre à jour le fichier $1 qui est construit à partir des
    # fichiers $2..@
    local dest="$1"; shift
    [ -f "$dest" ] || return 0
    local source
    for source in "$@"; do
        [ -f "$source" ] || continue
        [ "$source" -nt "$dest" ] && return 0
    done
    return 1
}

function copy_any() {
    ## copier un fichier ou un répertoire vers un répertoire
    # copie de répertoire à répertoire: le répertoire destination NE DOIT PAS
    # exister: si $dest existe, copier $source vers $dest/$bn où $bn est le nom
    # de base de $source
    # copie de fichier à répertoire: si $dest existe, copier $source vers
    # $source/$bn où $bn est le nom de base de $source. sinon, $dest est le nom
    # de la destination, et (dirname "$dest") est créé le cas échéant.
    local source="$1" dest="$2" destdir
    if [ -d "$dest" ]; then
        destdir="$dest"
        dest="$dest/$(basename "$source")"
    else
        destdir="$(dirname "$dest")"
    fi
    [ -d "$dest" ] && return 1

    estep "Copie $source --> $destdir/"
    mkdir -p "$destdir" || return 1
    cp -dR --preserve=mode,timestamps,links "$source" "$dest" || return 1
}
function download_shared() {
    # télécharger un fichier avec curl
    in_path curl || "le téléchargement de fichiers requière curl"

    local file="$1" dest="$2" destname="$(basename -- "$2")"
    local work="$RDDMGR/.$destname.tmpdl"
    local url="$SHARED_URL/files/?p=${file//\//%2F}&dl=1"

    estep "Téléchargement de $file --> $(dirname "$dest")/"
    curl -f#L -C - --retry 10 "$url" -o "$work" || return 1

    if cat "$work" | head -n5 | grep -q '<!DOCTYPE html'; then
        # fichier pourri
        rm "$work"
        eerror "Fichier introuvable"
        return 1
    fi
    mv "$work" "$dest" || return 1
}

function is_version() {
    # vérifier si le fichier $1 (dont on enlève le préfixe $2 et le suffixe $3) a
    # une version de la forme MM[.mm[.pp]]
    local version="$1" tmp major minor patch
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    ispnum "$tmp" && return
    major="${tmp%%.*}"; tmp="${tmp#*.}"
    ispnum "$major" || return 1

    [ -z "$tmp" ] && return
    ispnum "$tmp" && return
    minor="${tmp%%.*}"; tmp="${tmp#*.}"
    ispnum "$minor" || return 1

    [ -z "$tmp" ] && return
    ispnum "$tmp" && return
    patch="${tmp%%.*}"; tmp="${tmp#*.}"
    ispnum "$patch" || return 1

    [ -z "$tmp" ]
}
function check_version() {
    local version="$1"
    is_version "$version" || die "$version: version invalide"
}
function set_version() {
    local version="$1" tmp major minor patch vxx devxx
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    if ispnum "$tmp"; then
        version="$tmp.0.0"
    else
        major="${tmp%%.*}"; tmp="${tmp#*.}"
        if [ -z "$tmp" ]; then version="$major.0.0"
        elif ispnum "$tmp"; then version="$major.$tmp.0"
        else
            minor="${tmp%%.*}"; tmp="${tmp#*.}"
            if [ -z "$tmp" ]; then version="$major.$minor.0"
            elif ispnum "$tmp"; then version="$major.$minor.$tmp"
            else
                patch="${tmp%%.*}"; tmp="${tmp#*.}"
                version="$major.$minor.$patch"
            fi
        fi
    fi
    upvars version "$version" vxx "V${version%%.*}" devxx ""
}

function is_vxx() {
    # vérifier si le fichier $1 (dont on enlève le préfixe $2 et le suffix $3) a
    # une version de la forme VMM
    local version="$1" tmp major
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    major="${tmp#[Vv]}"
    ispnum "$major" || return 1
}
function check_vxx() {
    local version="$1"
    is_vxx "$version" || die "$version: version invalide"
}
function set_vxx() {
    local version="$1" tmp vxx devxx
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    upvars version "${tmp#[Vv]}.0.0" vxx "${tmp^^}" devxx ""
}

function is_devxx() {
    # vérifier si le fichier $1 (dont on enlève le préfixe $2 et le suffix $3) a
    # une version de la forme 0.1.0-dev.MM
    local version="$1" tmp major
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    major="${tmp#0.1.0-dev.}"
    ispnum "$major" || return 1
}
function check_devxx() {
    local version="$1"
    is_devxx "$version" || die "$version: version invalide"
}
function set_devxx() {
    local version="$1" tmp vxx devxx
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    upvars version "$tmp" vxx "" devxx "${tmp#0.1.0-dev.}"
}

function merge_vars() {
    local DBVIP="$DBVIP" LBVIP="$LBVIP"
    [ -n "$DBVIP" ] && DBVIP="${DBVIP%:}:"
    [ -n "$LBVIP" ] && LBVIP="${LBVIP%:}:"
    local USE_HTTPS="$USE_HTTPS" SSL="#" NOSSL=
    if [ -n "$USE_HTTPS" ]; then
        SSL=
        NOSSL="#"
    fi
    local USE_LETSENC="$USE_LETSENC" LETSENC="#" NOLETSENC=
    if [ -n "$USE_LETSENC" ]; then
        LETSENC=
        NOLETSENC="#"
    fi
    local TRAEFIK_PASSWORD="$TRAEFIK_PASSWORD" TRAEFIKP="#" NOTRAEFIKP=
    if [ -n "$TRAEFIK_PASSWORD" ]; then
        setx TRAEFIK_PASSWORD=tpasswd -u admin "$TRAEFIK_PASSWORD"
        TRAEFIKP=
        NOTRAEFIKP="#"
    fi
    local PGADMIN_PASSWORD="$PGADMIN_PASSWORD" PGADMINP="#" NOPGADMINP=
    if [ -n "$PGADMIN_PASSWORD" ]; then
        setx PGADMIN_PASSWORD=tpasswd -u pgadmin -q "$PGADMIN_PASSWORD"
        PGADMINP=
        NOPGADMINP="#"
    fi
    sed -i "\
s/@@LBNET@@/$LBNET/g
s/@@LBVIP@@/$LBVIP/g
s/@@LBHOST@@/$LBHOST/g
s/@@HTTP_PORT@@/$HTTP_PORT/g
s/@@HTTPS_PORT@@/$HTTPS_PORT/g
s/#@@SSL@@#/$SSL/g; s/#@@NOSSL@@#/$NOSSL/g
s/#@@LETSENC@@#/$LETSENC/g; s/#@@NOLETSENC@@#/$NOLETSENC/g
s/@@TRAEFIK_LBHOST@@/$TRAEFIK_LBHOST/g
s/@@TRAEFIK_PASSWORD@@/${TRAEFIK_PASSWORD//\//\\\/}/g
s/#@@TRAEFIKP@@#/$TRAEFIKP/g; s/#@@NOTRAEFIK@@#/$NOTRAEFIKP/g
s/@@PGADMIN_LBHOST@@/$PGADMIN_LBHOST/g
s/@@PGADMIN_PASSWORD@@/${PGADMIN_PASSWORD//\//\\\/}/g
s/#@@PGADMINP@@#/$PGADMINP/g; s/#@@NOPGADMINP@@#/$NOPGADMINP/g
s/@@DBNET@@/$DBNET/g
s/@@DBVIP@@/$DBVIP/g
s/@@PGSQL_PORT@@/$PGSQL_PORT/g
s/@@POSTGRES_PASSWORD@@/${POSTGRES_PASSWORD//\//\\\/}/g
s/@@PCSCOLPIVOT_PASSWORD@@/${PCSCOLPIVOT_PASSWORD//\//\\\/}/g
s/@@WKSNAME@@/$WKSNAME/g
s/@@RDDTOOLS_IMAGE@@/${RDDTOOLS_IMAGE//\//\\\/}/g
s/@@RDDTOOLS_VERSION@@/$RDDTOOLS_VERSION/g
s/@@MYPEGASE_VERSION@@/$MYPEGASE_VERSION/g
s/@@PIVOTBDD_VERSION@@/$PIVOTBDD_VERSION/g
" $(find "$1" -name private -prune -or -type f -print)
}
