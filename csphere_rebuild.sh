#!/bin/sh
set -e

version=$(cat ../third_party/csphere/VERSION.txt)
SUBFFIX=$(echo ${version:-master}|cut -d. -f1,2)
assets_url="http://tsing:e0cab9e41247ec200b7eb6ec5cb159ec@ci.csphe.re/job/csphere-fe/lastSuccessfulBuild/artifact/dist/assets-${SUBFFIX}.tgz"

mongod_url="http://52.68.20.57/cos-files/mongo-3.0.3.tgz"
registry_url="http://52.68.20.57/cos-files/registry.img"
kernel_url="http://52.68.20.57/cos-files/kernel.tbz2"
firmware_url="http://52.68.20.57/cos-files/firmware.tbz2"

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
	./csphere_prepare_kernel.sh "${kernel_url}" "${firmware_url}"
	./csphere_iamcos.sh
	sudo mkdir -p mkdir /tmp/csphere-product-version/
	./build_packages --csphere  \
		--csphere_assets_path="${assets_url}" \
		--csphere_mongod_path="${mongod_url}" \
		--csphere_registry_path="${registry_url}"
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

if [ -e /tmp/csphere_product_version.txt ]; then
	sudo cp -af /tmp/csphere_product_version.txt ../build/images/amd64-usr/latest/
fi
