#!/bin/bash
set -e

. csphere_libs.sh

kernel_url=$1
firmware_url=$2

BINDEST=$(get_bindest)
sudo curl -sS $kernel_url > ${BINDEST}${KERNEL_NAME}${SUFFIXTBZ}
sudo curl -sS $firmware_url > ${BINDEST}${FIRMWARE_NAME}${SUFFIXTBZ}
