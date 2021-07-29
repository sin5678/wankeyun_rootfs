#!/bin/sh

# export the sn and appver to workaround 211 factory version bug
export SN=`cat /tmp/miner_sn`
export APPVER=`awk -F- '{ print $4 }' /thunder/etc/.img_date`

# start nginx here
mkdir -p /tmp/nginx/logs
mkdir -p /tmp/nginx/socket
# generate sn for nginx
echo "set \$sn '${SN}';" > /tmp/.device_sn.conf
/thunder/bin/nginx -p /tmp/nginx -c /thunder/etc/conf/nginx.conf

# Generate coredump.
ulimit -c unlimited
echo "/tmp/dcdn_base/debug/core-%e-%p-%t" > /proc/sys/kernel/core_pattern

# Set stack size(KB).
ulimit -s 1024

APP_MODULES="stat netcfg mnt upgrade xqos dcdn remote fmgr xldp turnclient sysmgr tfmgr xlplayer ipkmgr"

modules_name="$APP_MODULES nginx gui happ"

mem_total=`head -n 1 /proc/meminfo | awk '{ print $2 }'`

SYSVER=
if [ -f /.sys_ver ]; then
    SYSVER=`cat /.sys_ver`
fi

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

    eval st_$name=0

    return 0
}



stat_modules()
{
	# stat system: cpu memory
    local topline=
    local mem_used=0
    local mem_used_percent=0
    local mem_free_percent=0
    local cpu_free_percent=0
    local cpu_used_percent=0
    local io_percent=0

    topline=`top -n 1 -b | head -n 2`
    if [ -n "$topline" ]; then
        mem_used=`echo $topline | head -n 1 | awk '{ print $4 }' | awk -FK '{ print $1 }'`
        if [ -n "$mem_used" ]; then
            mem_used_percent=$(($mem_used * 100 / $mem_total))
            mem_free_percent=$((100 - $mem_used_percent))
        fi
        
		local cpuline=`top -n 1 -b | grep "^CPU:"`
		if [ -n "$cpuline" ]; then
            io_percent=`echo $cpuline | awk '{ print $10 }' | awk -F% '{ print $1 }'`
            cpu_free_percent=`echo $cpuline | awk '{ print $8 }' | awk -F% '{ print $1 }'`
            if [ -n "$cpu_free_percent" ]; then
                cpu_used_percent=$((100 - $cpu_free_percent))
            fi
        fi
    fi	

	local uptime=`awk -F. '{ print $1 }' /proc/uptime`
    if [ -z "$uptime" ]; then
         uptime=0
    fi

    local et="`date +%s`"

    ubus send stat.normal '{"act":"system","et":"'$et'","sv":"'$SYSVER'","v":"'$APPVER'","sn":"'$SN'","mu":"'$mem_used_percent'","mf":"'$mem_free_percent'","io":"'$io_percent'","cu":"'$cpu_used_percent'","cf":"'$cpu_free_percent'","ut":"'$uptime'"}'

    for name in $modules_name
    do
        stat_module $name
    done
}

run_module ()
{
    if [ "$1" = "upgrade" -a -x /usr/sbin/upgrade ]; then
      return
    fi

    if [ "$1" = "remote" -a -x /usr/sbin/remote ]; then
      return
    fi
    
    /thunder/bin/$1 > /dev/null 2>&1 &
    ubus wait_for $1 -t 3
    echo -e "`date '+%Y-%m-%d %T'` <INFO>\t$1 running\t-- start_app.sh" >>/var/log/ubus_app.log
}

monitor_modules ()
{
    for name in $APP_MODULES
    do
        if [ "$name" = "upgrade" -a -x /usr/sbin/upgrade ]; then
	    UPG_PROC=`ps | grep onecloud_upgrade_run.sh | grep -v grep`
            if [ -z "$UPG_PROC" ]; then
            	sh /usr/sbin/onecloud_upgrade_run.sh &
            fi
            continue
        fi
        
        if [ "$name" = "remote" -a -x /usr/sbin/remote -a -x /etc/init.d/S90remote -a -x /usr/sbin/onecloud_remote_run.sh ]; then
            local remote_info=`ps | grep onecloud_remote_run.sh | grep -v grep`
            if [ -z "$remote_info" ]; then
                sh /etc/init.d/S90remote restart &
            fi
            continue
        fi

        ubus call $name get_status -t 30 >/dev/null 2>&1
        if [[ $? -eq 7 || $? -eq 4 ]]; then          #Request timed out(7) OR Object not found(4)
            (killall $name; sleep 2; killall -9 $name) >/dev/null 2>&1
            run_module $name
			eval st_${name}="\$((\$st_${name} + 1))"
        fi
    done
}

monitor_nginx()
{

	local nginx_monitor_running=`ps | grep "/thunder/bin/nginx" | grep -v "grep"`
	if [ ! -n "$nginx_monitor_running" ]; then
		echo "restart nginx..."
		killall -9 nginx
		/thunder/bin/nginx -p /tmp/nginx -c /thunder/etc/conf/nginx.conf > /dev/null 2>&1 &
		echo -e "`date '+%Y-%m-%d %T'` <INFO>\tnginx running\t-- start_app.sh" >>/var/log/ubus_app.log
		st_nginx=$(($st_nginx + 1))
	fi

}

monitor_samba()
{

    local samba_monitor_smbd=`pidof smbd`
    local samba_monitor_nmbd=`pidof nmbd`
    [ -n "$samba_monitor_smbd" -a -n "$samba_monitor_nmbd" ] && return

    local runflag=`cat /thunder/etc/config.json | sed 's/{.*\"samba\": *\"\([^,}]*\)\".*}/\1/'`
    [ $runflag = 1 ] || return 1
    echo "restart smaba..."
    /etc/init.d/S91smb restart > /dev/null 2>&1 &
    sleep 2
}

monitor_gui()
{
	local hdmi_up="`cat /sys/class/amhdmitx/amhdmitx0/hpd_state`"
	if [ "$hdmi_up" == "1" ]; then
		local gui_running=`ps | grep "/thunder/bin/gui" | grep -v "grep"`
		if [ -z "$gui_running" ]; then
			echo "restart gui"
			killall -9 gui
			/thunder/bin/gui &
			st_gui=$(($st_gui + 1))
		fi
	fi
}

monitor_fdrawer()
{
    local fdrawer_pid=`pidof fdrawer`

    if [ -n "${fdrawer_pid}" ]; then
        local try_times=0
        local rcode=0
        while [ $try_times -lt 3 ];
        do
            ubus call fdrawer get_status -t 30 >/dev/null 2>&1
            rcode=$?
            if [ $rcode -eq 7 -o $rcode -eq 4 ]; then
                #Request timed out(7) OR Object not found(4)
                try_times=$(($try_times + 1))
            else
                # fdrawer is alive
                return
            fi
        done

        (killall fdrawer; sleep 2; killall -9 fdrawer) >/dev/null 2>&1
    fi

    # fdrawer don't run or isn't alive, restart it
    st_fdrawer=$(($st_fdrawer + 1))
    run_module fdrawer
}

for name in $APP_MODULES
do
	run_module $name
done

run_module fdrawer

stat_module_timer=0

while :
do
    monitor_modules
    monitor_nginx
    monitor_fdrawer
    monitor_samba
    monitor_gui
    if [ $stat_module_timer -ge 360 ]; then
        stat_module_timer=0
        stat_modules
    else
        stat_module_timer=$(($stat_module_timer + 1))
    fi
    sleep 10
	
done

