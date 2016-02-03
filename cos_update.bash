#!/bin/bash
set -ex

basedir=$(cd $(dirname ${BASH_SOURCE[*]}); pwd -P)
cd $basedir


if [ "$(id -u)" != "0" ]; then
	echo "root privilege required"
	exit 1
fi

newbin="/opt/newbin"
if [ ! -d "${newbin}" ]; then
	mkdir -p "${newbin}"
fi

test -d units/ -a -d bin/
test -e /etc/csphere/inst-opts.env

ctlcomps=(
	"csphere-prepare"
	"csphere-agent"
	"csphere-controller"
	"csphere-docker-controller"
	"csphere-etcd2-controller"
	"csphere-prometheus"
	"csphere-mongodb"
)

agentcomps=(
	"csphere-prepare"
	"csphere-agent"
	"csphere-docker-agent"
	"csphere-dockeripam"
	"csphere-skydns"
	"csphere-etcd2-agent"
)

function updatectl() {
	systemctl stop ${ctlcomps[*]} || true
	cp -avf bin/{csphere,docker} $newbin/
	for x in ${ctlcomps[*]}
	do
		cp -avf units/${x}.service /etc/systemd/system/
	done
	cp -avf units/csphere-{prepare,agent-after}.bash /etc/csphere/
	np=$newbin/csphere
	sed -i 's#/bin/csphere#'$np'#g' /etc/systemd/system/csphere-{agent,controller}.service
	np=$newbin/docker
	sed -i 's#/usr/bin/docker#'$np'#g' /etc/systemd/system/csphere-docker-controller.service
	systemctl daemon-reload
}

function updateagent() {
	systemctl stop ${agentcomps[*]} || true
	cp -avf bin/{csphere,docker,net-plugin,csphere-quota} $newbin/
	for x in ${agentcomps[*]}
	do
		cp -avf units/${x}.service /etc/systemd/system/
	done
	cp -avf units/csphere-{prepare,agent-after,docker-agent-after,skydns-startup}.bash /etc/csphere/
	np=$newbin/csphere
	sed -i 's#/bin/csphere#'$np'#g' /etc/systemd/system/csphere-agent.service
	np=$newbin/docker
	sed -i 's#/usr/bin/docker#'$np'#g' /etc/systemd/system/csphere-docker-agent.service
	np=$newbin/net-plugin
	sed -i 's#/bin/net-plugin#'$np'#g' /etc/systemd/system/csphere-dockeripam.service
	systemctl daemon-reload
}

. /etc/csphere/inst-opts.env

if [ "${COS_ROLE}" == "controller" ]; then
	updatectl
elif [ "${COS_ROLE}" == "agent" ]; then
	updateagent
else
	echo "cos role: [${COS_ROLE}] unknown"
	exit 1
fi
