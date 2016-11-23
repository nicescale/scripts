#!/bin/bash
set -e

. csphere_libs.sh

etcd2_url=$1

BINDEST=$(get_bindest)
mkdir -p "${BINDEST}dev-db"
echo "downloading $etcd2_url ..."
curl -sS $etcd2_url > ${BINDEST}${ETCD2_NAME}${SUFFIXTBZ}
echo "sha1sum of $etcd2_url"
sha1sum "${BINDEST}${ETCD2_NAME}${SUFFIXTBZ}"
