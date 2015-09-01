#!/bin/sh

BACKTITLE="Installation"
DIALOG="/usr/share/oem/bin/dialog --backtitle ${BACKTITLE} "
TMPFILE="$(mktemp)"
TMPINET="$(mktemp).inet"
MOUNTON="/mnt"
BLOCKDEV=()
INETDEV=()
DEVICE=

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
	local coreos.units=0
	if [ -f "${TMPINET}" -a -s "${TMPINET}" ]; then
		local tmp=$(cat "${TMPINET}")
		tmp=$(echo -e "${tmp}" | sed -e 's/^/    /')
		cat <<EOF
coreos:
  units:
${tmp}
EOF
		coreos.units=1
	fi
}

gen_network_cloudconfig(){
	local inet="$1" cfg="$2"
	cat << EOF
- name: ${inet}-static.network
  content : |
    [Match]
    Name=${inet}

EOF
	local tmp=$( parse_inetcfg "${cfg}" ) 
	tmp=$(echo -e "${tmp}" | sed -e 's/^/    /')
	cat << EOF
${tmp}
EOF
}

inetcfg_error=(
	1  "IPAddr Malformation"
	2  "Gateway Malformation"
	3  "Dns Malformation"
	4  "Config Count Missing"
)

# parse inet config
parse_inetcfg() {
	local s="${1}"
	local ln=$(echo -e "${s}" | awk 'END{print NR}')
	[ $ln -ne 3 ] && return 4
	local ipaddr= gateway= dns=
	ipaddr=$(echo -e "${s}" | awk '{print;exit 0}')
	gateway=$(echo -e "${s}" | awk '(NR==2){print;exit}')
	dns=$(echo -e "${s}" | awk '(NR==3){print;exit}')
	ipp1=$(echo -e "${ipaddr}" | awk -F"/" '{print $1}')
	ipp2=$(echo -e "${ipaddr}" | awk -F"/" '{print $NF}')
	if ! isipaddr "${ipp1}" || ! is_between "${ipp2}" 0 32; then
		 return 1
	fi
	isipaddr "${gateway}"  || return 2
	isipaddr "${dns}" || return 3
	cat << EOF
[Network]
DHCP=no
Address=${ipaddr} 
Gateway=${gateway}
DNS=${dns}
EOF
	return 0
}

isipaddr() {
        echo "${1}" | grep -E -q "^(([0-9]|([1-9][0-9])|(1[0-9]{2})|(2([0-4][0-9]|5[0-5])))\.){3}([1-9]|([1-9][0-9])|(1[0-9]{2})|(2([0-4][0-9]|5[0-5])))$"
}

is_between() {
        echo $1 $2 $3 | awk '{if($1>=$2 && $1<=$3){exit 0;} else{exit 1;}}' 2>&- 
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
welcome() {
	${DIALOG} --title "Welcome" \
		--msgbox "Welcome to Installation Guid" 5 32
}

# select block device
setup_device() {
	get_blockdev
	local blockdevargs=()
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
	local rc=
	while [ -z "${DEVICE}" ]; do 
		exec 3>&1
		DEVICE=$( ${DIALOG} --title "Select Disk" \
				--cancel-label "Exit" \
				--radiolist "Devices:" 20 60 20 ${blockdevargs[*]} \
				2>&1 1>&3
			)
		rc=$?
		exec 3>&-
		[ $rc -eq 1 ] && exit_confirm
	done
}

# select csphere role
setup_role() {
	local rc=
	while [ -z "${Role}" ]; do
		exec 3>&1
		Role=$( ${DIALOG} --title "Select Role" \
			--cancel-label "Exit" \
			--radiolist "Role:" 10 60 0 \
			"controller" "Csphere Controller" 	r1 \
			"agent"      "Csphere Agent" 		r2 \
			2>&1 1>&3
		)
		rc=$?
		exec 3>&-
		[ $rc -eq 1 ] && exit_confirm
	done
}

# if agent, setup controller-url / authkey
setup_agentcfg() {
	local agentform=
	local rc=
	while :; do
		exec 3>&1
		agentform=$( ${DIALOG} --title "Agent Settings" \
				--cancel-label "Exit" \
				--form "Parameter:" 10 60 0 \
				"Controller:"    1 1 "" 1 12 32 0 \
				"AuthKey   :"    2 1 "" 2 12 32 0 \
				2>&1 1>&3		
			)
		rc=$?
		exec 3>&-
		[ $rc -eq 1 ] && exit_confirm
		[ -z "${agentform}" ] && continue
		agentform=( ${agentform} )
		Controller="${agentform[0]}"; [ -z "${Controller}" ] && continue
		AuthKey="${agentform[1]}"; [ -z "${AuthKey}" ] && continue
		break
	done
}

# system setup
setup_system() {
	local rc=
	local syssetup=
	while :; do
		exec 3>&1
		syssetup=$( ${DIALOG} --title "System Settings" \
			--cancel-label "Exit" \
			--form "Parameter:" 10 60 0 \
			"HostName:"      1 1 "${HostName}"     1 12 32 0 \
			"UserName:"      2 1 "${DefaultUser}"  2 12 -32 -32 \
			"Password:"      3 1 ""                3 12 32 0 \
			2>&1 1>&3
		)
		rc=$?
		exec 3>&-
		[ $rc -eq 1 ] && exit_confirm
		[ -z "${syssetup}" ] && continue
		syssetup=( ${syssetup} )
		HostName="${syssetup[0]}"; [ -z "${HostName}" ] && continue
		Password="${syssetup[1]}"; [ -z "${Password}" ] && continue
		Password="$( openssl  passwd -1  "${Password}" 2>/dev/null)"
		break
	done
}

# setup inet
setup_inet() {
	get_inetdev
	local inetdevargs=()
	for((i=0;i<=${#INETDEV[*]}-1;i+=2));do
		if [ -n ${INETDEV[$i]} -a -n "${INETDEV[(($i+1))]}" ]; then
			inetdevargs+=( ${INETDEV[$i]} ${INETDEV[(($i+1))]} ${i} )
		fi
	done
	if [ ${#inetdevargs[0]} -eq 0 ]; then
	${DIALOG} --title "NOTE" \
		--msgbox "NOTE: No Network Interface Device Found!" 5 44
		return 0
	fi

	local inetdev=
	local savedcfgs=()
	local ccl_label= extra_opts=
	local rc=
	while :; do 
		if [ "${#savedcfgs[*]}" -gt 0 ]; then
			ccl_label="Discard"
			extra_opts=" --extra-button --extra-label Save/Quit "
		else
			ccl_label="Skip"
			extra_opts=
		fi
		exec 3>&1
		inetdev=$( ${DIALOG} --title "Select Network Interface" \
				--ok-label "Select/Setup" --cancel-label "${ccl_label}" \
				${extra_opts} \
				--radiolist "Interface:" 20 70 20 \
				${inetdevargs[*]} \
				2>&1 1>&3
			)
		rc=$?
		exec 3>&-
		if [ $rc -eq 0 ]; then   # select and setup
			[ -z "${inetdev}" ] && continue
		elif [ $rc -eq 1 ]; then # cancel-label
			if [ "${#savedcfgs[*]}" -gt 0 ]; then ## Discard
				${DIALOG} --title "Confirm" \
					--yesno "Discard Network Interface Setup ?" \
					5 38
			else				    ## Skip
				${DIALOG} --title "Confirm" \
					--yesno "Skip Network Interface Setup ?" \
					5 34
			fi
			[ $? -eq 0 ] && break || continue
		elif [ $rc -eq 3 ]; then   ## save and quit
			break
		fi

		cfg=
		while [ -z "${cfg}" ]; do
			exec 3>&1
			cfg=$(	${DIALOG} --title "SetUp ${inetdev}:" \
					--ok-label "Save" --cancel-label "Discard" \
					--form "Parameter:" 10 60 0 \
					"IPAddres :"     1 1 ""  1 12 32 0 \
					"Gateway  :"     2 1 ""  2 12 32 0 \
					"DnsMaster:"     3 1 ""  3 12 32 0 \
					2>&1 1>&3
				)
			rc=$?
			exec 3>&-
			[ $rc -eq 1 ] && cfg= && break 1
			# mmm=$(parse_inetcfg "${cfg}"); rrr=$?
			# ${DIALOG} --title "Parse Result" --msgbox "mmm=${mmm} rrr=${rrr}"  40 100
			if ! parse_inetcfg "${cfg}" >/dev/null 2>&1; then
				cfg=
				continue 1
			fi
		done

		# accumulated savecfgs
		if [ -n "${cfg}" ]; then
			savedcfgs+=( "${inetdev}" "${cfg}" ) 
		fi	
	done

	:>${TMPINET}
	for((i=0;i<=${#savedcfgs[*]}-1;i+=2));do
		gen_network_cloudconfig "${savedcfgs[$i]}" "${savedcfgs[(($i+1))]}" >> ${TMPINET}
	done
}

# last confirm and install begin, display progress bar
prog_inst() {
	${DIALOG} --title "Last Confirm" \
		--yesno "\nAre you sure to install CoreOS on device ${DEVICE} ?\
		 	\n\nAll data on ${DEVICE} will be lost! " \
		10 60
	[ $? -ne 0 ] && exit 0

	clean_mount ${MOUNTON}

	(
		progress 0 10 0.1 "mount cdrom ..." &
		mount -o loop /dev/cdrom ${MOUNTON}
		sleep 1
		kill -10 $! >/dev/null 2>&1

		progress 11 95 0.4 "writing disk ..." &
		bunzip2 -c  ${MOUNTON}/bzimage/coreos_production_image.bin.bz2 > "${DEVICE}"
		sleep 1
		kill -10 $! >/dev/null 2>&1
	
		progress 96 100 0.1 "updating partition table ..." &
		blockdev --rereadpt "${DEVICE}" 2>&1
		sleep 1
		kill -10 $! >/dev/null 2>&1
	) | ${DIALOG} --gauge "Please Wait ..." 12 70 0
}

# creating cloud config 
cloudinit() {
	${DIALOG} --title "Almost Done" \
		--infobox "Creating Cloud Config ... " 3 29
	mkdir -p /mnt1
	mount -t ext4 ${DEVICE}9 /mnt1
	mkdir -p /mnt1/var/lib/coreos-install
	gen_cloudconfig > "${TMPFILE}"
	if ! coreos-cloudinit -validate --from-file="${TMPFILE}" >/dev/null 2>&1;  then
		${DIALOG} --title "ERROR" \
			--msgbox "ERROR: Cloud Config Validation Error!" 5 41
		exit 1
	fi
	${DIALOG} --title "Confirm Cloud Config" \
		--ok-label "OK" \
		--textbox "${TMPFILE}" \
		20 70
	cp "${TMPFILE}" /mnt1/var/lib/coreos-install/user_data
	clean_mount /mnt1
	sleep 1
}

bye() {
	# finished
	${DIALOG} --title "Finished" \
		--msgbox "Installation Finished! Reboot Now ? " 5 39
}


# Main Body Begin 
welcome
setup_device
setup_role
[ "${Role}" == "agent" ] &&  setup_agentcfg
setup_system
setup_inet
prog_inst
cloudinit
bye
reboot
