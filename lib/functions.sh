# -*- coding: utf-8 mode: sh -*- vim:sw=4:sts=4:et:ai:si:sta:fenc=utf-8
# Fonctions de support pour rddmgr

RDDTOOLS_IMAGE=docker.pc-scol.fr/pcscol/rdd-tools
FICHIERS_TRANSCO=fichiers-transco
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

function init_env() {
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

    if [ -n "$InitTraefik" ]; then
        # image traefik
        if [ -d "$RDDMGR/traefik.service" -a -z "$Reinit" ]; then
            ewarn "le répertoire traefik.service existe: il ne sera pas écrasé"
        else
            estep "Copie du répertoire traefik.service"
            rsync -a "$RDDMGR/lib/templates/traefik.service/" "$RDDMGR/traefik.service" || die

            estep "Mise à jour des variables dans les fichiers de traefik.service"
            merge_vars "$RDDMGR/traefik.service"
        fi
    fi

    if [ -n "$InitPgadmin" ]; then
        # image pgadmin
        if [ -d "$RDDMGR/pgadmin.service" -a -z "$Reinit" ]; then
            ewarn "le répertoire pgadmin.service existe: il ne sera pas écrasé"
        else
            estep "Copie du répertoire pgadmin.service"
            rsync -a "$RDDMGR/lib/templates/pgadmin.service/" "$RDDMGR/pgadmin.service" || die

            estep "Mise à jour des variables dans les fichiers de pgadmin.service"
            merge_vars "$RDDMGR/pgadmin.service"
        fi

        estep "Mise à jour de la liste des serveurs"
        update-pgadmin
    fi
}

function check_env() {
    edebug "Vérification de l'environnement docker et des espaces de travail"

    edebug "Vérification des réseaux"
    [ -n "$(dklsnet "$DBNET")" ] || die_use_init "Réseau $DBNET introuvable"
    [ -n "$(dklsnet "$LBNET")" ] || die_use_init "Réseau $DBNET introuvable"

    edebug "Vérification des services"
    [ -d "$RDDMGR/traefik.service" ] || die_use_init "traefik n'a pas été configuré"
    [ -d "$RDDMGR/pgadmin.service" ] || die_use_init "pgAdmin n'a pas été configuré"
}

function list_workspaces() {
    local -a wsdirs; local wsdir default
    setx -a wsdirs=ls_dirs "$RDDMGR" "*.works"
    if [ ${#wsdirs[*]} -gt 0 ]; then
        if [ -d "$RDDMGR/default.works" -a -L "$RDDMGR/default.works" ]; then
            setx default=readlink "$RDDMGR/default.works"
        else
            default="${wsdirs[0]}"
        fi
        esection "Liste des espaces de travail"
        for wsdir in "${wsdirs[@]}"; do
            if [ "$wsdir" == default.works -a -L "$RDDMGR/$wsdir" ]; then
                continue
            elif [ "$wsdir" == "$default" ]; then
                estep "$wsdir (espace par défaut)"
            else
                estep "$wsdir"
            fi
        done
    else
        echo_no_workspaces
    fi
}

function create_workspace() {
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## analyse des arguments
    local arg argname
    local wsdir source_wsdir shareddir version vxx devxx rddtools mypegase pivotbdd scriptx source initsrc initph
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            # répertoires
            setx argname=basename "$arg"
            if [[ "$argname" == *.works ]]; then
                if [ -z "$wsdir" ]; then
                    wsdir="$arg"
                elif [ -z "$source_wsdir" ]; then
                    source_wsdir="$arg"
                else
                    die "$arg: il ne faut spécifier que l'espace de travail à créer et l'espace de travail source"
                fi
            elif [ -n "$shareddir" ]; then
                die "$arg: vous ne pouvez spécifier le répertoire partagé qu'une seule fois"
            else
                shareddir="$arg"
            fi
        elif [ -f "$arg" ]; then
            # fichiers
            setx filename=basename "$arg"
            case "$filename" in
            rdd-tools_*.tar)
                [ -n "$rddtools" ] && die "$arg: vous ne pouvez spécifier qu'un seul fichier image"
                rddtools="$arg"
                ;;
            mypegase_*.env)
                [ -n "$mypegase" ] && die "$arg: vous ne pouvez spécifier qu'un seul fichier d'environnement"
                mypegase="$arg"
                ;;
            rdd-tools-pivot_*.tar.gz)
                [ -n "$pivotbdd" ] && die "$arg: vous ne pouvez spécifier qu'une seule définition de base pivot"
                pivotbdd="$arg"
                ;;
            RDD-scripts-externes_*.zip)
                [ -n "$scriptx" ] && die "$arg: vous ne pouvez spécifier qu'un seul fichier de scripts externes"
                scriptx="$arg"
                ;;
            RDD-init-transco-apogee_*.zip|RDD-init-transco-scolarix_*.zip|RDD-init-transco-sve_*.zip|RDD-init-transco-vierge_*.zip)
                [ -n "$initsrc" ] && die "$arg: vous ne pouvez spécifier qu'un seul fichier d'initialisation et de transcodification"
                initsrc="$arg"
                source="${arg#RDD-init-transco-}"
                source="${source%_*}"
                ;;
            RDD-init-habilitations-personnes_*.zip)
                [ -n "$initph" ] && die "$arg: vous ne pouvez spécifier qu'un seul fichier d'initialisation des personnes et des habilitations"
                initph="$arg"
                ;;
            *) die "$arg: fichier non reconnu";;
            esac
        else
            # autres
            local major minor patch
            if [ -d "$RDDMGR/$arg" ]; then
                if [ -z "$wsdir" ]; then
                    wsdir="$arg"
                elif [ -z "$source_wsdir" ]; then
                    source_wsdir="$arg"
                else
                    die "$arg: il ne faut spécifier que l'espace de travail à créer et l'espace de travail source"
                fi
            elif [ -d "$RDDMGR/$arg.works" ]; then
                arg="$arg.works"
                if [ -z "$wsdir" ]; then
                    wsdir="$arg"
                elif [ -z "$source_wsdir" ]; then
                    source_wsdir="$arg"
                else
                    die "$arg: il ne faut spécifier que l'espace de travail à créer et l'espace de travail source"
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
            elif [[ "$arg" == dev* ]] && ispnum "${arg#dev}"; then
                arg=0.1.0-dev."${arg#dev}"
                check_devxx "$arg"
                set_devxx "$arg"
            elif [ "$arg" == apogee -o "$arg" == scolarix -o "$arg" == sve -o "$arg" == vierge ]; then
                source="$arg"
            elif [ -z "$wsdir" ]; then
                wsdir="$arg"
            else
                die "$arg: version/valeur non reconnue"
            fi
        fi
    done

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## calcul de la version
    if [ -z "$version" ]; then
        if [ -n "$rddtools" ]; then
            setx arg=basename "$rddtools"
            arg="${arg#rdd-tools_}"
            arg="${arg%.tar}"
        else
            die "Vous devez spécifier la version de l'image"
        fi
    fi
    if [ -z "$vxx" -a -z "$devxx" ]; then
        vxx="V${version%%.*}"
    fi

    if [ -z "$wsdir" ]; then
        if [ -n "$vxx" ]; then
            wsdir="${vxx,,}"
        elif [ -n "$devxx" ]; then
            wsdir="dev$devxx"
        fi
        [ -n "$wsdir" ] && enote "Sélection automatique de $wsdir.works d'après la version $version"
    fi

    [ -n "$wsdir" ] || die "vous devez spécifier le nom de l'espace de travail à créer"
    setx wsdir=abspath "$wsdir" "$RDDMGR"
    [ "${wsdir#$RDDMGR/}" != "$wsdir" ] || die "$wsdir: l'espace de travail doit être dans le répertoire rddmgr"
    setx wsdir=basename "$wsdir"
    wsdir="${wsdir%.works}.works"
    [ -d "$RDDMGR/$wsdir" -a -z "$Recreate" ] && die "$wsdir: cet espace de travail existe déjà"

    if [ -n "$source_wsdir" ]; then
        setx source_wsdir=abspath "$source_wsdir" "$RDDMGR"
        [ "${source_wsdir#$RDDMGR/}" != "$source_wsdir" ] || die "$source_wsdir: l'espace de travail doit être dans le répertoire rddmgr"
        setx source_wsdir=basename "$source_wsdir"
        source_wsdir="${source_wsdir%.works}.works"
    fi

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ## Calcul des sources
    local -a files; local file
    if [ -z "$rddtools" ]; then
        files=()
        [ -n "$source_wsdir" ] && files+=("$source_wsdir/init/rdd-tools_$version.tar")
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools/,}"rdd-tools_$version.tar")
        [ -n "$source_wsdir" ] && files+=("$source_wsdir/init/rdd-tools_"*.tar)
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                rddtools="$file"
                break
            fi
        done
    fi
    if [ -z "$mypegase" ]; then
        files=()
        [ -n "$source_wsdir" ] && files+=("$source_wsdir/init/mypegase_$version.env")
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools/,}"mypegase_$version.env")
        [ -n "$source_wsdir" ] && files+=("$source_wsdir/init/mypegase_"*.env)
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                mypegase="$file"
                break
            fi
        done
    fi
    if [ -z "$pivotbdd" ]; then
        files=()
        [ -n "$source_wsdir" ] && files+=("$source_wsdir/init/rdd-tools-pivot_$version"{/,.tar.gz})
        [ -n "$shareddir" ] && files+=("$shareddir/"{rdd-tools-pivot/,}"rdd-tools-pivot_$version.tar.gz")
        [ -n "$source_wsdir" ] && files+=("$source_wsdir/init/rdd-tools-pivot_"{*/,*.tar.gz})
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

    if [ -d "$RDDMGR/$wsdir" ]; then
        enote "$wsdir: ce répertoire existe déjà"
    else
        estep "$wsdir: ce répertoire sera créé"
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
    if [ -f "$RDDMGR/$wsdir/init/$mypegasename" ]; then
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
    if [ -d "$RDDMGR/$wsdir/init/$pivotbdddir" ]; then
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

    if [ -d "$RDDMGR/$FICHIERS_TRANSCO" ]; then
        enote "$FICHIERS_TRANSCO: le répertoire est présent"
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

    esection "Création $wsdir"
    estep "Copie du répertoire${Recreate:+ avec écrasement}"
    rsync -a "$RDDMGR/lib/templates/works/" "$RDDMGR/$wsdir/" || die

    wsdirinit="$RDDMGR/$wsdir/init"
    scripts_externes="$RDDMGR/$SCRIPTS_EXTERNES"
    fichiers_transco="$RDDMGR/$FICHIERS_TRANSCO"
    mkdir -p "$wsdirinit" || die

    etitle "Image: $RDDTOOLS_IMAGE:$rddtools_version"
    import=1
    if [ -n "$(dklsimg "$version")" ]; then
        estep "L'image a déjà été importée"
        import=
    elif [ -n "$rddtools" ]; then
        copy_any "$rddtools" "$wsdirinit" || die
        rddtools="$wsdirinit/$rddtoolsname"
    else
        rddtools="$wsdirinit/$rddtoolsname"
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
    if [ -f "$wsdirinit/$mypegasename" ]; then
        estep "Le fichier est déjà présent"
        mypegase="$wsdirinit/$mypegasename"
        fixmypegase=
    elif [ -n "$mypegase" ]; then
        copy_any "$mypegase" "$wsdirinit" || die
        mypegase="$wsdirinit/$mypegasename"
    else
        mypegase="$wsdirinit/$mypegasename"
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
    if [ -d "$wsdirinit/$pivotbdddir" ]; then
        estep "Le répertoire est déjà présent"
        fixpivotbdd=
    elif [ -f "$wsdirinit/$pivotbddname" ]; then
        estep "Le fichier est présent"
        pivotbdd="$wsdirinit/$pivotbddname"
    elif [ -n "$pivotbdd" ]; then
        copy_any "$pivotbdd" "$wsdirinit" || die
        pivotbdd="$wsdirinit/$pivotbddname"
    else
        pivotbdd="$wsdirinit/$pivotbddname"
        if is_devxx "$pivotbddname" rdd-tools-pivot_ .tar.gz; then
            download_shared "/RDD/rdd-tools/temp/$pivotbddname" "$pivotbdd" || die
        else
            download_shared "/RDD/rdd-tools-pivot/$pivotbddname" "$pivotbdd" || die
        fi
    fi
    if [ -n "$fixpivotbdd" ]; then
        if [ -f "$pivotbdd" ]; then
            estep "Extraction de l'archive"
            tar xzf "$pivotbdd" -C "$wsdirinit" || die

            #estep "Suppression de l'archive source"
            #rm "$pivotbdd" || die
        fi

        estep "Correction du mot de passe pcscolpivot"
        sed -i \
            "s/PASSWORD 'password'/PASSWORD '${PCSCOLPIVOT_PASSWORD//\//\\\/}'/" \
            "$wsdirinit/$pivotbdddir/scripts/000_user.sql"
    fi
    eend

    etitle "Scripts externes: $SCRIPTS_EXTERNES"
    fixscriptx=1
    if [ -d "$scripts_externes" ]; then
        estep "Le répertoire est déjà présent"
        fixscriptx=
    elif [ -f "$wsdirinit/$scriptxname" ]; then
        estep "Le fichier est présent"
        scriptx="$wsdirinit/$scriptxname"
    elif [ -n "$scriptx" ]; then
        copy_any "$scriptx" "$wsdirinit" || die
        scriptx="$wsdirinit/$scriptxname"
    else
        scriptx="$wsdirinit/$scriptxname"
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
            unzip -q "$scriptx" -d "$scripts_externes" || die

            #estep "Suppression de l'archive source"
            #rm "$scriptx" || die
        fi
    fi
    eend

    if [ -d "$fichiers_transco" ]; then
        etitle "Fichiers init, transco, personnes et habilitations: $FICHIERS_TRANSCO"
        estep "Le répertoire est déjà présent"
        eend
    else
        etitle "Fichiers init et transco: $initsrcdir"
        fixinitsrc=1
        if [ -d "$wsdirinit/$initsrcdir" ]; then
            estep "Le répertoire est déjà présent"
            fixinitsrc=
        elif [ -f "$wsdirinit/$initsrcname" ]; then
            estep "Le fichier est présent"
            initsrc="$wsdirinit/$initsrcname"
        elif [ -n "$initsrc" ]; then
            copy_any "$initsrc" "$wsdirinit" || die
            initsrc="$wsdirinit/$initsrcname"
        else
            initsrc="$wsdirinit/$initsrcname"
            download_shared "/RDD/rdd-tools-pivot/$initsrcname" "$initsrc" || die
        fi
        if [ -n "$fixinitsrc" ]; then
            if [ -f "$initsrc" ]; then
                estep "Extraction de l'archive"
                mkdir -p "$fichiers_transco" || die
                unzip -q -j "$initsrc" -d "$fichiers_transco" || die
                mkdir -p "$wsdirinit/$initsrcdir"

                #estep "Suppression de l'archive source"
                #rm "$initsrc" || die
            fi
        fi
        eend

        etitle "Fichiers personnes et habilitations: $initphdir"
        fixinitph=1
        if [ -d "$wsdirinit/$initphdir" ]; then
            estep "Le répertoire est déjà présent"
            fixinitph=
        elif [ -f "$wsdirinit/$initphname" ]; then
            estep "Le fichier est présent"
            initph="$wsdirinit/$initphname"
        elif [ -n "$initph" ]; then
            copy_any "$initph" "$wsdirinit" || die
            initph="$wsdirinit/$initphname"
        else
            initph="$wsdirinit/$initphname"
            download_shared "/RDD/rdd-tools-pivot/$initphname" "$initph" || die
        fi
        if [ -n "$fixinitph" ]; then
            if [ -f "$initph" ]; then
                estep "Extraction de l'archive"
                mkdir -p "$fichiers_transco" || die
                unzip -q -j "$initph" -d "$fichiers_transco" || die
                mkdir -p "$wsdirinit/$initphdir"

                #estep "Suppression de l'archive source"
                #rm "$initph" || die
            fi
        fi
        eend
    fi

    estep "Mise à jour des variables"
    WSNAME="${wsdir%.works}"
    RDDTOOLS_VERSION="$rddtools_version"
    MYPEGASE_VERSION="$mypegase_version"
    PIVOTBDD_VERSION="$pivotbdd_version"
    merge_vars "$RDDMGR/$wsdir"

    estep "Mise à jour de la liste des serveurs"
    update-pgadmin

    #estep "Démarrage de la base pivot"
    "$RDDMGR/$wsdir/rddtools" -r

    enote "Vous pouvez maintenant aller dans l'espace de travail et commencer à utiliser rddtools
    cd $wsdir
    ./rddtools"
}

function delete_workspace() {
    local wsdir showwarn
    for wsdir in "$@"; do
        setx wsdir=abspath "$wsdir"
        [ "${wsdir#$RDDMGR/}" != "$wsdir" ] || die "$wsdir: l'espace de travail doit être dans le répertoire rddmgr"
        setx wsdirname=basename "$wsdir"
        [[ "$wsdirname" == *.works ]] || die "$wsdirname: n'est pas un espace de travail"
        [ -d "$wsdir" ] || die "$wsdirname: espace de travail non trouvé"

        ask_yesno "Etes-vous certain de vouloir supprimer $wsdirname?" || continue
        if [ -z "$showwarn" ]; then
            eimportant "La suppression des espaces de travail est uniquement manuelle"
            showwarn=1
        fi
        einfo "Si vous êtes CERTAIN que l'espace de travail ne contient plus de données à sauvegarder,
- assurez-vous que rddweb ne tourne pas dans cet espace de travail
    $(qvals "./$wsdirname/rddtools" -k)
- puis vous pouvez le supprimer avec une commande comme celle-ci:
    $(qvals sudo rm -rf $wsdirname)
- puis mettez à jour la configuration
    $(qvals ./lib/sbin/update-pgadmin -r)"
    done
}

function set_default_workspace() {
    local default; local -a wsdirs
    if [ -d "$RDDMGR/default.works" -a -L "$RDDMGR/default.works" ]; then
        setx default=readlink "$RDDMGR/default.works"
    else
        setx -a wsdirs=ls_dirs "$RDDMGR" "*.works"
        default="${wsdirs[0]}"
        if [ -n "$default" ]; then
            enote "Autosélection de $default comme espace de travail par défaut"
            ln -s "$default" "$RDDMGR/default.works"
        fi
    fi
    upvar default "$default"
}

function _set_services() {
    for service in "$@"; do
        setx service=basename "$service"
        auto=
        case "$service" in
        traefik|traefik.service) traefik=1;;
        pgadmin|pgadmin.service) pgadmin=1;;
        default|default.works) default=1;;
        *)
            service="${service%.works}.works"
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
    local auto=1 service traefik pgadmin default
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
        set_default_workspace
        if [ -n "$default" ]; then
            "$RDDMGR/$default/rddtools" -s || die
        elif [ -n "$auto" ]; then
            echo_no_workspaces
        fi
    fi

    for service in "${services[@]}"; do
        "$RDDMGR/$service/rddtools" -s || die
    done
}

function stop_services() {
    local auto=1 service traefik pgadmin default
    local -a services; _set_services "$@"

    for service in "${services[@]}"; do
        "$RDDMGR/$service/rddtools" -s || die
    done

    if [ -n "$default" ]; then
        set_default_workspace
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
    stop_services "$@"
    start_services "$@"
}

################################################################################
# fonctions rddtools
################################################################################

function start_pivotbdd() {
    cd "$WSDIR"
    if dcrunning rddtools.docker-compose.yml; then
        enote "la base pivot est démarrée"
    else
        estep "Démarrage de la base pivot"
        docker compose -f rddtools.docker-compose.yml up ${BuildBefore:+--build} -d --wait || die
    fi
}

function stop_pivotbdd() {
    cd "$WSDIR"
    if dcrunning rddtools.docker-compose.yml; then
        estep "Arrêt de le base pivot"
        docker compose -f rddtools.docker-compose.yml down || die
    fi
}

function restart_pivotbdd() {
    stop_pivotbdd "$@"
    start_pivotbdd "$@"
}

function ensure_system_ymls() {
    if [ -f "$WSDIR/config/pegase.yml" ]; then
        pegase_yml="$WSDIR/config/pegase.yml"
    elif [ -f "$RDDMGR/config/pegase.yml" ]; then
        pegase_yml="$RDDMGR/config/pegase.yml"
    else
        die "le fichier config/pegase.yml est requis"
    fi
    if [ -f "$WSDIR/config/sources.yml" ]; then
        sources_yml="$WSDIR/config/sources.yml"
    elif [ -f "$RDDMGR/config/sources.yml" ]; then
        sources_yml="$RDDMGR/config/sources.yml"
    else
        die "le fichier config/sources.yml est requis"
    fi
}
function ensure_user_env() {
    mkdir -p "$WSDIR/envs"

    local previous
    if [ -L "$WSDIR/current.env" ]; then
        previous="$(readlink "$WSDIR/current.env")"
        previous="${previous#envs/}"
        if [ -f "$WSDIR/current.env" ]; then
            eval "$(cat "$WSDIR/current.env" | grep '^_rddtools_' | sed 's/^_rddtools_//')"
        fi
    fi
    [ -n "$Envname" ] || Envname="$previous"

    if [ -z "$Envname" ]; then
        ewarn "Aucun environnement n'est défini ou sélectionné"
        Envname=default
    fi
    Envname="${Envname%.env}.env"

    if [ ! -f "$WSDIR/envs/$Envname" ]; then
        ask_yesno "L'environnement $Envname n'existe pas. Voulez-vous le créer?" O || die
        eval "$(dump-config.py "$pegase_yml" "$sources_yml" -l --local-vars)"

        [ -n "$instance" ] || instance="${instances[0]}"
        simple_menu instance instances -t "Choix de l'instance" -m "Veuillez choisir l'instance attaquée pour les injections"

        sources+=("pas de source")
        [ "$source" == none ] && source="pas de source"
        simple_menu source sources -t "Choix de la source" -m "Veuillez choisir la source des données pour les déversements"
        [ "$source" == "pas de source" ] && source=none

        if [ "$source" != none ]; then
            source_profiles="${source}_profiles[@]"; source_profiles=("${!source_profiles}")
            [ -n "$source_profile" ] || source_profile="${source_profiles[0]}"
            simple_menu source_profile source_profiles -t "Choix du profil" -m "Veuillez choisir le profil de la source de données"
        else
            source_profile=
        fi

        echo >"$WSDIR/envs/$Envname" "\
# Ces paramètres servent à sélectionner la source des données pour les
# déversements, ainsi que l'instance de PEGASE pour les injections
_rddtools_instance=$instance
_rddtools_source=$source
_rddtools_source_profile=$source_profile

# Modifier les paramètres à partir d'ici"
    fi

    user_env="$WSDIR/envs/$Envname"
    [ -f "$user_env" ] || die "$Envname: environnemnt invalide"

    # rendre courant l'environnement sélectionné
    if [ "$Envname" != "$previous" ]; then
        enote "Sélection de l'environnement $Envname"
        ln -sfT "envs/$Envname" "$WSDIR/current.env"
    fi

    eval "$(cat "$user_env" | grep '^_rddtools_' | sed 's/^_rddtools_//')"
}

function run_rddtools() {
    local pegase_yml sources_yml
    ensure_system_ymls

    local mypegase_env system_env user_env instance source source_profile
    ensure_user_env

    mypegase_env="$WSDIR/init/mypegase_$MYPEGASE_VERSION.env"
    [ -f "$mypegase_env" ] || die "Le fichier ${mypegase_env#$WSDIR/} est requis"

    system_env="$WSDIR/envs/.$Envname"
    if should_update "$system_env" "$pegase_yml" "$sources_yml" "$WSDIR/.env"; then
        dump-config.py \
            -s "$instance" \
            -d "$source" -p "$source_profile" \
            "$pegase_yml" "$sources_yml" "$WSDIR/.env" >"$system_env"
    fi

    local -a run
    # arguments de base
    run=(run -it --rm --net "$DBNET")
    # environnements
    run+=(--env-file "$mypegase_env" --env-file "$system_env" --env-file "$user_env")
    [ -n "$Debug" ] && run+=(-e debug_job=O)
    # points de montage
    local filesdir="$RDDMGR/$FICHIERS_TRANSCO"
    local scriptxsdir="$RDDMGR/$SCRIPTS_EXTERNES"
    local backupsdir="$RDDMGR/backups"
    mkdir -p "$backupsdir"; chmod 775 "$backupsdir"
    local logsdir="$WSDIR/logs/$(date +%Y%m%dT%H%M%S)"
    mkdir -p "$logsdir"; chmod 775 "$logsdir"

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
        enote "Les logs sont dans le répertoire ${logsdir#$WSDIR/} (code de retour $r)"
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
function echo_no_workspaces() {
    ewarn "Il n'y a pas d'espace de travail pour le moment. Utilisez rddmgr --create pour en créer un"
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

    local file="$1" dest="$2" work="$dest.dl$$"
    local dir="$(dirname "$file")"
    local url="$SHARED_URL/files/?p=${file//\//%2F}&dl=1"
    local referer="$SHARED_URL/?p=${dir//\//%2F}&mode=list"

    estep "Téléchargement de $file --> $(dirname "$dest")/"
    curl -fsSL -e "$referer" "$url" -o "$work" || return 1

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
    local version="$1" tmp major minor patch devxx
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
    upvars version "$version" devxx ""
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
    local version="$1" tmp devxx
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    upvars version "${tmp#[Vv]}.0.0" devxx ""
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
    local version="$1" tmp devxx
    tmp="$version"
    [ -n "$2" ] && tmp="${tmp#$2}"
    [ -n "$3" ] && tmp="${tmp%$3}"

    upvars version "$tmp" devxx "${tmp#0.1.0-dev.}"
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
s/@@WSNAME@@/$WSNAME/g
s/@@RDDTOOLS_IMAGE@@/${RDDTOOLS_IMAGE//\//\\\/}/g
s/@@RDDTOOLS_VERSION@@/$RDDTOOLS_VERSION/g
s/@@MYPEGASE_VERSION@@/$MYPEGASE_VERSION/g
s/@@PIVOTBDD_VERSION@@/$PIVOTBDD_VERSION/g
" $(find "$1" -name private -prune -or -type f -print)
}
