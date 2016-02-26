#!/bin/bash
set -e
# https://coreos.com/releases/#835.13.0
# glibc patched for CVE-2015-1781, CVE-2014-8121, CVE-2015-8776, CVE-2015-8778, CVE-2015-8779 and CVE-2015-7547

. csphere_libs.sh

glibc_url=$1

BINDEST=$(get_bindest)
mkdir -p "${BINDEST}sys-libs"
echo "downloading $glibc_url ..."
curl -sS $glibc_url > ${BINDEST}${GLIBC_NAME}${SUFFIXTBZ}
