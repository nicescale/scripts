#!/bin/sh
set -e 

/usr/share/oem/bin/dialog
exit 0

show_usage(){
cat <<EOF

Usage: 	    ${0##*/}  <device>

Example:    ${0##*/}  /dev/sda

EOF
}

device=$1
[ -z "${device}" ] && {
	show_usage
	exit 1
}

[ -b "${device}" -a -w "${device}" ] || {
	echo "ERR: [${device}] must be block writable block device"
	exit 1
}

mount -o loop /dev/cdrom /mnt
bunzip2 -c  /mnt/bzimage/coreos_production_image.bin.bz2 > "${device}"
blockdev --rereadpt "${device}"

echo "Install to ${device} Finished!"
