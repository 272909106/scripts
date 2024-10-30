#!/bin/bash
set -xe
cleanPath(){
	if [ ! -d $1 ]
        then 
          mkdir -p $1 && cd $1
        else 
	  rm -rf $1
	  mkdir -p $1 && cd $1
        fi
}
copyPath(){
if [ -d $1 ];then
	cp -r $1 .
fi
}

copyFile(){
if [ -f $1 ];then
        cp $1 .
fi
}

decorator() {
  cleanPath $2
  $1
  cd $currentPath
}
currentPath=$PWD
maintenancePath='/data/maintenance'
dockerConfig='/etc/docker/daemon.json'
keepalivedCfg='/etc/keepalived/keepalived.conf'
haproxyCfg='/etc/haproxy/haproxy.cfg'


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

bakDockerConfig(){
copyFile $dockerConfig 
}

bakMaintenance(){
copyPath $maintenancePath/scripts
copyPath $maintenancePath/bin
}

bakKeepalivedHaproxy(){
copyFile $keepalivedCfg
scp  adp-master-2:/etc/keepalived/keepalived.conf keepalived-master-0002.conf
scp  adp-master-3:/etc/keepalived/keepalived.conf keepalived-master-0003.conf
copyFile $haproxyCfg 
}

bakCrontab(){
crontab -l >./crontab
}

decorator bakTecoAdp kubesphere-backup-yaml
decorator bakDockerConfig docker-config
decorator bakMaintenance maintenance
decorator bakKeepalivedHaproxy keepalived-haproxy
bakCrontab
