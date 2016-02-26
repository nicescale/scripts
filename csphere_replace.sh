#!/bin/bash
set -e

. csphere_libs.sh

BINDEST=$(get_bindest)
for((i=0;i<=${#BUILDLST[*]}-1;i+=3));do
	if [ "${BUILDLST[$(($i+2))]}" == "PREBUILD" ]; then
		confirm_package ${BUILDLST[$i]}
	else
		build_package ${BUILDLST[$(($i+1))]} ${BUILDLST[$(($i+2))]}
	fi
	replace_package ${BUILDLST[$i]}
	refresh_digest ${BUILDLST[$i]}
done
