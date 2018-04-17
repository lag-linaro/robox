#!/bin/bash

# Use `<scriptname> -n <num_instances>` to run

ROBOX=$PWD/robox
ROBOXFAILLOG=/tmp/robox-faillog
SCALABILITYFAILLOG=/tmp/scalability-faillog

maxinstances=254
instancestostart=1    # Start 1 instance by default
baseinstancetostart=0 # Start from 1 by default

FAILED=255
QUIET="-q"

function stop_instances {
    local result
    local instance
    local dockerdangle

    if [ "$FORCESTOPALL" == "" ]; then
	echo "Scanning for instances to stop"
    else
	echo -n "Forcibly stopping instances $((1+$baseinstancetostart)) "
	echo    "through $(($instancestostart+$baseinstancetostart))"
    fi

    for ((i=1; i<=$instancestostart; i++)); do
	instance=$(($i+$baseinstancetostart))
	if [ "$FORCESTOPALL" == "" ]; then
	    result=$(ps aux | grep "instance$i" | grep -v grep)
	    if [ "$result" != "" ]; then
		echo "Stopping instance $instance"
		$ROBOX stop $instance -f -v $QUIET &
	    fi
	else
	    $ROBOX stop $instance -f -v $QUIET &
	fi
    done

    echo "Waiting for all instances to stop ..."
    wait

    dockerdangle=`docker ps -aq --no-trunc -f status=exited`
    if [ "$dockerdangle" != "" ]; then
	echo "Removing any dangling/exited Docker instances"
	docker ps -aq --no-trunc -f status=exited | xargs docker rm
	sleep .2
    fi
}

function start_instances {
    echo "Starting $instancestostart instances"
    for ((i=1; i<=instancestostart; i++)); do
	instance=$(($i+$baseinstancetostart))
	$ROBOX start $instance $QUIET &
    done
}

function count_instances {
    local count=0
    local last=$count
    local sleeptime=1
    local iterations=0
    local timeout=0
    local lines=0

    if [ $instancestostart -lt 15 ]; then
	timeout=20
    else
	timeout=$(($instancestostart * 1))
    fi

    count=0
    while [ $count -lt $(($instancestostart+$baseinstancetostart)) ]; do
	count=$(ps aux | grep "x11vnc" | grep -v grep | wc -l)

	sleep $sleeptime

	if [ $count -gt $last ]; then
	    echo "$count instances now up"
	    last=$count
	fi

	iterations=$(($iterations+1))
	if [ $(($iterations*$sleeptime)) -gt $timeout ]; then
	    echo "FAILED: One or more instances did not come up in time"
	    return $FAILED
	fi

	# Also include the broken instances for the break
	lines=$(wc -l $ROBOXFAILLOG | cut -d' ' -f1)
	count=$(($count+$lines))
    done
}

function retry {
    instance=$1

    echo "Trying to re-start failed instance $instance"
    $ROBOX stop $instance -f -v $QUIET
    $ROBOX start $instance $QUIET
}

function main {
    local count=1 # Meaningless value to ensure loop is initially executed

    rm -f $ROBOXFAILLOG
    touch $ROBOXFAILLOG

    if [ "$DONTSTOP" == "" ]; then
	# Ensure no other versions of `robox` are running
	while [ $count -gt 0 ]; do
	    count=$(ps aux | grep 'robox start\|robox stop' | grep -v grep | wc -l)
	    killall -q robox
	done

	stop_instances
	if [ $? -eq $FAILED ]; then
	    return $FAILED
	fi
    fi

    if [ "$ONLYSTOP" == "true" ]; then
	return
    fi

#    sleep 10

    time {
	start_instances
	count_instances

	# Try to restart failed instance one more time
	cp $ROBOXFAILLOG $SCALABILITYFAILLOG
	rm $ROBOXFAILLOG 2>&1 > /dev/null
	touch $ROBOXFAILLOG

	for instance in `cat $SCALABILITYFAILLOG`; do
	    retry $instance &
	done

	count_instances
    }

    lines=$(wc -l $ROBOXFAILLOG | cut -d' ' -f1)

    echo -e "\nCompleted with $lines failures"
}

if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root"
    exit 1
fi

# Ensure we have current sudoers rights
sudo ls > /dev/null

while [ $# -gt 0 ]; do
    case $1 in
	-f)
	    FORCESTOPALL=true
	    ;;
	-n)
	    instancestostart=$2
	    shift
	    ;;
	-b)
	    baseinstancetostart=$2
	    shift
	    ;;
	-v|--verbose)
	    QUIET=""
	    ;;
	-d|--debug)
	    QUIET="-d"
	    ;;
	-ds|--dont-stop)
	    DONTSTOP=true
	    ;;
	-os|--only-stop)
	    ONLYSTOP=true
	    ;;
	*)
	    echo "Unrecognised parameter $1"
	    exit 1
	    ;;
    esac
    shift
done

main
