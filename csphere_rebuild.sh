#!/bin/sh
set -e

# newest
assets_url="http://tsing:e0cab9e41247ec200b7eb6ec5cb159ec@ci.csphe.re/job/csphere-fe/lastSuccessfulBuild/artifact/dist/assets-master.tgz"

mongod_url="http://52.68.20.57/cos-files/mongo-3.0.3.tgz"
registry_url="http://52.68.20.57/cos-files/registry.img"

# remout /website
sudo mount -o remount,rw /website

mode=$1
case "${mode}" in
"all")
	sudo /bin/rm -rf ../build/*
	echo "csphere" | \
		openssl passwd -1 -stdin | \
		sudo tee /etc/shared_user_passwd.txt >/dev/null
	./setup_board --default --board=amd64-usr
	./csphere_iamcos.sh
	./build_packages --csphere  \
		--csphere_assets_path="${assets_url}" \
		--csphere_mongod_path="${mongod_url}" \
		--csphere_registry_path="${registry_url}"
		# --reuse_pkgs_from_local_boards \  # this flag is abondoned
		# --nogetbinpkg  # directely use built binary to save time
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
