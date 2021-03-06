#!/bin/bash
#
# Copyright 2010-2013 Akiban Technologies, Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Build build artifacts associated with a release
#   - Bundles/packages
#       - akiban-sql-parser-X.X.X.zip                (binary, Apache)
#       - akiban-sql-parser-X.X.X.tar.gz             (binary, Apache)
#       - akiban-sql-parser-X.X.X-source.zip         (source, Apache)
#       - akiban-sql-parser-X.X.X-source.tar.gz      (source, Apache)
#

set -e

# $1 - APIDOC_URL (empty OK)
function docs_build {
    rm -rf target/site/apidocs
    mvn javadoc:javadoc >/dev/null
}

# $1 - revno
# $2 - args to maven
function maven_build {
    mvn $2 -DBZR_REVISION="$1" -DskipTests=true clean compile test-compile package >/dev/null
}

MD5_TYPE=""
function md5_type {
    if [ "$(which md5sum)" != "" ]; then
        MD5_TYPE="md5sum"
    else
        if [ "$(which md5)" != "" ]; then
            MD5_TYPE="md5"
        else
            echo "    No supported md5 program found in PATH" 1>&2
            exit 1
        fi
    fi
}

function do_md5 {
    OUTFILE="${1}.md5"
    case "${MD5_TYPE}" in
        md5)
            $(md5 -r "$1" |sed 's/ /  /' > "${OUTFILE}")
        ;;
        md5sum)
            $(md5sum "$1" > "${OUTFILE}")
        ;;
        *)
            echo "Unknown md5 type: ${MD5_TYPE}"
            exit 1
        ;;
    esac
}


REQUIRED_PROGS="bzr mvn javac sphinx-build curl awk sed tr basename zip tar gpg"
BRANCH_DEFAULT="lp:~akiban-technologies/akiban-sql-parser"

VERSION=""
BRANCH_URL=""
WORKSPACE="/tmp/parser_release"

while getopts "hb:v:w:" FLAG; do
    case "${FLAG}" in
        h) ;;
        b) BRANCH_URL="${OPTARG}" ;;
        v) VERSION="${OPTARG}" ;;
        w) WORKSPACE="${OPTARG}" ;;
        *) echo "Unhandled option" 1>&2 ; exit 1 ;;
    esac
done

if [ "${VERSION}" = "" ]; then
    echo "Missing required version arg -v" 1>&2
    exit 1
fi

if [ "${BRANCH_URL}" = "" ]; then
    BRANCH_URL="${BRANCH_DEFAULT}/${VERSION}"
fi


echo "Build packages for version: ${VERSION}"
echo "Use source branch         : ${BRANCH_URL}"
echo "Use workspace location    : ${WORKSPACE}"


echo "Checking for required programs"
for PROG in ${REQUIRED_PROGS}; do
    if [ "$(which ${PROG})" = "" ]; then
        echo "    ${PROG} not found in PATH" 1>&2
        exit 1
    fi
done

echo "Checking for md5 program"
md5_type


NAME="akiban-sql-parser"
BRANCH_DIR="${WORKSPACE}/${VERSION}"
SOURCE_DIR="${WORKSPACE}/${NAME}-${VERSION}-source"
OPEN_DIR="${WORKSPACE}/${NAME}-${VERSION}"


echo "Cleaning workspace ${WORKSPACE}"
rm -rf "${WORKSPACE}"
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"


echo "Fetching revision number"
REVNO=$(bzr revno -q "${BRANCH_URL}")
echo "Revision $REVNO"


echo "Exporting branch"
bzr export -q "${BRANCH_DIR}" "${BRANCH_URL}"


echo "Making package directories"
cp -r "${BRANCH_DIR}" "${SOURCE_DIR}"
cp -r "${BRANCH_DIR}" "${OPEN_DIR}"
rm -r "${OPEN_DIR}"/{src,pom.xml}
mkdir "${OPEN_DIR}/doc"


echo "Building open edition and docs"
cd "${BRANCH_DIR}"
maven_build "${REVNO}"
docs_build "../apidocs"


echo "Copying docs and jars"
cd "${WORKSPACE}"
cp -r "${BRANCH_DIR}"/target/site/apidocs "${OPEN_DIR}/doc"
# TODO: need to create release notes for parser
mv "${BRANCH_DIR}"/target/*-sources.jar "${OPEN_DIR}/${NAME}-${VERSION}-sources.jar"
mv "${BRANCH_DIR}"/target/${NAME}-${VERSION}.jar "${OPEN_DIR}/${NAME}-${VERSION}.jar"


echo "Creating zip and tar.gz files"
cd "${WORKSPACE}"
for DIR in "${OPEN_DIR}" "${SOURCE_DIR}"; do
    BASE_DIR="`basename ${DIR}`"
    zip -r "${DIR}.zip" "$BASE_DIR" >/dev/null
    tar czf "${DIR}.tar.gz" "${BASE_DIR}"
done


if [ "$SKIP_SIGNING" = "" ]; then
    echo "Signing files for Launchpad upload"
    for FILE in `ls *.zip *.tar.gz`; do
        gpg --armor --sign --detach-sig "${FILE}" 1>/dev/null
        do_md5 "${FILE}"
    done
fi


echo "All output files are in: ${WORKSPACE}"
echo "Done"

