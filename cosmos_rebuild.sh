#!/bin/bash
#
# Rebuild the patched cosmos gem:
#   1. DIFF CREATE  - diff the reference gem against the installed, modified version
#   2. REF CREATE   - unpack a clean copy of the reference gem
#   3. APPLY PATCH  - apply the diff to the clean copy
#   4. CREATE       - build the new gem from the patched copy
#
# Run it as a script (./cosmos_rebuild.sh), do NOT "source" it.

set -eu                                               # stop on the first error or unset variable
                                                      # (no pipefail: "yes | cp" always ends "yes" with SIGPIPE)

############################# HELPERS #############################
PS4='+ [line ${LINENO}] '                             # prefix of every echoed command
shopt -s expand_aliases
alias say='{ set +x; } 2>/dev/null; _say'             # echo off, so the message is not printed twice
alias die='{ set +x; } 2>/dev/null; _die'

_say() {                                              # say HEADLINE [DETAIL...] - print, then echo on again
    printf '\n>>> %s\n' "$1"
    shift
    while [ $# -gt 0 ]; do
        printf '%s\n' "$1" | sed 's/^/    /'
        shift
    done
    set -x
}

fail_msg=""
_die() {                                              # die MESSAGE - stop, on_exit prints the message
    fail_msg="$*"
    exit 1
}

rbenv_dirty=0                                         # 1 while the reference gem is installed in rbenv
restore_rbenv() {                                     # undo everything "gem install" did to rbenv
    rbenv_dirty=0
    cd "$RBENV_FOLDER" && git reset --hard && git clean -fdx
}

on_exit() {                                           # runs at every exit, also after an error or Ctrl-C
    if [ "$rbenv_dirty" -eq 1 ]; then
        printf '\n>>> Restore rbenv before stopping\n'
        restore_rbenv || fail_msg="$fail_msg (and rbenv could NOT be restored)"
    fi
    if [ "$1" -ne 0 ]; then
        printf '\nERROR: %s\n' "${fail_msg:-exit status $1}" >&2
    fi
}

trap '{ fail_msg="stopped at line $LINENO"; } 2>/dev/null' ERR
trap '{ fail_msg="interrupted"; } 2>/dev/null; exit 130' INT TERM
trap '{ status=$?; set +x; } 2>/dev/null; on_exit "$status"' EXIT

############################ SETTINGS #############################
export PACKAGE_VERSION_REF="4.5.2"

export PACKAGE_NAME="cosmos"
export PACKAGE_VERSION="4.5.3"
export PACKAGE_FOLDER="${PACKAGE_NAME}-${PACKAGE_VERSION_REF}"

PACKAGE_FOLDER_NEW="${PACKAGE_NAME}-${PACKAGE_VERSION}"
DIFF_FILE="${PACKAGE_FOLDER}_to_${PACKAGE_VERSION}.diff"

export RBENV_FOLDER="$HOME/.rbenv"                                    # replaces the console function "rbenvd"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"            # folder of this script (cosmos_install)
GEMS_DIR="$RBENV_FOLDER/versions/2.2.2/lib/ruby/gems/2.2.0/gems"      # Centos 32 Bit
# GEMS_DIR="$RBENV_FOLDER/versions/2.5.8/lib/ruby/gems/2.5.0/gems"    # Ubuntu 64 Bit

set -x                                                # echo on

############################# CHECKS ##############################
say "Rebuild ${PACKAGE_FOLDER_NEW}.gem = ${PACKAGE_FOLDER}.gem + the changes of the installed ${PACKAGE_FOLDER_NEW}" \
    "reference gem    : $SCRIPT_DIR/${PACKAGE_FOLDER}.gem" \
    "modified version : $GEMS_DIR/$PACKAGE_FOLDER_NEW" \
    "diff file        : $SCRIPT_DIR/$DIFF_FILE" \
    "new gem          : $SCRIPT_DIR/${PACKAGE_FOLDER_NEW}.gem"

if [ ! -f "$SCRIPT_DIR/${PACKAGE_FOLDER}.gem" ]; then
    die "reference gem not found: $SCRIPT_DIR/${PACKAGE_FOLDER}.gem"
fi
if [ ! -d "$GEMS_DIR/$PACKAGE_FOLDER_NEW" ]; then
    die "modified version not found: $GEMS_DIR/$PACKAGE_FOLDER_NEW"
fi

# DIFF CREATE ends with "git reset --hard" and "git clean -fdx" in $RBENV_FOLDER: make sure
# it really is the rbenv repository and that no uncommitted change would be thrown away
cd "$RBENV_FOLDER"
if [ "$(git rev-parse --show-toplevel)" != "$(pwd -P)" ]; then
    die "$RBENV_FOLDER is not the top folder of a git repository"
fi
uncommitted=$(git status --porcelain --untracked-files=no)
if [ -n "$uncommitted" ]; then
    say "Uncommitted changes in $RBENV_FOLDER:" "$uncommitted"
    die "commit them first, \"git reset --hard\" would throw them away"
fi

########################### DIFF CREATE ###########################
say "DIFF CREATE: install ${PACKAGE_FOLDER}.gem next to the modified ${PACKAGE_FOLDER_NEW}"
cd "$SCRIPT_DIR"
rbenv_dirty=1                                         # from here on rbenv is restored, whatever happens
gem install --force "./${PACKAGE_FOLDER}.gem"

cd "$GEMS_DIR"
if [ ! -d "$PACKAGE_FOLDER" ]; then                   # with -N a missing folder would count as an empty one
    die "gem install did not create $GEMS_DIR/$PACKAGE_FOLDER"
fi
diff_rc=0                                             # 0 = identical, 1 = differences found (expected), 2 = trouble
diff -uraN -x '*.o' -x '*.so' -x '*.bin' -x '*.gif' -x '*.txt' -x '*.tsv' -x 'Makefile' \
    "$PACKAGE_FOLDER" "$PACKAGE_FOLDER_NEW" \
    > "$DIFF_FILE" || diff_rc=$?

# -x '*.txt' and -x '*.tsv' keep log files out of the diff, but they also hide files that are
# packed into the gem (Manifest.txt itself, config files, ...): diff the packed ones separately.
# A packed file that is missing in the installed version (the outputs/ folders are not kept
# in the rbenv repository) is not a deleted file: it stays as it is in the reference gem.
{ set +x; } 2>/dev/null                               # echo off, this loops over all packed text files
txt_dir=$(mktemp -d)
mkdir "$txt_dir/$PACKAGE_FOLDER" "$txt_dir/$PACKAGE_FOLDER_NEW"
kept=0
skipped=0
while IFS= read -r f; do
    case "${f##*/}" in
        crc.txt|README.txt)                           # no patch wanted for these, whatever folder they are in
            skipped=$((skipped + 1))
            continue ;;
    esac
    if [ ! -f "$PACKAGE_FOLDER_NEW/$f" ]; then
        kept=$((kept + 1))
        continue
    fi
    (cd "$PACKAGE_FOLDER_NEW" && cp --parents "$f" "$txt_dir/$PACKAGE_FOLDER_NEW/")
    if [ -f "$PACKAGE_FOLDER/$f" ]; then
        (cd "$PACKAGE_FOLDER" && cp --parents "$f" "$txt_dir/$PACKAGE_FOLDER/")
    fi
done < <(tr -d '\r' < "$PACKAGE_FOLDER_NEW/Manifest.txt" | grep -E '\.(txt|tsv)$' || true)
txt_rc=0
(cd "$txt_dir" && diff -uraN "$PACKAGE_FOLDER" "$PACKAGE_FOLDER_NEW") > "$txt_dir/packed.diff" || txt_rc=$?
cat "$txt_dir/packed.diff" >> "$DIFF_FILE"
packed_txt=$(sed -n "s|^diff -uraN .* ${PACKAGE_FOLDER_NEW}/||p" "$txt_dir/packed.diff")
rm -rf "$txt_dir"
if [ "$txt_rc" -gt "$diff_rc" ]; then
    diff_rc=$txt_rc
fi

say "diff exit status ${diff_rc} (1 = differences found), packed *.txt and *.tsv files in the diff:" \
    "${packed_txt:-(none)}" \
    "(${skipped} crc.txt and README.txt files are left out on purpose and stay as in the reference gem)" \
    "(${kept} packed text files are missing in the installed ${PACKAGE_FOLDER_NEW} and stay as in the reference gem)"
if [ "$diff_rc" -ne 1 ]; then
    die "diff failed or found no differences, $SCRIPT_DIR/$DIFF_FILE was not updated"
fi
wc -l "$DIFF_FILE"
yes | cp "$DIFF_FILE" "$SCRIPT_DIR/"

say "DIFF CREATE: restore rbenv"
restore_rbenv

########################### REF CREATE ############################
say "REF CREATE: unpack a clean ${PACKAGE_FOLDER}"
cd "$SCRIPT_DIR"
# rm -rif $PACKAGE_FOLDER".gem" $PACKAGE_FOLDER
# gem fetch $PACKAGE_NAME -v $PACKAGE_VERSION_REF
rm -rf "$PACKAGE_FOLDER" "$PACKAGE_FOLDER_NEW"        # leftovers of an aborted run
gem unpack "./${PACKAGE_FOLDER}.gem"

########################### APPLY PATCH ###########################
say "APPLY PATCH: dry run"
cd "$SCRIPT_DIR"
yes | cp "$DIFF_FILE" ./p1.patch
# Rename the top folder in the file header lines only, never in the patched content
sed -i -r "/^(diff|---|\+\+\+) / s|${PACKAGE_FOLDER}/|${PACKAGE_FOLDER_NEW}/|g" p1.patch

cd "$PACKAGE_FOLDER"
patch --dry-run -p1 -i ../p1.patch
# read -p "Check dry-run & press any key to continue... " -n1 -s
say "APPLY PATCH: dry run OK, patching ${PACKAGE_FOLDER}"
patch -p1 -i ../p1.patch
rm -f ../p1.patch

cd "$SCRIPT_DIR"
#yes | cp splash/data/*.gif "$PACKAGE_FOLDER/data/"

# "gem build" packs exactly the files listed in Manifest.txt: compare the patched folder with it
{ set +x; } 2>/dev/null                               # echo off, only the result matters here
if [ ! -f "$PACKAGE_FOLDER/Manifest.txt" ]; then
    die "$PACKAGE_FOLDER/Manifest.txt not found"
fi
cd "$PACKAGE_FOLDER"
manifest=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' Manifest.txt | grep -v '^$' || true)
missing=$(printf '%s\n' "$manifest" | while IFS= read -r f; do [ -f "$f" ] || printf '%s\n' "$f"; done)
not_packed=$(find . -type f | sed 's|^\./||' | sort | grep -vxF -f <(printf '%s\n' "$manifest") || true)
cd "$SCRIPT_DIR"
if [ -n "$missing" ]; then
    say "Listed in Manifest.txt but missing in the patched ${PACKAGE_FOLDER}:" "$missing"
    die "gem build would fail: put these files into the patched ${PACKAGE_FOLDER} or correct Manifest.txt"
fi
if [ -n "$not_packed" ]; then
    say "WARNING: not listed in Manifest.txt, so NOT packed into the gem:" "$not_packed"
else
    say "Manifest.txt matches the patched ${PACKAGE_FOLDER}"
fi

########################## CREATE 4.5.3 ###########################
say "CREATE: build ${PACKAGE_FOLDER_NEW}.gem"
cd "$SCRIPT_DIR"
rm -f "${PACKAGE_FOLDER_NEW}.gem"

mv "$PACKAGE_FOLDER" "$PACKAGE_FOLDER_NEW"
cd "$PACKAGE_FOLDER_NEW"

VERSION="$PACKAGE_VERSION" gem build "${PACKAGE_NAME}.gemspec"
mv "${PACKAGE_FOLDER_NEW}.gem" ../

cd "$SCRIPT_DIR"
rm -rf "$PACKAGE_FOLDER_NEW"
ls -l "${PACKAGE_FOLDER_NEW}.gem"
say "DONE: $SCRIPT_DIR/${PACKAGE_FOLDER_NEW}.gem"

############################# INSTALL #############################
# WTF: if cosmos install original version instead patched one => remove all files in rbenvd & git reset --hard
# rbenvd && rm -rif ./versions/2.2.2/lib/ruby/gems/2.2.0/cache/cosmos-4.5.3.gem  # Centos 32 Bit
# rbenvd && rm -rif ./versions/2.5.8/lib/ruby/gems/2.5.0/cache/cosmos-4.5.3.gem  # Ubuntu 64 Bit
# cp $PACKAGE_FOLDER"_patched.gem" $PACKAGE_FOLDER.gem
# gem uninstall $PACKAGE_NAME -v $PACKAGE_VERSION
# gem install --force ./$PACKAGE_FOLDER".gem"
# rm -rif $PACKAGE_FOLDER.gem
###################################################################
