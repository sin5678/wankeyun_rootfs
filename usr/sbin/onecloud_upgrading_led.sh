#!/bin/sh

LED_RED="gpio2"
LED_GREEN="gpio3"
LED_BLUE="gpio4"

LED_ON="1"
LED_OFF="0"

#ubusd_process_info=`ps | grep ubusd | grep -v grep`
[ -x /thunder/bin/run.sh ] && exit 0

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

# led blinking loop
while :
do
    set_led_color ${LED_RED} ${LED_ON}
    sleep 1
    set_led_color ${LED_GREEN} ${LED_ON}
    sleep 1
    set_led_color ${LED_BLUE} ${LED_ON}
    sleep 1
done


