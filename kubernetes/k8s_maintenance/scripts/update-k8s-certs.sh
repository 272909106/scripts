#!/bin/bash
set -ex
#update all certs
/usr/bin/kubeadm certs renew all
#copy lastet new k8s config
cp /etc/kubernetes/admin.conf /root/.kube/config
#kubectl get pods -n kube-system |grep kube-apiserver |awk '{print$1}' |grep -v  NAME |xargs kubectl delete pods -n kube-system
#kubectl get pods -n kube-system |grep kube-controller-manager |awk '{print$1}' |grep -v  NAME |xargs kubectl delete pods -n kube-system
#kubectl get pods -n kube-system |grep kube-scheduler |awk '{print$1}' |grep -v  NAME |xargs kubectl delete pods -n kube-system
#kubectl get pods -n kube-system |grep etcd |awk '{print$1}' |grep -v  NAME |xargs kubectl delete pods -n kube-system
#delete  old k8s component 
kubectl delete pod -n kube-system -l component=kube-apiserver
kubectl delete pod -n kube-system -l component=kube-controller-manager
kubectl delete pod -n kube-system -l component=kube-scheduler
kubectl delete pod -n kube-system -l component=etcd
#check updated certs date
sleep 1
kubeadm certs check-expiration
