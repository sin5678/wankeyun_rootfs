#!/bin/sh

LED_RED="gpio2"
LED_GREEN="gpio3"
LED_BLUE="gpio4"

LED_ON="1"
LED_OFF="0"


# Not work in factory mode
SOFTMODE=`fw_printenv xl_softmode |  awk -F "=" '{print $2}'`
[ "$SOFTMODE" == "factory" ] && exit 0

export SN=`cat /tmp/miner_sn`
export APPVER=`awk -F- '{ print $4 }' /thunder/etc/.img_date`

SYSVER=
if [ -f /.sys_ver ]; then
	SYSVER=`cat /.sys_ver`
fi

# make dir
mkdir -p /var/cache/opkg-upgrade

#ubusd_process_info=`ps | grep ubusd | grep -v grep`
[ -x /thunder/bin/run.sh ] || ubusd -s /var/run/ubus.sock  &

# Generate coredump.
ulimit -c unlimited
echo "/tmp/dcdn_base/debug/core-%e-%p-%t" > /proc/sys/kernel/core_pattern

# Set stack size(KB).
ulimit -s 1024

APP_MODULES="upgrade"

run_module ()
{
    unset LD_LIBRARY_PATH
    /usr/sbin/$1 > /dev/null 2>&1 &
    ubus wait_for $1 -t 3
    echo -e "`date '+%Y-%m-%d %T'` <INFO>\t$1 running" >>/var/log/upgrade.log
}

monitor_modules ()
{
    for name in $APP_MODULES
    do
        ubus call $name get_status -t 30 >/dev/null 2>&1
        if [[ $? -eq 7 || $? -eq 4 ]]; then          #Request timed out(7) OR Object not found(4)
            (killall $name; sleep 2; killall -9 $name) >/dev/null 2>&1
            run_module $name
			eval st_${name}="\$((\$st_${name} + 1))"
        fi
    done
}

set_led_color ()
{
  what_color=$1
  what_onoff=$2
  
  # turn off all color led
  echo ${LED_OFF} > /sys/class/gpio/${LED_RED}/value
  echo ${LED_OFF} > /sys/class/gpio/${LED_GREEN}/value
  echo ${LED_OFF} > /sys/class/gpio/${LED_BLUE}/value
  
  echo ${what_onoff} > /sys/class/gpio/${what_color}/value
}

monitor_network ()
{
  ip_addr=`ifconfig eth0|grep 'inet add'|awk -F "[: ]" '{print $13}'`
  link_status=`ethtool eth0|grep 'Link detected'|awk -F ": " '{print $2}'`
  
  if [ "${link_status}" = "no" ]; then
    set_led_color ${LED_RED} ${LED_ON}
  elif [ -z "${ip_addr}" ]; then
    set_led_color ${LED_RED} ${LED_ON}
    ifconfig eth0 up
    udhcpc eth0
  else
    upgrading_process_info=`ps | grep onecloud_upgrading_led.sh | grep -v grep`
    if [ -z "${upgrading_process_info}" ]; then
      set_led_color ${LED_BLUE} ${LED_ON}
    fi
  fi
}

stat_module()
{
    #$1 == module_name
    local name=$1

    local st=0

    eval st=\$st_$name
	
    if [ -z "$st" ]; then
        st=0
    fi

    local pid="`pidof $name | awk '{ print $1 }'`"
    if [ -z "$pid" -a $st -eq 0 ]; then
        return 1
    fi
    
    local topline=
    local cpu=
    local mem=
    local fds=

    if [ -n "$pid" ]; then
        fds="`ls /proc/$pid/fd | wc -l`"
        topline="`top -n 1 -b | grep -v grep | grep "^\ *$pid\ \+"`"
        if [ -n "$topline" ]; then          
            cpu="`echo $topline | awk '{ print $7 }' | awk -F% '{ print $1 }'`"
            mem="`echo $topline | awk '{ print $6 }' | awk -F% '{ print $1 }'`"
        fi
    fi

    local et="`date +%s`"
    
    if [ -z "$cpu" ]; then
        cpu=0
    fi

    if [ -z "$mem" ]; then
        mem=0
    fi

    if [ -z "$fds" ]; then
        fds=0
    fi

    #echo "name $1, pid $pid, cpu $cpu, mem $mem, fds $fds, et $et"

    ubus send stat.normal '{"act":"process","et":"'$et'","v":"'$APPVER'","sn":"'$SN'","pn":"'$name'","cu":"'$cpu'","mu":"'$mem'","st":"'$st'","fn":"'$fds'"}'

	return 0
}


for name in $APP_MODULES
do
	run_module $name
done

set_led_color ${LED_BLUE} ${LED_ON}

stat_module_timer=0

while :
do
    sleep 10

	if [ $stat_module_timer -ge 360 ]; then
		stat_module_timer=0
		stat_module upgrade
	else
		stat_module_timer=$(($stat_module_timer + 1))
	fi

	# onecloud-app not installed or corrupted
    [ -x /thunder/bin/netcfg ] || monitor_network
    
    monitor_modules
done


