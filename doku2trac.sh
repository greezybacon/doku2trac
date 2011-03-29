#!/bin/bash
#
# Simple script to convert DokuWiki documentation into Trac format,
# optionally using tracadmin to import it into trac or even to 
# import it into the database directly
#
VERSION="1.0"

# Set Defaults
DOKUPATH=$(pwd -P)
PAGENAMES="CamelCase"
PAGEPREFIX=""

# Load plugins
PLUGINS=""
for plugin in plugins/*; do
    source $plugin
done
PLUGINS=(${PLUGINS})

usage() {
	cat <<EOF
DokuWiki -> Trac converter, version ${VERSION}
circa 2009, Jared Hancock

Converts DokuWiki documentation into trac format, optionally importing
it directly into trac.

Usage:
$(basename $0) [options] [DokuWikiPage] 

Options:
    -A, --all           Capture all editions of the page
    -d, --doku-path     Path of DokuWiki installation. Defaults 
                        to '${DOKUPATH}'
    -S, --sql           Generate SQL statements to import directly into Trac
                        database. This option is necessary if you intend to 
                        capture the modification times, user names, and commit
                        comments logged in DokuWiki.
    -f, --files [/path/to/output]
                        Create files for wiki pages (multiple per page if
                        used with the --all feature. Optionally you can
                        specify an output location to place the output
                        wiki page files. The path will be created by this
                        conversion script upon your confirmation
                        NOTE: This feature cannot be used with the 'CamelPath'
                              --page-names option.
    -h, --help          Show this help message
    -l, --log           Log output to file as well as STDERR
    -m, --meta-data     Capture meta-data of the pages. This options is
                        only used with the --database option and will insert
                        usernames, IP addresses, and comments of page
                        modifications into the database
    -r, --recursive     Convert all DokuWiki pages
    -t, --trac-admin <path>
                        Use trac-admin to import wiki page(s). Specify the
                        path to be passed to trac-admin as the project
                        location to import into

    --exclude <pattern>
                        Exclude pages matching the named pattern. For 
                        instance, to exclude shipped DokuWiki pages, use
                        --exclude wiki* --exclude playground*
    --page-name-prefix <prefix>
                        Prefix to attach to all converted pages. Therefore
                        'Start' would become 'PrefixStart' for instance.
                        NOTE: This should be capitalized, but not required
    --page-names <type> Conversion technique for DokuWiki pagenames into
                        Trac page names. Default is '${PAGENAMES}'
                        CamelCase - Treat '/', ':', '_', '-', and ' ' as name 
                            separators. They will be removed and the 
                            following character capitalized
                        CamelPath - Replace Doku ':' namespace separator with
                            '/', and treat '_', '-', and ' ' as name
                            separators which will be removed and the following
                            character capitalized
    --sql-delete        When generating SQL output (--sql), issue delete
                        statements to remove all versions of the page currently
                        in the database before issuing new insert statements
                        for the imported version(s)
EOF
# Get plugin help
for plugin in ${PLUGINS[@]}; do ${plugin}_help; done
exit 0
}

indent() {
    INDENT="$INDENT   "
}
outdent() {
    INDENT="${INDENT:3:${#INDENT}}"
}
info() {
    if [[ $LOG ]]; then
        echo "$INDENT>> $*" | tee -a $LOG >&2
    else
        echo "$INDENT>> $*" >&2
    fi    
}

# Parse Options
while [[ -n $1 ]]; do
    # TODO: Separate --option=val into two options
    if [[ ${1:0:2} == "--" ]]; then
        ARG=${1%=*}; VAL=${1#*=}
        if [[ $ARG != $VAL ]]; then
            shift
            set - $ARG $VAL "$@"
        fi
    fi
	case $1 in
        -A|--all)               EDITIONS=1;;
        -d|--doku-path)         shift; DOKUPATH=$1;;
        -S|--sql)               SQL=1;;
        -f|--files)             FILES=1; 
            # Capture output path if specified
            if [[ ${2:0:1} != "-" ]]; then shift; OUTPUT_PATH=$1; fi;;
        -t|--trac-admin)        shift; TRACADMIN=$1;;
		-h|--help)				usage;;
        -m|--meta-data)         METADATA=1;;
        -r|--recursive)         RECURSE=1;;
        -v|--verbose)           VERBOSE=1;;
        -l|--log)               shift; LOG=$1;;

        --exclude)              shift; EXCLUDE[${#EXCLUDE[@]}]=${1//%/*};;
        --page-names)           shift; PAGENAMES=$1;;
        --page-name-prefix)     shift; PAGEPREFIX=$1;;
        --sql-delete)           SQLDELETE=1;;
        -*)     
                valid=1
                for plugin in ${PLUGINS[@]}; do
                    ${plugin}_handle_options $1 $2
                    status=$?
                    [[ $status == 2 ]] && shift
                    if [[ $status != 1 ]]; then valid=0; break; fi
                done
                if [[ $valid != 0 ]]; then
                    info "Error: $1: Invalid option specified"
                    exit -1
                fi;;
        *)
            [[ -n $VERBOSE ]] && info "Adding page '$1'"
            PAGES[$((${#PAGES[@]}+1))]=$1
	esac
	shift
done

isExcluded() {
    for pattern in "${EXCLUDE[@]}"; do
        [[ -z ${1##${pattern}} ]] && { set +f; return 0; }
    done
    set +f; return 1
}

# Arguments:
# $1 - Folder to traverse into
# $2 - Current namespace
#
enterFolder() {
    if [[ -n $1 ]]; then
        if isExcluded ${2:+$2:}$1; then
            [[ $VERBOSE == 1 ]] && info "Excluding $1"
            return
        fi
        if [[ ! -d "$1" ]]; then
            if [[ -f "$1" && -r "$1" ]]; then
                handleFile "$1" "$2"
                return
            fi
            info "Error: Namespace $1 does not exist"
            exit -1
        fi
        pushd . > /dev/null
        [[ $VERBOSE == 1 ]] && info "Entering $1"
        indent
        cd $1
    fi
    for page in *; do
        if [[ -d $page ]]; then
            if [[ -n $2 ]]; then
                enterFolder "$page" "$2:$page"
            else
                enterFolder "$page" "$page"
            fi
        elif [[ -f $page ]]; then
            # handleFile with no extension
            [[ $VERBOSE == 1 ]] && info "Converting page ${page%.*}"
            handleFile "${page%.*}" "$2"
        fi
    done
    if [[ -n $1 ]]; then
        popd > /dev/null
        [[ $VERBOSE == 1 ]] && info "Leaving $1"
        outdent
    fi
}

# Arguments:
# $1 - File to be handled
# $2 - Current namespace (with colons)
handleFile() {
    if [[ -n $2 ]]; then
        FQPN="$2:$1"
    else
        FQPN=$1
    fi
    if isExcluded $FQPN; then
        [[ $VERBOSE == 1 ]] && info "Excluding $FQPN"
        return
    fi
    # Change : to / and that's the relative path to the page
    PAGEPATH=$( echo $FQPN | sed -e "s~:~/~g" )
    # Remove the page from the FQPN and that's the namespace (might
    # be empty)
    NAMESPACE=${FQPN%*:*}
    local -i VERSION=1
    # TODO: Emit DELETE statement if required
    [[ $SQL == 1 && $SQLDELETE == 1 ]] && \
        printf "delete from wiki where name='%s';\n" "$(tracPageName "${FQPN}")"
    # Lookup all the editions from metadata
    CHANGES=${DOKUPATH}/data/meta/${PAGEPATH}.changes
    if [[ $EDITIONS == 1 ]]; then
        indent
        VERSIONS=$( cat $CHANGES | sed -e "s/\\t/;/g" )
        [[ -z $VERSIONS ]] && return 1
        # Iterate through changes
        { local IFS=$'\n'; for V in $VERSIONS; do
            # Convert to array
            # [0]-Modification time, [1]-IP address, 
            # [2]-Mode (C-Created, E-Major edit, e-Minor edit)
            # [2]-*REPLACE* Version number for Trac direct database import
            # [3]-Pagename, [4]-Username, [5]-Comment
            local IFS=";"; V=($V)
            V[2]=$VERSION
            let VERSION++
            if [[ $VERBOSE == 1 ]]; then
                IFS=" " info $(date -d "1970-01-01 UTC + ${V[0]} seconds" +"%F %T") \
                "${V[4]}" "${V[5]:+- }${V[@]:5}"
                indent
            fi
            output "$(tracize "${DOKUPATH}/data/attic/${PAGEPATH}.${V[0]}.txt.gz" \
                    $NAMESPACE)" \
                "$(tracPageName "${FQPN}")" \
                "$V"
            [[ $VERBOSE == 1 ]] && outdent
        done }
        outdent
    fi
    # Handle current version 
    # TODO: Fetch modification time for METADATA
    if [[ -r $CHANGES ]]; then
        local IFS=";"; V=($( tail -1 $CHANGES | sed -e "s/\\t/;/g" ))
    else
        # No changes every made. Infer modification time for file timestamp
        V=($(stat --printf=%Y "${DOKUPATH}/data/pages/${PAGEPATH}.txt"))
    fi
    V[2]=$VERSION
    output "$(tracize "${DOKUPATH}/data/pages/${PAGEPATH}.txt" $NAMESPACE)" \
        "$(tracPageName "${FQPN}")" \
        "$V"
}

# Compile extra plugin SED code
PLUGIN_SED=$(
    for plugin in ${PLUGINS[@]}; do
        ${plugin}_tracize 2> /dev/null
    done
)
    
# Arguments:
# $1 - Filename of file to be converted (/dev/stdin for STDIN)
# [$2] - Current Doku namespace
tracize() {
    # Don't bother with non-existent or unreadable files
    [[ ! -r $1 ]] && return -1
    # Compile a list of plugins that define postconvert()
    local postconverters=()
    for plugin in ${PLUGINS[@]}; do
        if [[ $(type -t "${plugin}_postconvert") == "function" ]]; then
            postconverters[${#postconverters}]=${plugin}
        fi
    done
    { 
        # Call preconvert() of all plugins
        for plugin in ${PLUGINS[@]}; do ${plugin}_preconvert; done
        if [[ "${1: -3:3}" == ".gz" ]]; then gzip -dc "$1"; else cat "$1"; fi; 
        # Add trailing newline for bottom ( while read line ) section to
        # detect the last line properly
        echo; 
    } | sed -nr "
        # Non wiki markup sections
        # Handle inline code, file, and html blocks. 
        # XXX: Continuing will cause format conversion to happen for 
        #      the contained content
        s/<(code|file|html)>([^<]+)<\/\1>/\n{{{\n\2\n}}}\n/g; t continue
        s/<(code|file|html)( [^>]+)>([^<]+)<\/\1>/\n{{{\n#!\2\n\3\n}}}\n/g; t continue
        
        # Skip down to the close section and skip any further transformations
        /<(html|nowiki)>/,/<\/(html|nowiki)>/ {
            s:<nowiki>:{{{\n#!span:
            # HTML sections
            s/<html>/{{{\n#!html/g
            /<\/nowiki>|<\/html>/ {
                s:</(nowiki|html)>:}}}:
                p; b
            }
        }
        # XXX: This does not handle <nowiki> blocks because I have not
        #      found an equivalent for Trac

        /<code( [^>]+)?>/,/<\/code>/ {
            # Handle inline <code> blocks
            s:</code>([^ ]+|$):\n}}}\n\1:
            s/((^|\n)\s*\S.*)<code>/\1\n{{{\n/
            s/((^|\n)\s*\S.*)<code ([^>]+)>/\1\n{{{\n#!\3\n/; t continue

            s/<code>/{{{/
            s/<code ([^>]+)>/{{{\n#!\1/
            #s:</code>:}}}:
            p; b
        }
        /<file( [^>]+)?>/,/<\/file>/ {
            # Handle inline <file> blocks
            s:</file>([^ ]+|$):\n}}}\n\1:
            s/((^|\n)\s*\S.*)<file>/\1\n{{{\n/
            s/((^|\n)\s*\S.*)<file ([^>]+)>/\1\n{{{\n#!\3\n/; t continue

            s/^<file>/{{{/
            s/<file ([^>]+)>/{{{\n#!\1/
            s:</file>:}}}: 
            # bash is sh in trac
            s/(^|\n)#!bash/#!sh/
            p; b
        }

        # Lines indented 2 spaces should become {{{ blocks (watch out
        # for lists!). 
        /^  +[^ *-]/ {
            # First one gets {{{
            i \{\{\{
            :loop
            /^  +[^ *-]/ { s/^  //; p; n; b loop; }
            # Prepend }}} before following lines
            i \}\}\}
        }
        # ! is special in Trac, so make sure there is a space or
        # end-of-line after '!' characters
        s/!([^ !])/! \1/g
    
        :continue
        # NOTE: Hereafter, the buffer may contain multiple lines, in which
        #       case ^ will only match the very beginning of the buffer, 
        #       and \n will match second and subsequent lines

        # bash is sh in Trac
        s/(^|\n)#!bash/\1#!sh/
    
        # bold, italics, monospace, strikethrough
        # XXX: These don't match if the section spans a newline
        s/''(([^']|'[^'])+)''/\`\1\`/g
        # Handle leading '*' to indicate unordered list
        s/\*\*([^*]([^*]|[*][^*])*)\*\*/'''\1'''/g
        s://(([^/]|[/][^/])+)//:''\1'':g
        s:<del>|</del>:~~:g

        # Headers -- Handle unbalanced '=' counts, since Doku accepts
        #   unbalaced but Trac does not. Consider the count on the left
        s/(^|\n)( )*=([^=]+)=+/\2~~!H5~~ \3 ~~!H5~~/
        s/(^|\n)( )*==([^=]+)=+/\2~~!H5~~ \3 ~~!H5~~/
        s/(^|\n)( )*===([^=]+)=+/\2~~!H4~~ \3 ~~!H4~~/
        s/(^|\n)( )*====([^=]+)=+/\2~~!H3~~ \3 ~~!H3~~/
        s/(^|\n)( )*=====([^=]+)=+/\2~~!H2~~ \3 ~~!H2~~/
        s/(^|\n)( )*======([^=]+)=+/\2~~!H1~~ \3 ~~!H1~~/
        s/~~!H1~~/=/g
        s/~~!H2~~/==/g
        s/~~!H3~~/===/g
        s/~~!H4~~/====/g
        s/~~!H5~~/=====/g

        # Numbered lists (Doku doesn't require a space after '-', but
        #   Trac does)
        s/(^|\n)( +)- ?( *)/\21. \3/
        # Unordered lists
        s/(^|\n)( +)\* ?( *)/\2* \3/

        # Superscript and subscript
        s:<sup>|</sup>:^:g
        s:<sub>|</sub>:,,:g

        # Links
        ## HTTP URL link
        s~\[\[(https?://[^]|]+)\]\]~[\1]~g
        ## HTTP URL link + Display Name
        s~\[\[(https?://[^]|]+)[ ]*[ |]+([^]]+)\]\]~[\1 \2]~g
        ## UNC reference -- Requires http://tinyurl.com/4xg9c for Firefox
        s~\[\[\\\\\\\\([^]|]+)\]\]~[file:///%5C%5C\1]~g
        ## UNC reference + Display Name
        s~\[\[\\\\\\\\([^]|]+)[ ]*[ |]+([^]]+)\]\]~[file:///%5C%5C\1 \2]~g
        ## WikiPage? + Anchor? + Display Name
        ## NOTE: Anchor names should be leading capital
        s~\[\[([^]|#]+)?(\#[^|]+)?[ |]+([^]|]+)\]\]~[:TracPageLink(\1\2) \3]~g
        ## WikiPage? + Anchor? 
        s~\[\[([^]|#]+)?(\#[^|]+)?\]\]~[:TracPageLink(\1\2)]~g

        # Tables (require | or ^ to be the first non-whitespace character 
        #         on the line)
        / *[|^]/ {
            ## Table Headers (except for ending) -- standard cell + bold 
            s/\^( *[^^|]+ *)/~~CELL~~'''\1'''/g
            ## Standard cells
            s/\|( *[^|]+ *)/~~CELL~~\1/g
            ## Spanned cells
            s/[|^] *[^|] */~~CELL~~ ~~CELL~~ /g
            ## Ending ^
            s/[|^] *$/~~CELL~~/
            s/~~CELL~~/||/g
        }
 
        # Line breaks (Dont match UNC prefix)
        s/\\\\\\\\( |$)/[[BR]]\1/g

        # Perform extra plugin sed magic
        $PLUGIN_SED

        # Footnotes (Supported through FootNoteMacro 
        # http://trac-hacks.org/wiki/FootNoteMacro)
        s/\(\((([^)]|\)[^)])+)\)\)/[[FootNote\(\1\)]]/g

        # Trac macros added in already (like TOC)
        s/:TracMacro\(([^)]+)\)/[[\1]]/g
        
        # CamelCase words should have a preceeding !
        s/(^|[^[#:0-9A-Za-z])([A-Z]+[a-z]+[A-Z]+[a-z])/\1!\2/g

        p
        " | ( while IFS=$'\n' read -r line; do
            # Don't do path expansion (globbing) in here
            set -f
            # TODO: Convert page links 
            while [[ "$line" =~ ":TracPageLink(" ]]; do
                LINK=${line#*:TracPageLink(}; LINK=${LINK%%)*}
                # Don't interpret escape sequences
                OLD=${LINK//\\/\\\\}
                # If link does not contain a ':', place it in the
                # current Doku namepsace ($2). Ok if it's a reference
                # to an anchor on this page
                if [[ ${LINK:0:1} == "#" ]]; then
                    line=${line/:TracPageLink($LINK)/$(\
                        PAGEPREFIX="" PAGENAMES="CamelCase" \
                        tracPageName "$LINK")}
                else
                    [[ ! $LINK =~ ":" ]] && LINK="$2:$LINK"
                    line=${line/:TracPageLink($OLD)/wiki:$(\
                        tracPageName "$LINK")}
                fi
            done
            for plugin in ${postconverters[@]}; do
                returned=$(${plugin}_postconvert $line)
                line=${returned:-${line}}
            done
            echo "$line"
        done )
}

# Arguments:
# $1 - DokuWiki page name with prefixxed namespace
#
tracPageName() {
    case $PAGENAMES in
        CamelCase)
            # (1) Convert leading character to uppercase
            # (2) Convert -, :, ' ', and _ to camelcase
            echo ${PAGEPREFIX}$(echo $1 | sed -re "s/^(.)/\U\1/" \
                -e "s/[:_ -]+(.)/\U\1/g");;
        CamelPath)
            # (1) Convert leading character to uppercase
            # (2) Convert : to / and capitalize following char
            # (3) Convert -, _ and ' ' to camelcase
            echo ${PAGEPREFIX:+${PAGEPREFIX}/}$(echo $1 | \
                sed -re "s/^(.)/\U\1/" -e "s/:+(.)/\/\U\1/g" \
                    -e "s/[_ -]+(.)/\U\1/g");;
        *)
            # Leave pagename alone
            echo $1
    esac
}

# Arguments:
# $@ - Array
_args_to_list() {
    {
        while [[ -n $1 ]]; do
            # Escape single quotes and backslashes
            echo -n "${1}"
            [[ -n $2 ]] &&  echo -n "!~S~!"
            shift
        done
    } | sed -e "s:':'':g" -e 's:\\:\\\\:g' -e "s:!~S~!:${SEP:-,}:g"
}

# Arguments:
# $1 -   Tracized page content
# $2 -   Trac pagename
# [$3] - DokuWiki page version information
#
output() {
    # Don't output empty pages
    [[ -z $1 ]] && return -1
    V="$3"
    if [[ $SQL == 1 ]]; then
        # Basic fields
        local VERSION=1
        local FIELDS=("name" "version" "text")
        local VALUES=("$2" ${V[2]} "$1")
        if [[ $METADATA == 1 && ${#V[*]} -gt 0 ]]; then
            [[ -n ${V[0]} ]] && { FIELDS[3]="time"; VALUES[3]="${V[0]}"; }
            [[ -n ${V[1]} ]] && { FIELDS[4]="ipnr"; VALUES[4]="${V[1]}"; }
            [[ -n ${V[4]} ]] && { FIELDS[5]="author"; VALUES[5]="${V[4]}"; }
            [[ -n ${V[5]} ]] && { FIELDS[6]="comment"; VALUES[6]="${V[@]:5}"; }
        fi
        printf "insert into wiki (%s) values ('%s');\n" \
            "$(_args_to_list "${FIELDS[@]}")" \
            "$(SEP="', '" _args_to_list "${VALUES[@]}")"

    elif [[ -n $TRACADMIN ]]; then
        # Trac admin doesn't support importing from standard in yet,
        # so create a temporary file
        TEMPFILE=/tmp/$(basename $0)$RANDOM.txt
        echo "$1" > $TEMPFILE
        trac-admin "$TRACADMIN" wiki import "$2" $TEMPFILE
        rm $TEMPFILE
    else
        if [[ -n $OUTPUT_PATH ]]; then
            # Create file for output
            if [[ $EDITIONS && $# -gt 2 ]]; then
                __OUT_FILE="$OUTPUT_PATH/$2.${V[0]}"
            else
                __OUT_FILE="$OUTPUT_PATH/$2"
            fi
        else
            __OUT_FILE=/dev/stdout
        fi
        # Send to __OUT_FILE
        { 
            [[ $__OUT_FILE == "/dev/stdout" ]] && echo "---- Begin Trac Page ----"
            if [[ $METADATA ]]; then
                if [[ ${#V[*]} -gt 0 ]]; then
                    [[ ${V[3]} ]] && echo "Doku-Page: ${V[3]}"
                    echo "Modified: $(date -d "1970-01-01 UTC + ${V[0]} seconds")"
                    [[ ${V[4]} ]] && echo "Modified-By: ${V[4]} @ (${V[1]})"
                    [[ ${V[5]} ]] && echo "Comment: ${V[@]:5}"
                fi
                [[ -n $2 ]] && { echo "Trac-Page: $2"; }
                [[ -n ${V[2]} ]] && { echo "Trac-Version: ${V[2]}"; echo; }
            fi
            echo "$1"
            [[ $__OUT_FILE == "/dev/stdout" ]] && echo "---- End Trac Page ----"
        } > "$__OUT_FILE"
    fi
}

# Validate options
## Create output location
if [[ $FILES == 1 ]]; then
    # Convert OUTPUT_PATH to be absolute
    [[ ${OUTPUT_PATH:0:1} != "/" ]] && OUTPUT_PATH=$(pwd -P)/$OUTPUT_PATH
    if [[ -n $OUTPUT_PATH && ! -d $OUTPUT_PATH ]]; then
        echo -n "$OUTPUT_PATH does not exist. Create it? " >&2
        read action
        case ${action:0:1} in
            y|Y)            mkdir -p $OUTPUT_PATH;;
            *)              exit -1;;
        esac
    fi
    if [[ ! -r $OUTPUT_PATH ]]; then
        info "Error: Unable to access $OUTPUT_PATH"
        exit -1
    fi
    # Cannot output files with CamelPath pagename converter
    if [[ $PAGENAMES == "CamelPath" ]]; then
        info "Error: File output cannot be used with CamelPath page name " \
            "conversion"
        exit -1
    fi
## Fetch Trac version for SQL output
elif [[ $SQL == 1 ]]; then
    # Detect Trac version. 
    # XXX: Assume that the trac-admin in the current path is the
    #      one that is used to manage the target Trac path
    VERSION=$(trac-admin --version 2>/dev/null); 
    VERSION=${VERSION##trac-admin }
    if [[ "x$VERSION" == "x" ]]; then
        # Unable to detect Trac version
        echo -n "Which Trac version are you importing into? " >&2
        read VERSION
    else
        echo -n "Which Trac version are you importing into? [$VERSION] " >&2
        read VERSION2
        [[ -n $VERSION2 ]] && VERSION=$VERSION2
        #
        # Detect supported version
        case $VERSION in
            0.11*)      
                [[ $VERBOSE == 1 ]] && info "Using Trac version $VERSION";;
            *)          
                info "Warning: Trac version $VERSION is untested!\n" \
                     "    This script is tested with Trac installs up to\n " \
                     "    version 0.11*. If you are sure your Trac database\n " \
                     "    is compatible with a specific version up to 0.11, \n" \
                     "    fake this scipt out and use that version"
                exit -1;;
        esac
    fi
fi
## Remove trailing slash from page-name-prefix
if [[ $PAGENAMES == "CamelPath" && $PAGEPREFIX ]]; then
    # Pageprefix shouldn't end in slash
    if [[ ${PAGEPREFIX: -1:1} == "/" ]]; then
        info "Warning: Removing trailing slash from Page-Name-Prefix $PAGEPREFIX"
        PAGEPREFIX=${PAGEPREFIX%*/}
    fi
fi
## Log file
if [[ $LOG ]]; then
## Log file must be writeable
    if [[ ! -w $LOG ]]; then
        info "Error: $LOG: Not writeable"
        exit -1
## Log file path must be absolute
    elif [[ ${LOG:0:1} != "/" ]]; then
        LOG=$(pwd -P)/"$LOG"
    fi
fi

# Start converting
if [[ ${#PAGES[@]} -gt 0 ]]; then
    for P in ${PAGES[*]}; do
        [[ $VERBOSE ]] && info "Processing page '$P'"
        if [[ $RECURSE ]]; then
            pushd . > /dev/null
            [[ $VERBOSE ]] && info "Entering ${DOKUPATH}/data/pages"
            cd "${DOKUPATH}/data/pages"
            # Assume starting location is the namespace
            enterFolder $( echo "$P" | sed -e "s~:~/~g" ) "$P"
            popd > /dev/null
        else
            handleFile ${P}
        fi
    done
elif [[ $RECURSE ]]; then
    pushd . > /dev/null
    cd "${DOKUPATH}/data/pages"
    enterFolder
    popd > /dev/null
else
    # Convert from standard in
    tracize /dev/stdin
fi

#:vim:se ft=bash tabstop=8 noexpandtab:
