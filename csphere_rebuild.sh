#!/bin/sh
set -e

assets_url="http://tsing:e0cab9e41247ec200b7eb6ec5cb159ec@54.64.118.80/job/csphere-fe/lastSuccessfulBuild/artifact/dist/assets-0.13.tgz"
mongod_url="http://192.157.213.209/mongo-3.0.3/mongo-3.0.3.tgz"

sudo cp -a xfs/mkfs.xfs /sbin/mkfs.xfs

mode=$1
case "${mode}" in
"all")
	sudo /bin/rm -rf ../build/*
	echo "csphere" | \
		openssl passwd -1 -stdin | \
		sudo tee /etc/shared_user_passwd.txt >/dev/null
	./setup_board --default --board=amd64-usr
	./build_packages --csphere  \
		--csphere_assets_path="${assets_url}" \
		--csphere_mongod_path="${mongod_url}" \
		# --reuse_pkgs_from_local_boards \  # this flag is abondoned
		--nogetbinpkg
	./build_image prod
	;;
"iso")
	sudo /bin/rm -rf ../build/images/amd64-usr/latest/*iso*
	./image_to_vm.sh  --format=iso \
		--from=../build/images/amd64-usr/latest/ \
		--board=amd64-usr \
		--prod_image
	exit 0
	;;
*)
	cat <<HELP
	Usage:   ${0##*/}    all | iso 
HELP
	exit 1
esac

./image_to_vm.sh  --format=iso \
	--from=../build/images/amd64-usr/latest/ \
	--board=amd64-usr \
	--prod_image
