#!/bin/sh

BACKTITLE="Installation"
DIALOG="/usr/share/oem/bin/dialog --backtitle ${BACKTITLE} "
TMPFILE="$(mktemp)"

get_blockdev() {
	find /dev -type b -a -writable -a ! -name "loop*"  -a ! -name "sr*" 2>&-
}

get_inetdev(){
	awk -F: '/:/ {if(/lo/){next}else{print $1}}' /proc/net/dev 2>&-
}

exit_confirm() {
	local rc=0
	while [ ${rc} == "0" ]; do
		${DIALOG} --title "Exit Confirm" --yesno "Are you sure to exit ?" 5 26
		if [ $? == "0" ]; then 	# Yes
			exit 0
		else			# No / ctrl C 
			rc=1
		fi
	done
}

# trap ctrl C
trap 'exit_confirm' 2 15

# welcome
${DIALOG} --title "Welcome" \
	--msgbox "Welcome to Installation Guid" 5 32

# select block device
blockdevargs=
n=0
for d in `get_blockdev`; do
	((n++))
	blockdevargs="${blockdevargs} ${n} ${d} d${n} "
done
if [ -z "${blockdevargs// /}" ]; then
	${DIALOG} --title "ERROR" \
		--msgbox "ERROR: No Writable Block Device Found!" 5 42
	exit 1
fi
blockdev=
while [ -z "${blockdev}" ]; do 
	exec 3>&1
	blockdev=$( ${DIALOG} --title "Select Disk" \
			--radiolist "Devices:" 20 60 20 \
			${blockdevargs} \
			2>&1 1>&3
		)
	exec 3>&-
done
blockdevargs=( ${blockdevargs} )
device=
for((i=0;i<=${#blockdevargs[*]}-1;i+=3));do
	if [ ${blockdevargs[$i]}  -eq $blockdev ]; then
		echo "$i got it"
		device=${blockdevargs[(($i+1))]}
		break
	fi
done
if [ -z "${device}" ]; then
	${DIALOG} --title "ERROR" \
		--msgbox "ERROR: No Writable Block Device Found!" 5 42
	exit 1
fi

# select csphere role
role=
while [ -z "${role}" ]; do
	exec 3>&1
	role=$( ${DIALOG} --title "Select Role" \
			--radiolist "Role:" 10 60 0 \
			1 Csphere-Controller 	r1  \
			2 Csphere-Agent 	r2 \
			2>&1 1>&3
		)
	exec 3>&-
done

# if agent, setup controller-url / authkey
if [ "${role}" == "2" ]; then
	agentform=
	controller=
	authkey=
	while :; do
		exec 3>&1
		agentform=$( ${DIALOG} --title "Agent Settings" \
				--form "Parameter:" 10 60 0 \
				"Controller:"    1 1 "" 1 12 32 0 \
				"AuthKey   :"    2 1 "" 2 12 32 0 \
				2>&1 1>&3		
			)
		exec 3>&-
		[ -z "${agentform}" ] && continue
		agentform=( ${agentform} )
		controller="${agentform[0]}"; [ -z "${controller}" ] && continue
		authkey="${agentform[1]}"; [ -z "${authkey}" ] && continue
		break
	done
	echo -e "${agentform[*]}"
fi


# setup inet
#inetdevargs=
#if [ -n "$(get_inetdev)" ]; then
#fi


# last confirm
${DIALOG} --title "Last Confirm" \
	--yesno "\nAre you sure to install CoreOS on device ${device} ?\
		 \n\nAll data on ${device} will be lost! " \
	10 60
[ $? -ne 0 ] && exit 

# install begin, display progress bar
mount -o loop /dev/cdrom /mnt
bunzip2 -c  /mnt/bzimage/coreos_production_image.bin.bz2 > "${device}"
blockdev --rereadpt "${device}" 2>&1 1>&-

# finished
${DIALOG} --title "Finished" \
	--msgbox "Installation Finished! Reboot Now ... " 5 41
reboot
