#!/bin/bash
DCP=/data/docker/containers

cleanImages(){
	echo "clean docker images"
	docker image prune -a -f
}
cleanDockerDf(){
	echo "clean docker df"
	docker system prune -f
}
cleanDockerLog(){
	echo "==================== start clean docker containers logs =========================="
	logs=$(find $DCP -name *-json.log)
	for log in $logs
	  do
		size=`du -sh $log | grep G`
		if [  "$size" ];then
		   echo "clean logs : $log"
		   echo $size
		   cat /dev/null > $log
		fi
	  done
	echo "==================== end clean docker containers logs   =========================="
}


cleanImages
cleanDockerDf
cleanDockerLog
