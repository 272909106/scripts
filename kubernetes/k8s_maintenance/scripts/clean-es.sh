#!/bin/bash
cleanEs() {
        echo "clean teco-adp es cluster"
        time=`date -d "-1 month" +%Y.%m.*`
        command_half="curl -s -XDELETE http://192.168.1.93:32313/ks-logstash-log-$time"
        echo $command_half
        i=0
        while true
        do
        status=`$command_half`
        sleep 90
        let "i=i+1"
        echo $i
        if [[ "$i" -gt 3 ]] ;then
        exit
        fi
        done
}

cleanEs
