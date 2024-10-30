#!/bin/bash
set -xe
#设置主机名
#hostnamectl set-hostname adp-master

is_path_exist() {
	local path="$1"
	if [ ! -d "$path" ] ; then
	    mkdir -p $path
		return 0
	fi
}

systemArch=`uname -m`
if [ $systemArch == 'x86_64' ] ;then
	systemArch='x86'
elif [ $systemArch == 'aarch64' ] ;then
	systemArch='arm64'
fi
echo $systemArch

#host_ip=`hostname -I`
#host_ip=`hostname -I |awk '{ print $1}'`
#主机解析、私有仓库域名写入本地hosts
#echo "$host_ip  adp-master hub.registry2.com" >> /etc/hosts
cat >> /etc/hosts <<EOF
192.168.186.149 adp-master  hub.registry2.com
EOF



#设置主机名
hostnamectl set-hostname adp-master

#自动生成公钥、私钥
if [ ! -f ~/.ssh/id_rsa ] ; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -P ""
fi
#清理已存在的本机免密认证，以防报错

rm -rf ~/.ssh/authorized_keys

#配置免密
#expect -c '
#set timeout 10
#set password "T110226@jxj"
#
#
#spawn ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@adp-master 
#expect {
#    "password:" {
#        send "$password\r"
#    }
#    "Are you sure you want to continue connecting" {
#        send "yes\r"
#        exp_continue
#    }
#}
#expect eof
#'
#
#ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@adp-master

sshpassStatus=`rpm -qa |grep sshpass|wc -l`
if [ $sshpassStatus == 0 ];then
	rpm -ivh ./base-tools/$systemArch/sshpass-1.09-1.oe2203sp4.x86_64.rpm
	sshpass -p "T110226@jxj" ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@adp-master
else
	
	rpm -ivh ./base-tools/$systemArch/sshpass*.rpm || true
	sshpass -p "T110226@jxj" ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no root@adp-master
fi


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

