#!/bin/sh
set -e
name="etcd-bak-"`date "+%Y-%m-%d-%H-%M-%S"`
storePath="/data/maintenance/backup/etcd/"
#检查路径，没有则创建
if [ ! -d $storePath ]
then 
   mkdir -p $storePath
fi
#check etcdctl binary file
/usr/local/sbin/etcdctl version
#备份etcd
#tar -czvf "$storePath"$name".tar.gz" /var/lib/etcd --warning=no-file-changed

ETCDCTL_API=3 /usr/local/sbin/etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save $storePath/$name.db

#check the backup file
/usr/local/sbin/etcdctl snapshot status $storePath/$name.db -w table

#清理大于60天的备份
#find $storePath -type f -name "*.db" -mtime +60 -exec rm -f {} + | head -n -10 
#保留最新的10个文件
find $storePath -type f -name "*.db" | head -n -10 |xargs rm -f
#恢复etcd，需要清空配置文件，然后才能恢复文件及数据
#find $storePath -type f -name "*.db" |tail -n 1 |xargs etcdctl snapshot restore --data-dir /var/lib/etcd
