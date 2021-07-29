#!/bin/sh

echo -e "`date '+%Y-%m-%d %T'` <INFO>\tonecloud_upgrade_restart.sh running" >>/var/log/upgrade.log

# kill now running instance
while :
do
  pid=`ps | grep 'onecloud_upgrade_run.sh' | grep -v 'grep' | awk -F ' ' '{print $1}'`
  
  if [ -n "$pid" ]; then
	echo -e "`date '+%Y-%m-%d %T'` <INFO>\tkill [$pid] onecloud_upgrade_run.sh" >>/var/log/upgrade.log
    kill -9 $pid
  else
    break
  fi
done

sleep 1

while :
do
  echo "`ps | grep 'upgrade' | grep -v 'grep' `"
  pid=`ps | grep 'upgrade' | grep -v 'grep' | grep -v 'onecloud_upgrade_restart.sh' | awk -F ' ' '{print $1}'`
  if [ -n "$pid" ]; then
	echo -e "`date '+%Y-%m-%d %T'` <INFO>\tkill [$pid] upgrade" >>/var/log/upgrade.log
    kill -9 $pid
  else
    break
  fi
done

sleep 1

# begin a new era
sh /usr/sbin/onecloud_upgrade_run.sh &

exit 0

