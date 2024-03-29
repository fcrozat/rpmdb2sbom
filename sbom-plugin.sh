#!/bin/bash
#
# This plugin create a CycloneDX SBOM corresponding to RPM db
#
# to be installed in /usr/lib/zypp/plugins/commit/
#

DEBUG="false"

RPMDIR=${TRANSACTIONAL_UPDATE_ROOT}$(rpm --eval "%_dbpath")
SCRIPTNAME="$(basename "$0")"

cleanup() {
    test -n "$tmpdir" -a -d "$tmpdir" && execute rm -rf "$tmpdir"
}

trap cleanup EXIT

tmpdir=$(mktemp -d /tmp/sbom-libzypp-plugin.XXXXXX)

log() {
    logger -p info -t $SCRIPTNAME --id=$$ "$@"
}

debug() {
    $DEBUG && log "$@"
}

respond() {
    debug "<< [$1]"
    echo -ne "$1\n\n\x00"
}

execute() {
    debug -- "Executing: $@"

    $@ 2> $tmpdir/cmd-output
    ret=$?

    if $DEBUG; then
        if test $ret -ne 0; then
            log -- "Command failed, output follows:"
            log -f $tmpdir/cmd-output
            log -- "End output"
        else
            log -- "Command succeeded"
        fi
    fi
    return $ret
}

sbom_generate() {
source /etc/os-release

cat << EOF > $tmpdir/db.json 
{
   "bomFormat" : "CycloneDX",
   "specVersion" : "1.5",
   "serialNumber" : "urn:uuid:c7dbc0d8-bcba-5946-aec2-0be72a6f5f3d",
   "version" : 1,
   "metadata" : {
      "timestamp" : "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
      "tools" : [
         {
            "name" : "sbom-libzypp-plugin",
            "version" : "0.1"
         }
      ]
   },
   "components": [

EOF

rpm -qa --queryformat '\t{\n\t\t"bom-ref": "pkg:%{NAME}-%{SIGMD5}",\n\t\t"type": "library",\n\t\t"name": "%{NAME}",\n\t\t"version": "%{VERSION}-%{RELEASE}",\n\t\t"purl": "pkg:rpm/%{VENDOR}/%{NAME}@%{VERSION}-%{RELEASE}&arch=%{ARCH}&upstream=%{SOURCERPM}&distro=@@ID@@-@@VERSION_ID@@",\n\t\t"licenses" : \[\n\t\t\t{\n\t\t\t"expression" : "%{LICENSE}"\n\t\t\t\n\t\t\t\}\n\t\t\],\n\t\t"publisher":"%{VENDOR}"\n\t\},\n' >> $tmpdir/db.json
sed -i -e 's,rpm/openSUSE/,rpm/opensuse/,g' -e "s,@@ID@@,$ID,g" -e "s,@@VERSION_ID@@,$VERSION_ID,g" $tmpdir/db.json
# temporary allow validation of SBOM
sed -i -e 's/SUSE-Public-Domain/CC0-1.0/g' $tmpdir/db.json
cat << EOF  >> $tmpdir/db.json
        {
         "type" : "operating-system",
         "name" : "$ID",
         "version" : "$VERSION_ID",
         "description" : "$NAME",
         "externalReferences" : [
            {
               "url" : "$BUG_REPORT_URL",
               "type" : "issue-tracker"
            },
            {
               "url" : "$HOME_URL",
               "type" : "website"
            }
         ]
      }
   ]
}
EOF

mv -f $tmpdir/db.json $RPMDIR/sbom.cdx.json
return 0
}

ret=0

# The frames are terminated with NUL.  Use that as the delimeter and get
# the whole frame in one go.
while read -d ' ' -r FRAME; do
    echo ">>" $FRAME | debug

    # We only want the command, which is the first word
    read COMMAND <<<$FRAME

    # libzypp will only close the plugin on errors, which may also be logged.
    # It will also log if the plugin exits unexpectedly.  We don't want
    # to create a noisy log when using another file system, so we just
    # wait until COMMITEND to do anything.  We also need to ACK _DISCONNECT
    # or libzypp will kill the script, which means we can't clean up.
    debug "COMMAND=[$COMMAND]"
    case "$COMMAND" in
    COMMITEND) ;;
    _DISCONNECT)
        respond "ACK"
        break
        ;;
    *)
        respond "_ENOMETHOD"
        continue
        ;;
    esac


    sbom_generate > $tmpdir/sbom-output
    if test $? -ne 0; then
        respond "ERROR"
        ret=1
        break
    fi

    # Log the output if we're in debug mode
    debug "Output follows:"
    debug -f $tmpdir/sbom-output
    debug -- "End output"


    respond "ACK"
done
debug "Terminating with exit code $ret"
exit $ret
