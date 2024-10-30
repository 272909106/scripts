#!/bin/bash
set -xe

currentPath=$PWD
maintenancePath='/data/maintenance'
dockerConfig='/etc/docker/daemon.json'
keepalivedCfg='/etc/keepalived/keepalived.conf'
haproxyCfg='/etc/haproxy/haproxy.cfg'

#清理路径并创建、进入路径
cleanPath(){
	if [ ! -d $1 ]
        then 
          mkdir -p $1 && cd $1
        else 
	  rm -rf $1
	  mkdir -p $1 && cd $1
        fi
}

#拷贝路径
copyPath(){
if [ -d $1 ];then
	cp -r $1 .
fi
}

#拷贝文件
copyFile(){
if [ -f $1 ];then
        cp $1 .
fi
}

#装饰器函数
decorator() {
  cleanPath $2
  $1
  cd $currentPath
}

#备份adp
bakTecoAdp(){
for n in `kubectl get ns |grep -v NAME |awk  '{print $1}'`;
do mkdir $n ;cd $n
object="deploy statefulset daemonset configmap svc secrets"
for obj in $object ;
do
  mkdir $obj
  for i in `kubectl get $obj -n $n  |grep -v NAME |awk  '{print $1}'` ; do kubectl get $obj/$i -n $n -o yaml > $obj/$i.yaml ; done
done
cd ../;
done
find ./ -type d -empty |xargs rmdir
}

#备份docker config
bakDockerConfig(){
copyFile $dockerConfig 
}

#备份维护脚本
bakMaintenance(){
copyPath $maintenancePath/scripts
copyPath $maintenancePath/bin
}

#备份keepalived 和 haproxy
bakKeepalivedHaproxy(){
copyFile $keepalivedCfg
scp  adp-master-2:/etc/keepalived/keepalived.conf keepalived-master-0002.conf
scp  adp-master-3:/etc/keepalived/keepalived.conf keepalived-master-0003.conf
copyFile $haproxyCfg 
}

#备份crontab定时任务
bakCrontab(){
crontab -l >./crontab
}

#备份host
backHost(){
cat /etc/hosts >./hosts
}

main(){
decorator bakTecoAdp kubesphere-backup-yaml
decorator bakDockerConfig docker-config
decorator bakMaintenance maintenance
decorator bakKeepalivedHaproxy keepalived-haproxy
bakCrontab
backHost
}

main