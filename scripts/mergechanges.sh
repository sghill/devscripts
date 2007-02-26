#! /bin/bash
## 
## mergechanges -- merge Architecture: and Files: fields of a set of .changes
## Copyright 2002 Gergely Nagy <algernon@debian.org>
## Changes copyright 2002,2003 by Julian Gilbey <jdg@debian.org>
##
## $MadHouse: home/bin/mergechanges,v 1.1 2002/01/25 12:37:27 algernon Exp $
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

set -e

PROGNAME=`basename $0`

usage () {
    echo \
"Usage: $PROGNAME [--help|--version] [-f] <file1> <file2> [<file> ...]
  Merge the changes files <file1>, <file2>, ....  Output on stdout
  unless -f option given, in which case, output to
  <package>_<version>_multi.changes in the same directory as <file1>."
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright (C) 2002 Gergely Nagy <algernon@debian.org>
Changes copyright 2002 by Julian Gilbey <jdg@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

# Commandline parsing
FILE=0

while [ $# -gt 0 ]; do
    case "$1" in
	--help)
	    usage
	    exit 0
	    ;;
	--version)
	    version
	    exit 0
	    ;;
	-f)
	    FILE=1
	    shift
	    ;;
	-*)
	    echo "Unrecognised option $1.  Use $progname --help for help" >&2
	    exit 1
	    ;;
	*)
	    break
	    ;;
    esac
done

# Sanity check #0: Do we have enough paramaters?
if [ $# -lt 2 ]; then
    echo "Not enough paramaters." >&2
    echo "Usage: mergechanges [--help|--version] [-f] <file1> <file2> [<file...>]" >&2
    exit 1
fi

# Sanity check #1: Do the requested files exist?
for f in "$@"; do
    if ! test -r $f; then
	echo "ERROR: Cannot read $f!" >&2
	exit 1
    fi
done

# Extract the Architecture: field from all .changes files,
# and merge them, sorting out duplicates
ARCHS=$(grep -h "^Architecture: " "$@" | sed -e "s,^Architecture: ,," | tr ' ' '\n' | sort -u | tr '\n' ' ')

# Extract & merge the Version: field from all files..
# Don't catch Version: GnuPG lines, though!
VERSION=$(grep -h "^Version: [0-9]" "$@" | sed -e "s,^Version: ,," | sort -u)
SVERSION=$(echo "$VERSION" | perl -pe 's/^\d+://')
# Extract & merge the sources from all files
SOURCE=$(grep -h "^Source: " "$@" | sed -e "s,^Source: ,," | sort -u)
# Extract & merge the files from all files
FILES=$(egrep -h "^ [0-9a-f]{32} [0-9]+" "$@" | sort -u)

# Sanity check #2: Versions must match
if test $(echo "${VERSION}" | wc -l) -ne 1; then
    echo "ERROR: Version numbers do not match:"
    grep "^Version: [0-9]" "$@"
    exit 1
fi

# Sanity check #3: Sources must match
if test $(echo "${SOURCE}" | wc -l) -ne 1; then
    echo "Error: Source packages do not match:"
    grep "^Source: " "$@"
    exit 1
fi

if test ${FILE} = 1; then
    DIR=`dirname "$1"`
    REDIR1="> '${DIR}/${SOURCE}_${SVERSION}_multi.changes'"
    REDIR2=">$REDIR1"
fi

# Temporary output
OUTPUT=`tempfile`
trap "rm -f '${OUTPUT}'" 0 1 2 3 7 10 13 15

# Copy one of the files to ${OUTPUT}, nuking any PGP signature
if $(grep -q "BEGIN PGP SIGNED MESSAGE" "$1"); then
    perl -ne 'next if 1../^$/; next if /^$/..1; print' "$1" > ${OUTPUT}
else
    cp "$1" ${OUTPUT}
fi

# Replace the Architecture: field, and nuke the value of Files:
eval "sed -e 's,^Architecture: .*,Architecture: ${ARCHS},; /^Files: /q' \
    ${OUTPUT} ${REDIR1}"

# Voodoo magic to get the merged filelist into the output
eval "echo '${FILES}' ${REDIR2}"

exit 0