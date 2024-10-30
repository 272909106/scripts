#!/bin/bash

# 开启调试模式，并将所有输出同时保存到日志文件和控制台
LOG_FILE="adp-setup.log"
exec > >(tee -a $LOG_FILE) 2>&1  # 将标准输出和错误输出都保存到文件，并显示到控制台


set -xe
#部署的docker版本包
dockerPack=docker-27.3.1.tgz
#部署的containerd的版本包
containerdPack=cri-containerd-cni-1.7.22-linux-amd64.tar.gz
#yq的调用路径
yq_yaml=/usr/local/bin/yq
#docker的网络配置
dockerNet=172.19.0.1/16
#主机的网络接口
hostNetInt=ens160
#vip的地址
vipAddr=192.168.186.202
#部署主机ip
deploy_host_ip=192.168.186.149
#部署主机名
deploy_host_name=adp-master
#kubeadm的配置文件名
k8s_config_path=./config/kubernetes/
kubeadm_config=$k8s_config_path"kubeadm-config-ha.yaml"
#k8s的存储配置文件名
kube_storageclass=$k8s_config_path"kube-storageclass-12615.yaml"
#k8s网络的文件名
kube_flannel=$k8s_config_path"kube-flannel.yml"

#kubesphere config
kubesphere_config_path=./config/kubesphere/
kubesphere_installer=$kubesphere_config_path"kubesphere-installer.yaml"
kubesphere_cluster_config=$kubesphere_config_path"cluster-configuration.yaml"

#所有主机的ip及主机名
# v0="[\"192.168.186.202\",\"adp-master\",\"192.168.186.147\"]"
#通过函数获取替换
#k8s的pod网络
podNet=10.245.0.0/16
#k8s的service网络
serviceNet=10.244.0.0/16
#k8s的cluster dns的地址
cluserDns=[\"10.244.0.10\"]
#nfs存储的路径
nfs_path=/data/share


is_path_exist() {
	local path="$1"
	if [ ! -d "$path" ] ; then
	    mkdir -p $path
		return 0
	fi
}

#deploy docker

deploy_docker() {
	if [ ! -f /usr/local/bin/docker ];then
	#untar docker
	tar zxvf ./pack/docker/$dockerPack  --strip-components=1  -C /usr/local/bin/  docker/
	#check docker config path
	is_path_exist /etc/docker

	#cp daemon.json /etc/docker/
	cat >/etc/docker/daemon.json <<EOF
{ 
 "insecure-registries": ["http://hub.registry2.com:32005"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "bip": "$dockerNet"
}
EOF
	cp ./config/docker/docker.service /etc/systemd/system/
	systemctl enable --now docker.service
	systemctl restart docker 
	fi


}


#### deploy containerd ####
deploy_containerd() {
	if [ ! -f /usr/local/sbin/runc ];then

	#untar containerd 
	tar zxvf ./pack/containerd/$containerdPack -C /
	
	#cp containerd config 	
	#\cp -r crictl.yaml /etc/
	cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
pull-image-on-create: false
disable-pull-on-run: false
EOF

	#clear old network config
	rm -rf /etc/cni/net.d/*
	
	#configure containerd insecure registry
	is_path_exist /etc/containerd/certs.d/
	if [ ! -d /etc/containerd/certs.d/hub.registry2.com\:32005 ];then
		is_path_exist /etc/containerd/certs.d/hub.registry2.com\:32005
		cat  > /etc/containerd/certs.d/hub.registry2.com:32005/hosts.toml <<EOF
server = "http://hub.registry2.com:32005"

[host."http://hub.registry2.com:32005"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF
	fi
	
	
	#cover containerd config
	is_path_exist /data/containerd/
	\cp ./config/containerd/config.toml /etc/containerd/
	
	#set buildkit,containerd start for start machine
	systemctl daemon-reload
	systemctl enable --now containerd.service
	systemctl restart containerd.service
	fi

}



#一键安装 kubeadm、kubelet、kubect

deploy_kubelet() {
set +e
output=$(rpm -qa |grep kubelet)  
set -e
# 检查命令输出-n有结果-z没结果
if [ -z "$output" ]; then  
	systemNum=`cat /etc/openEuler-release  |awk '{print $3}' |awk -F '.' '{print $1}'`
	if [ $systemNum -eq 22 ];then
		rpm -ivh ./rpm/kubelet/openeuler22/*.rpm || true
	elif [ $systemNum -eq 24 ]; then
		rpm -ivh ./rpm/kubelet/openeuler24/*.rpm || true
	fi
	systemctl enable kubelet.service --now
fi
}


#安装ipvs
deploy_ipvs() {
set +e
output=$(rpm -qa |grep ipvsadm)  
set -e
# 检查命令输出-n有结果-z没结果
if [ -z "$output" ]; then  
	rpm -ivh ./rpm/ipvs/*.rpm || true
fi
}



deploy_registry() {
if [ ! -d /data/registry/docker ];then
	is_path_exist /data/registry/
        cp -r ./registry /data/
	docker  load -i ./images/registry_2_amd64.tar
	docker run -d -p 32005:5000 --restart always -v /data/registry:/var/lib/registry  --name registry registry:2
fi
}


deploy_hundred_certs() {
#生成百年CA证书
if [ ! -f /etc/kubernetes/pki/ca.crt ];then
	# bash generate_ca.sh
	certs_path="/etc/kubernetes/pki/"
	etcd_certs_path=$certs_path"etcd"
	is_path_exist "$etcd_certs_path"
	ca_name=("ca" "front-proxy-ca")
	for c in ${ca_name[@]} ; do openssl genrsa -out $certs_path$c.key 2048 ; openssl req -x509 -new -nodes -key $certs_path$c.key -subj "/CN=kubernetes" -days 36500 -out $certs_path$c.crt ; done

	openssl genrsa -out $etcd_certs_path/ca.key 2048
	openssl req -x509 -new -nodes -key $etcd_certs_path/ca.key -subj "/CN=kubernetes" -days 36500 -out $etcd_certs_path/ca.crt
fi
}



#配置kube-vip static pod
#https://kube-vip.io/docs/installation/static/#generating-a-manifest

deploy_kubevip() {
\cp ./config/kubernetes/kube-vip.yaml /etc/kubernetes/manifests/

if [ ! -f /usr/local/bin/yq ];then
	tar xvf ./pack/base-tools/yq_linux_amd64.tar.gz  -C /usr/local/bin/ ./yq_linux_amd64
	mv /usr/local/bin/yq_linux_amd64 /usr/local/bin/yq
fi
$yq_yaml -i '.spec.containers[0].env[] |= (select(.name == "vip_interface").value = "'$hostNetInt'")' /etc/kubernetes/manifests/kube-vip.yaml
$yq_yaml  '.spec.containers[0].env[] | select(.name == "vip_interface")' /etc/kubernetes/manifests/kube-vip.yaml

$yq_yaml -i '.spec.containers[0].env[] |= (select(.name == "address").value = "'$vipAddr'")' /etc/kubernetes/manifests/kube-vip.yaml
$yq_yaml '.spec.containers[0].env[] | select(.name == "address")' /etc/kubernetes/manifests/kube-vip.yaml

}

modify_kubeadm_yaml() {
	case $1 in
		nl)
			#修改值
			# $yq_yaml e '('$1' | select(di == '$2')) = "'$3'"' -i $kubeadm_config
			$yq_yaml e '('$2') = "'$3'"' -i $4 
			#查看值
			# $yq_yaml eval ''$1' | select(di == '$2')'  $kubeadm_config
			$yq_yaml eval ''$2''  $4
			;;
		list)
			#修改值
			# $yq_yaml e '('$1' | select(di == '$2')) = "'$3'"' -i $kubeadm_config
			$yq_yaml e '('$2') = '$3'' -i $4 
			#查看值
			# $yq_yaml eval ''$1' | select(di == '$2')'  $kubeadm_config
			$yq_yaml eval ''$2''  $4
			;;
		json)
			# $yq_yaml e -i '(. | select(di == 4) | .data."net-conf.json") |= (fromjson | .Network = "'$podNet'" | tojson)' $kube_flannel
			# $yq_yaml e '.data."net-conf.json" | select(di == 4) | fromjson | .Network' $kube_flannel
			$yq_yaml e ''$2' = "'$3'" |tojson)' -i $4 
			new_condication=$(echo "$2" | sed 's/|=(/|/g')
			$yq_yaml eval ''$new_condication''  $4			
			;;
	esac
}

#modify_kubeadm_append_yaml(){
	#修改值
#	$yq_yaml e '('$1' | select(di == '$2')) += "'$3'"' -i $kubeadm_config
	#查看值
#	$yq_yaml eval ''$1' | select(di == '$2')'  $kubeadm_config
#}

format_hosts() {
    local output='['
    while IFS= read -r line; do
        IFS=' ' read -r -a fields <<< "$line"
        for field in "${fields[@]}"; do
            output+="\"$field\","
        done
    done < hosts.txt

    # 移除最后一个逗号
    output=${output%,}
    output+=']'

    # 转义双引号
    # output=$(echo "$output" | sed 's/"/\\"/g')

    # 返回结果
    echo "$output"
}

modify_kubeadm_config () {
	#第一个文件修改
	#修改并获取修改后的部署主机ip
	#$yq_yaml e '(.localAPIEndpoint.advertiseAddress | select(di == 0)) = "'$deploy_host_ip'"' -i $kubeadm_config
	#$yq_yaml eval '.localAPIEndpoint.advertiseAddress | select(di == 0)'  $kubeadm_config
	modify_kubeadm_yaml "nl" ".|select(.kind==\"InitConfiguration\")|.localAPIEndpoint.advertiseAddress" $deploy_host_ip $kubeadm_config
	
	#修改后并获取部署主机明
	#$yq_yaml e '(.nodeRegistration.name | select(di == 0)) = "'$deploy_host_name'"' -i $kubeadm_config
	#$yq_yaml eval '.nodeRegistration.name | select(di == 0)'  $kubeadm_config
	modify_kubeadm_yaml "nl" ".|select(.kind==\"InitConfiguration\")|.nodeRegistration.name" $deploy_host_name $kubeadm_config
	
	#第三个文件修改
	#$yq_yaml e '(.controlPlaneEndpoint | select(di == 2)) = "'$vipAddr:6443'"' -i $kubeadm_config
    #$yq_yaml eval '(.controlPlaneEndpoint | select(di == 2))'  $kubeadm_config
	modify_kubeadm_yaml "nl" ".|select(.kind==\"ClusterConfiguration\")|.controlPlaneEndpoint" $vipAddr:6443 $kubeadm_config
	
	#修改certsans
	#yq e '(.apiServer.certSANs | select(di == 2)) += ["192.168.186.200","adp-master","192.168.186.138","adp-vip"]' -i kubeadm-config-ha.yaml
    #yq eval '(.apiServer.certSANs | select(di == 2))'  kubeadm-config-ha.yaml
	#modify_kubeadm_yaml ".apiServer.certSANs" 2 $v0
	#modify_kubeadm_append_yaml ".apiServer.certSANs" 2 [$v1]
	#modify_kubeadm_append_yaml ".apiServer.certSANs" 2 [$v2]
	#modify_kubeadm_append_yaml ".apiServer.certSANs" 2 [$v3]
	
	# $yq_yaml e '(.apiServer.certSANs | select(di == 2)) = '$v0'' -i $kubeadm_config
	# $yq_yaml eval '(.apiServer.certSANs | select(di == 2))'  $kubeadm_config
	modify_kubeadm_yaml "list" ".|select(.kind==\"ClusterConfiguration\")|.apiServer.certSANs" $(format_hosts) $kubeadm_config
	
	#修改flannel 网络
	modify_kubeadm_yaml "nl" ".|select(.kind==\"ClusterConfiguration\")|.networking.podSubnet" $podNet $kubeadm_config
	modify_kubeadm_yaml "nl" ".|select(.kind==\"ClusterConfiguration\")|.networking.serviceSubnet" $serviceNet $kubeadm_config
	
	#修改clusterDns
	# $yq_yaml e '(.clusterDNS | select(di == 3)) = '$cluserDns'' -i $kubeadm_config
	# $yq_yaml eval '(.clusterDNS | select(di == 3))'  $kubeadm_config
	modify_kubeadm_yaml "list" ".|select(.kind==\"KubeletConfiguration\")|.clusterDNS" $cluserDns $kubeadm_config
	
	#修改flannel网络
	$yq_yaml e -i '(. | select(di == 4) | .data."net-conf.json") |= (fromjson | .Network = "'$podNet'" | tojson)' $kube_flannel
	$yq_yaml e '.data."net-conf.json" | select(di == 4) | fromjson | .Network' $kube_flannel
	
	modify_kubeadm_yaml "json" "(.|select(.kind==\"ConfigMap\").data.\"net-conf.json\")|=(fromjson|.Network" $podNet $kube_flannel
	
}



deploy_k8s_flannel() {
#根据kubeadm的配置文件创建集群
#kubeadm config print init-defaults > kubeadm-config.yaml

#k8s_result=$(kubeadm init --config=kubeadm-config.yaml --ignore-preflight-errors=SystemVerification)
#echo $k8s_result
#kubeadm init --config=kubeadm-config.yaml --ignore-preflight-errors=SystemVerification
kubeadm init --config=kubeadm-config-ha.yaml --ignore-preflight-errors=SystemVerification

is_path_exist $HOME/.kube
\cp  /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

sleep 1

#create flannel network
kubectl apply -f $kube_flannel
}



#check setup k8s cluster and flannel
#kubectl get pods,svc,ds,deployment -A -o wide

#check k8s certs
#kubeadm certs check-expiration

#clear nerdctl network for flannel
#sleep 1
#kubectl delete pods --all -n kube-system
#kubectl delete pods -n kube-system -l k8s-app=kube-dns

deploy_nfs() {
#accept deploy pod to master
kubectl taint nodes $deploy_host_name node-role.kubernetes.io/control-plane- || true

#configure local nfs server 
if [ ! -d /data/share ];then
	is_path_exist $nfs_path
	chmod -R 666 $nfs_path
	
	#general nfs config
	cat >/etc/exports <<EOF
/data/share *(rw,sync,insecure,no_subtree_check,no_root_squash)
EOF

	#setup nfs-utils
	rpm -ivh ./rpm/nfs/*.rpm 
	
	# configure nfs start up from machine
	systemctl start rpcbind  && systemctl enable rpcbind
	systemctl start nfs  &&  systemctl enable nfs
	
	#check nfs 
	showmount -e localhost
	
fi

}

# modify_kubeadm_yaml_2_select() {
	# #if [ $5 == "value"]:then
	# #	$yq_yaml eval '('$1' | select(.name == "'$2'").value) = "'$3'"' -i $4
	# #	$yq_yaml eval ''$1' | select(.name == "'$2'")'  $4
	# #else
	# #	
	# #fi
	# case $1 in
	  # value)
		# $yq_yaml eval '(.| select(.kind == "Deployment") | '$2' | select(.name == "'$3'").value) = "'$4'"' -i $5
		# $yq_yaml eval 'select(. | .kind == "Deployment") | '$2' | select(.name == "'$3'")'  $5
		# ;;
	  # modify)
	    # #yq eval '.spec.template.spec.volumes[].nfs.server ' kube-storageclass-12615.yaml
		# #yq eval '(.spec.template.spec.volumes[].nfs.server)="192.168.186.144"' -i kube-storageclass-12615.yaml
		# $yq_yaml eval '(. | select(.kind == "Deployment") | '$2')="'$3'"' -i $4
		# $yq_yaml eval '. | select(.kind == "Deployment") | '$2'' $4
		# ;;
	# esac
# }

deploy_storage() {
	#修改nfs server地址
	#yq eval '(.spec.template.spec.containers[].env[] | select(.name == "NFS_SERVER").value) = "'$deploy_host_ip'"' -i kube-storageclass-12615.yaml
	#yq eval '.spec.template.spec.containers[].env[] | select(.name == "NFS_SERVER")'  kube-storageclass-12615.yaml
	# modify_kubeadm_yaml_2_select "value" ".spec.template.spec.containers[].env[]" "NFS_SERVER" $deploy_host_ip $kube_storageclass
	# modify_kubeadm_yaml_2_select "value" ".spec.template.spec.containers[].env[]" "NFS_PATH" $nfs_path $kube_storageclass
	
	# modify_kubeadm_yaml_2_select "modify" ".spec.template.spec.volumes[0].nfs.server" $deploy_host_ip $kube_storageclass
	# modify_kubeadm_yaml_2_select "modify" ".spec.template.spec.volumes[0].nfs.path" $nfs_path $kube_storageclass
	
	modify_kubeadm_yaml "nl" ".|select(.kind==\"Deployment\")|.spec.template.spec.containers[].env[]|select(.name==\"NFS_SERVER\").value" $deploy_host_ip $kube_storageclass
	modify_kubeadm_yaml "nl" ".|select(.kind==\"Deployment\")|.spec.template.spec.containers[].env[]|select(.name==\"NFS_PATH\").value" $nfs_path $kube_storageclass
	
	modify_kubeadm_yaml "nl" ".|select(.kind==\"Deployment\")|.spec.template.spec.volumes[0].nfs.server" $deploy_host_ip $kube_storageclass
	modify_kubeadm_yaml "nl" ".|select(.kind==\"Deployment\")|.spec.template.spec.volumes[0].nfs.path" $nfs_path $kube_storageclass
	
	#setup storageclass
	kubectl apply -f $kube_storageclass
	kubectl get sc 
	kubectl get pods -A
}


optimization_nfs() {
if [ ! -f /etc/nfs.conf.bak ];then
	NFS_CONF="/etc/nfs.conf"
	BACKUP_CONF="${NFS_CONF}.bak"

	# 备份原始配置文件
	cp $NFS_CONF $BACKUP_CONF

	# 新配置内容
	MOUNTD_CONFIG="[mountd]\nrpc.mountd.timeout=10\nrpc.mountd.retry_count=1\n"
	NFSD_CONFIG="[nfsd]\nrpc.nfsd.timeout=10\nrpc.nfsd.retry_count=1"

	# 替换 mountd 配置
	if grep -q '\[mountd\]' $NFS_CONF; then
		sed -i "/\[mountd\]/c\\$MOUNTD_CONFIG" $NFS_CONF
	else
		echo -e "$MOUNTD_CONFIG" >> $NFS_CONF
	fi

	# 替换 nfsd 配置
	if grep -q '\[nfsd\]' $NFS_CONF; then
		sed -i "/\[nfsd\]/c\\$NFSD_CONFIG" $NFS_CONF
	else
		echo -e "$NFSD_CONFIG" >> $NFS_CONF
	fi

	# 重启 NFS 服务
	sudo systemctl restart nfs

	echo "NFS 配置已更新，服务已重启。"
	cat /etc/nfs.conf |grep -v '#'
fi
}

#deploy teco-adp

deploy_adp() {
#旧的adp
#kubectl create -f 02-teco-adp-installer.yaml   
#kubectl create -f 03-cluster-configuration.yaml

#new的kubesphere
kubectl create -f $kubesphere_installer
kubectl create -f $kubesphere_cluster_config

#kubectl get pod ks-installer-65d4775bd4-cz6zq -o jsonpath='{.status.phase}' -n kubesphere-system

KEYWORD="P@88w0rd"
while true; do
    status=$(kubectl get pod $(kubectl get pod -n kubesphere-system -l app=ks-installer -o jsonpath='{.items[0].metadata.name}') -o jsonpath='{.status.phase}' -n kubesphere-system)
    if [[ "$status" == "Running" ]]; then		
		kubectl logs -n kubesphere-system $(kubectl get pod -n kubesphere-system -l app=ks-installer -o jsonpath='{.items[0].metadata.name}') -f  | while read -r line
		do
			set +x
			echo "$line" # 打印日志

			# 检查是否包含特定字符串
			if [[ "$line" == *"$KEYWORD"* ]]; then
				echo "检测到关键字 '$KEYWORD'，退出日志监控。"
				set -x
				#修改opensearch-cluster镜像的私有仓库
				kubectl patch statefulset opensearch-cluster-master  -n kubesphere-logging-system    --type='json'   -p='[{"op": "replace", "path": "/spec/template/spec/initContainers/0/image", "value":"hub.registry2.com:32005/library/busybox:latest"}]'

				kubectl patch statefulset opensearch-cluster-data  -n kubesphere-logging-system    --type='json'   -p='[{"op": "replace", "path": "/spec/template/spec/initContainers/0/image", "value":"hub.registry2.com:32005/library/busybox:latest"}]'
				pkill -P $$  # 终止所有子进程
				exit 0
			fi
		done
    else
        echo "ks-installer status : $status not ok"
        sleep 8
    fi
done
}





main() {
deploy_docker
deploy_containerd
deploy_kubelet
deploy_ipvs
deploy_registry
deploy_hundred_certs
deploy_kubevip
modify_kubeadm_config
deploy_k8s_flannel
deploy_nfs
optimization_nfs
deploy_storage
deploy_adp
}

main