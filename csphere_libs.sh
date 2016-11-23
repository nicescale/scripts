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
KERNEL_NAME="sys-kernel/coreos-kernel-4.0.5"
FIRMWARE_NAME="sys-kernel/coreos-firmware-20141009-r1"
GLIBC_NAME="sys-libs/glibc-2.20-r2"
ETCD2_NAME="dev-db/etcd-2.0.12"
GOLANG_NAME="dev-lang/go-1.4.2"
BUILDLST=(
	"${KERNEL_NAME}" "" "PREBUILD"
	"${FIRMWARE_NAME}" "" "PREBUILD"
	"${GLIBC_NAME}" "" "PREBUILD"
	"${ETCD2_NAME}" "" "PREBUILD"
	"${GOLANG_NAME}" "" "PREBUILD"
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
	sudo sed -i ''${ln}'c'"${fname}"': '"${fvalue}"'' ${BINPACKAGESF}
	echo "updating ${BINPACKAGESF}, line:$ln, new:$fname: $fvalue"
}

build_package() {
	echo "building package: $1"
	if [ -n "${2}" ]; then
		echo "USE=\"${2}\"" | sudo tee ${FMAKECONFUSER} >/dev/null
	fi
	sudo ebuild --skip-manifest ${SRCDIR}${1}${SUFFIXEBD} "clean"
	sudo ebuild --skip-manifest ${SRCDIR}${1}${SUFFIXEBD} "package"
}

confirm_package() {
	echo "confirming prebuild package: $1"
	test -e ${BINDEST}${1}${SUFFIXTBZ}
	test -s ${BINDEST}${1}${SUFFIXTBZ}
	sha1sum ${BINDEST}${1}${SUFFIXTBZ}
}

replace_package() {
	echo "replacing package: $1"
	echo "previous: $(sha1sum ${BINHOSTPATH}/${1}${SUFFIXTBZ})"
	sudo mv -v ${BINDEST}${1}${SUFFIXTBZ} ${BINHOSTPATH}/${1}${SUFFIXTBZ}
	echo "new package: $(sha1sum ${BINHOSTPATH}/${1}${SUFFIXTBZ})"
}

refresh_digest() {
	echo "updating md5sum for package: $1"
	updatecpvf $(seekcpvf "${1}" "MD5") \
		"MD5"  \
		$(get_md5sum "${BINHOSTPATH}/${1}${SUFFIXTBZ}")
	echo "updating sha1sum for package: $1"
	updatecpvf $(seekcpvf "${1}" "SHA1") \
		"SHA1"  \
		$(get_sha1sum "${BINHOSTPATH}/${1}${SUFFIXTBZ}")
	echo "updating size for package: $1"
	updatecpvf $(seekcpvf "${1}" "SIZE") \
		"SIZE"  \
		$(get_size "${BINHOSTPATH}/${1}${SUFFIXTBZ}")
}
