#!/bin/bash
set -xe
#设置主机名
#hostnamectl set-hostname adp-master
local_host_name=adp-master
local_host_passwd=T110226@jxj

is_path_exist() {
	local path="$1"
	if [ ! -d "$path" ] ; then
	    mkdir -p $path
		return 0
	fi
}

setHosts() {
cat >> /etc/hosts <<EOF
192.168.186.149 adp-master  hub.registry2.com
EOF
}


setHostname_key_nopasswd(){
#设置主机名
hostnamectl set-hostname $local_host_name

#自动生成公钥、私钥
if [ ! -f ~/.ssh/id_rsa ] ; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -P ""
fi
#清理已存在的本机免密认证，以防报错

rm -rf ~/.ssh/authorized_keys

#配置免密

sshpassStatus=`rpm -qa |grep sshpass|wc -l`
if [ $sshpassStatus == 0 ];then
	rpm -ivh ./rpm/base-tools/sshpass*.rpm
	sshpass -p "$local_host_passwd" ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@$local_host_name
# else
	
# 	rpm -ivh ./base-tools/$systemArch/sshpass*.rpm || true
# 	sshpass -p "T110226@jxj" ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@adp-master
fi
}


closeFirewall_swap(){
#防火墙、selinux关闭
systemctl stop firewalld &&
systemctl disable firewalld &&
setenforce 0 || true
sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

#注释swap分区
swapon -a 

# 使用sed注释掉fstab中的swap行
sed -i 's/^UUID=.*swap/#&/' /etc/fstab

cat /etc/fstab

swapon -a 

}

optimization_kernel() {

#k8s内核优化
if [ ! -f /etc/sysctl.d/k8s.conf ] ;then
	cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
vm.max_map_count = 262144
EOF

sed -i "s/net.ipv4.ip_forward=0/net.ipv4.ip_forward=1/" /etc/sysctl.conf

sysctl --system
fi

#开启启动此内核
if [ ! -f /etc/modules-load.d/containerd.conf ];then
	cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe br_netfilter
modprobe overlay
fi

#检查确认
lsmod | egrep br_netfilter||overlay

#k8s ipvs配置
if [ ! -f /etc/sysconfig/modules/ipvs.modules ];then
	cat > /etc/sysconfig/modules/ipvs.modules <<EOF
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
EOF
fi

}

main() {
setHosts
setHostname_key_nopasswd
closeFirewall_swap
optimization_kernel
}

main