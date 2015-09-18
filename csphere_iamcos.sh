#!/bin/sh
set -e
#
# build binary packages from our local modified codes and
# replace the binary packages of local http file service
#
BASEDIR="$(cd $(dirname $0); /bin/pwd)"
BINHOSTBASE="/website"
BINHOSTPATH="${BINHOSTBASE}/boards/amd64-usr/723.3.0/pkgs/"
BINPACKAGESF="${BINHOSTPATH}/Packages"
SRCDIR="../third_party/"
FMAKECONF="/etc/portage/make.conf"
FMAKECONFUSER="/etc/portage/make.conf.user"
DEFAULT_BINDEST="/var/lib/portage/pkgs/"
BINDEST=
SUFFIXTBZ=".tbz2"
SUFFIXEBD=".ebuild"
BUILDLST=(
	"net-misc/ntp-4.2.8-r3"  "coreos-overlay/net-misc/ntp/ntp-4.2.8-r3" ""
	"sys-apps/baselayout-3.0.14" "coreos-overlay/sys-apps/baselayout/baselayout-3.0.14" ""
	"coreos-base/coreos-init-0.0.1-r108" "coreos-overlay/coreos-base/coreos-init/coreos-init-0.0.1-r108" "symlink-usr"
	"app-emulation/docker-1.6.2"  "coreos-overlay/app-emulation/docker/docker-1.6.2" ""
)

get_bindest() {
	local d=$( awk -F"=" '(NF==2 && $1=="PKGDIR") \
		{gsub("\"","",$2); print $2; exit;} ' \
		$FMAKECONF 2>&-
	)
	[ -d "${d}" ] || d="${DEFAULT_BINDEST}"
	echo -e "${d}/"
}

get_md5sum(){
	md5sum "${1}" 2>&- | awk '{print $1;exit;}' 
}

get_sha1sum(){
	sha1sum "${1}" 2>&- | awk '{print $1;exit;}'
}

get_size(){
	du -sb "${1}" 2>&- | awk '{print $1;exit;}'
}

seekcpvf() {
	local cpv=${1/\//\\/} fname=$2
	awk '($0~/^CPV: '${cpv}'$/) {x=1;next;} \
		(x==1 && $0~/^[ \t]*$/) {exit} \
		(x==1 && $0~/^'${fname}':[ \t]*/) {print NR;exit;} \
		' ${BINPACKAGESF} 2>&-
}

updatecpvf() {
	local ln=$1 fname=$2 fvalue=$3
	sed -i ''${ln}'c'"${fname}"': '"${fvalue}"'' ${BINPACKAGESF}
}

build_package() {
	if [ -n "${2}" ]; then
		echo "USE=\"${2}\"" | sudo tee ${FMAKECONFUSER} >/dev/null
	fi
	sudo ebuild --skip-manifest ${SRCDIR}${1}${SUFFIXEBD} "clean"
	sudo ebuild --skip-manifest ${SRCDIR}${1}${SUFFIXEBD} "package"
}

replace_package() {
	sudo mv -v ${BINDEST}${1}${SUFFIXTBZ} ${BINHOSTPATH}/${1}${SUFFIXTBZ}
}

refresh_digest() {
	updatecpvf $(seekcpvf "${1}" "MD5") \
		"MD5"  \
		$(get_md5sum "${BINHOSTPATH}/${1}${SUFFIXTBZ}")
	updatecpvf $(seekcpvf "${1}" "SHA1") \
		"SHA1"  \
		$(get_sha1sum "${BINHOSTPATH}/${1}${SUFFIXTBZ}")
	updatecpvf $(seekcpvf "${1}" "SIZE") \
		"SIZE"  \
		$(get_size "${BINHOSTPATH}/${1}${SUFFIXTBZ}")
}

# main body begin
BINDEST=$(get_bindest)
for((i=0;i<=${#BUILDLST[*]}-1;i+=3));do
	build_package ${BUILDLST[$(($i+1))]} ${BUILDLST[$(($i+2))]}
	replace_package ${BUILDLST[$i]}
	refresh_digest ${BUILDLST[$i]}
done
