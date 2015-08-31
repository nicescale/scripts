#!/bin/sh

BACKTITLE="Installation"
DIALOG="/usr/share/oem/bin/dialog --backtitle ${BACKTITLE} "
TMPFILE="$(mktemp)"
MOUNTON="/mnt"
BLOCKDEV=()
INETDEV=()

HostName=$(mktemp -u XXXXXXXX)
DefaultUser="core"
Password=
Role=
Controller=
AuthKey=

gen_cloudconfig() {
cat << EOF
#cloud-config
hostname: ${HostName}
users:
  - name: ${DefaultUser}
    passwd: ${Password}
    groups:
      - sudo
      - docker
EOF
}

get_blockdev() {
	local hwdisk=()
	eval "hwdisk=( 
		$( lshw -short -class disk |\
			awk '($1~/^\//){$1=$3=""; \
				gsub("^[ \t]*","",$0); \
				gsub("[ \t]*$","",$0); \
				print}' | \
			awk '{print "\""$1"\""; \
				$1=""; \
				gsub("[ \t]", "_", $0);\
				print "\""$0"\""}' 
		)
	)
	"
	for((i=0;i<=${#hwdisk[*]}-1;i+=2)) do
		[ -b ${hwdisk[$i]} -a -w ${hwdisk[$i]} ] || continue
		[[ ${hwdisk[$i]} =~ "cdrom" ]] && continue
		BLOCKDEV+=( ${hwdisk[$i]}  "${hwdisk[(($i+1))]}" )
	done
}
# get_blockdev; echo "${BLOCKDEV[*]}"; exit 0

get_inetdev(){
	local hwnetwork=()
	eval "hwnetwork=(
		$( lshw -short -class network |\
			awk '($1~/^\//){$1=$3=""; \
				gsub("^[ \t]*","",$0); \
				gsub("[ \t]*$","",$0); \
				print}' | \
			awk '{print "\""$1"\""; \
				$1=""; \
				gsub("[ \t]", "_", $0);\
				print "\""$0"\""}'
		)
	)
	"
	INETDEV+=( ${hwnetwork[*]} )
}
# get_inetdev; echo ${INETDEV[*]}; exit 0

clean_mount() {
	if mountpoint  -q ${1} >/dev/null 2>&1; then
		umount ${1}
	fi
}

progress(){
	trap 'echo -e "XXXX\n$2\n\n\n$4\nXXXX\n";exit;' 10
        for((n=$1;n<=$2;n++));do
                echo -e "XXXX\n$n\n\n\n$4\nXXXX"
                sleep $3
        done
}

exit_confirm() {
	local rc=0
	while [ ${rc} == "0" ]; do
		${DIALOG} --title "Exit Confirm" --yesno "Are you sure to exit ?" 5 26
		if [ $? == "0" ]; then 	# Yes
			clean_mount ${MOUNTON}
			exit 0
		else			# No / ctrl C 
			rc=1
		fi
	done
}

# trap ctrl C
trap 'exit_confirm' 2 15


# run as root
if [ "$(id -u)" != "0" ]; then
	${DIALOG} --title "Note" \
		--msgbox "Require Root Privilege" 5 26
	exit 1
fi

# welcome
${DIALOG} --title "Welcome" \
	--msgbox "Welcome to Installation Guid" 5 32

# select block device
get_blockdev
blockdevargs=()
for((i=0;i<=${#BLOCKDEV[*]}-1;i+=2));do
	if [ -n ${BLOCKDEV[$i]} -a -n "${BLOCKDEV[(($i+1))]}" ]; then
		blockdevargs+=( ${BLOCKDEV[$i]} ${BLOCKDEV[(($i+1))]} ${i} )
	fi
done
if [ ${#blockdevargs[0]} -eq 0 ]; then
	${DIALOG} --title "ERROR" \
		--msgbox "ERROR: No Writable Block Device Found!" 5 42
	exit 1
fi
device=
while [ -z "${device}" ]; do 
	exec 3>&1
	device=$( ${DIALOG} --title "Select Disk" \
			--radiolist "Devices:" 20 60 20 ${blockdevargs[*]} \
			2>&1 1>&3
		)
	exec 3>&-
done

# select csphere role
while [ -z "${Role}" ]; do
	exec 3>&1
	Role=$( ${DIALOG} --title "Select Role" \
			--radiolist "Role:" 10 60 0 \
			"controller" "Csphere Controller" 	r1 \
			"agent"      "Csphere Agent" 		r2 \
			2>&1 1>&3
		)
	exec 3>&-
done

# if agent, setup controller-url / authkey
if [ "${Role}" == "agent" ]; then
	agentform=
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
		Controller="${agentform[0]}"; [ -z "${Controller}" ] && continue
		AuthKey="${agentform[1]}"; [ -z "${AuthKey}" ] && continue
		break
	done
fi

# system setup
syssetup=
while :; do
	exec 3>&1
	syssetup=$( ${DIALOG} --title "System Settings" \
			--form "Parameter:" 10 60 0 \
			"HostName:"      1 1 "${HostName}"     1 12 32 0 \
			"UserName:"      2 1 "${DefaultUser}"  2 12 -32 -32 \
			"Password:"      3 1 ""                3 12 32 0 \
			2>&1 1>&3
		)
	exec 3>&-
	[ -z "${syssetup}" ] && continue
	syssetup=( ${syssetup} )
	HostName="${syssetup[0]}"; [ -z "${HostName}" ] && continue
	Password="${syssetup[1]}"; [ -z "${Password}" ] && continue
	Password="$( openssl  passwd -1  "${Password}" 2>/dev/null)"
	break
done

# setup inet
get_inetdev
inetdevargs=()
for((i=0;i<=${#INETDEV[*]}-1;i+=2));do
	if [ -n ${INETDEV[$i]} -a -n "${INETDEV[(($i+1))]}" ]; then
		inetdevargs+=( ${INETDEV[$i]} ${INETDEV[(($i+1))]} ${i} )
	fi
done
if [ ${#blockdevargs[0]} -eq 0 ]; then
	${DIALOG} --title "ERROR" \
		--msgbox "ERROR: No Writable Block Device Found!" 5 42
	exit 1
fi
inetdevargs+=( "SKIP" "Skip_Inet_Setup" "skip" )
inetdev=
while [ -z "${inetdev}" ]; do 
	exec 3>&1
	inetdev=$( ${DIALOG} --title "Select Network Interface" \
			--radiolist "Interface:" 20 70 20 ${inetdevargs[*]} \
			2>&1 1>&3
		)
	exec 3>&-
done
if [ ${inetdev} != "SKIP" ]; then
	echo "${inetdev}"
fi


# last confirm
${DIALOG} --title "Last Confirm" \
	--yesno "\nAre you sure to install CoreOS on device ${device} ?\
		 \n\nAll data on ${device} will be lost! " \
	10 60
[ $? -ne 0 ] && exit 

# install begin, display progress bar
clean_mount ${MOUNTON}
(
	progress 0 10 0.1 "mount cdrom ..." &
	mount -o loop /dev/cdrom ${MOUNTON}
	sleep 1
	kill -10 $! >/dev/null 2>&1

	progress 11 95 0.4 "writing disk ..." &
	bunzip2 -c  ${MOUNTON}/bzimage/coreos_production_image.bin.bz2 > "${device}"
	sleep 1
	kill -10 $! >/dev/null 2>&1
	
	progress 96 100 0.1 "updating partition table ..." &
	blockdev --rereadpt "${device}" 2>&1
	sleep 1
	kill -10 $! >/dev/null 2>&1
) | ${DIALOG} --gauge "Please Wait ..." 12 70 0

# creating cloud config 
${DIALOG} --title "Almost Done" \
	--infobox "Creating Cloud Config ... " 3 29
mkdir -p /mnt1
mount -t ext4 ${device}9 /mnt1
mkdir -p /mnt1/var/lib/coreos-install
gen_cloudconfig > "${TMPFILE}"
cp "${TMPFILE}" /mnt1/var/lib/coreos-install/user_data
clean_mount /mnt1
sleep 1

# finished
${DIALOG} --title "Finished" \
	--msgbox "Installation Finished! Reboot Now ? " 5 39

reboot
