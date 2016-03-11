#!/bin/sh
set -e

# detect real in use commit
eval "$(awk '/^[ \t]*CROS_WORKON_COMMIT=/' ../third_party/coreos-overlay/csphere/csphere/csphere-9999.ebuild)"
if [ "${CROS_WORKON_COMMIT}" != "-" ]; then
	rm -rf /tmp/.csphere.tmp
	git clone ../third_party/csphere/ /tmp/.csphere.tmp
	git -C /tmp/.csphere.tmp checkout ${CROS_WORKON_COMMIT} VERSION.txt
	version=$(cat /tmp/.csphere.tmp/VERSION.txt)
else
	version=$(cat ../third_party/csphere/VERSION.txt)
fi

SUBFFIX=$(echo ${version:-master}|cut -d. -f1,2)
assets_url="http://tsing:e0cab9e41247ec200b7eb6ec5cb159ec@ci.csphe.re/job/csphere-fe/lastSuccessfulBuild/artifact/dist/assets-${SUBFFIX}.tgz"

mongod_url="http://52.68.20.57/cos-files/mongo-3.0.3.tgz"
registry_url="http://52.68.20.57/cos-files/registry.img"
kernel_url="http://52.68.20.57/cos-files/kernel.tbz2"
firmware_url="http://52.68.20.57/cos-files/firmware.tbz2"
glibc_url="http://builds.developer.core-os.net/boards/amd64-usr/835.13.0/pkgs/sys-libs/glibc-2.20-r3.tbz2"
etcd2_url="http://builds.developer.core-os.net/boards/amd64-usr/960.0.0/pkgs/dev-db/etcd-2.2.5.tbz2"
golang_url="http://builds.developer.core-os.net/boards/amd64-usr/899.8.0/pkgs/dev-lang/go-1.4.3.tbz2"

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
	./csphere_dlprebuild_kernel.sh "${kernel_url}" "${firmware_url}"
	./csphere_dlprebuild_glibc.sh "${glibc_url}"
	./csphere_dlprebuild_etcd2.sh "${etcd2_url}"
	./csphere_dlprebuild_go.sh "${golang_url}"
	./csphere_replace.sh
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

echo "create tarball for binaries required by rpm package"
sudo mkdir -pv /tmp/rpm-binaries/
sudo cp -avf \
	/tmp/csphere-quota \
	/tmp/csphere \
	/tmp/registry.img \
	/tmp/csphere-mongo/bin/{mongo,mongod,mongodump,mongoexport,mongoimport,mongorestore,mongostat} \
	/tmp/cspherectl \
	/tmp/net-plugin \
	/tmp/csphere-logger \
	/tmp/prometheus \
	/tmp/skydns \
	/tmp/docker \
	/tmp/rpm-binaries/
sudo curl -sS $etcd2_url -o /tmp/etcd-2.2.5.tbz2
sudo tar -xf /tmp/etcd-2.2.5.tbz2 -C /tmp
sudo mv -vf /tmp/usr/bin/* /tmp/rpm-binaries/
dest=$(pwd)/../build/images/amd64-usr/latest/rpm-binaries.tgz
pushd /tmp
sudo tar -czvf $dest rpm-binaries/
popd

echo "create csphere product info txt"
sudo cp -avf /tmp/csphere_product_version.txt ../build/images/amd64-usr/latest/

# create tarball for cos local update
dest=$(pwd)/../build/images/amd64-usr/latest/cos-update.tgz
sudo mkdir -pv /tmp/bin/
sudo cp -avf /tmp/{csphere,net-plugin,csphere-logger,csphere-quota,docker} /tmp/bin
sudo cp -avf ./cos_update.bash /tmp/
pushd /tmp/
sudo tar -czvf $dest bin/ units/ cos_update.bash csphere_product_version.txt
popd
