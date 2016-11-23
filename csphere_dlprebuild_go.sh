#!/bin/bash
set -e

. csphere_libs.sh

golang_url=$1

BINDEST=$(get_bindest)
mkdir -p "${BINDEST}dev-lang"
echo "downloading $golang_url ..."
curl -sS $golang_url > ${BINDEST}${GOLANG_NAME}${SUFFIXTBZ}
echo "sha1sum of $golang_url"
sha1sum "${BINDEST}${GOLANG_NAME}${SUFFIXTBZ}"
