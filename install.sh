#!/bin/bash
#------------------------------------|RUN AS ROOT|--------------------------------------------
# Before running, make the changes you wish to the conf file
#

tstamp() {
  date +"%F"_"%H":"%M"
 }

# func requires arguments (username)
chk_usr() {
   if [ "$(whoami)" != "$1" ]; then
       printf "\nyou need to be root\nexiting....\n\n"
       exit
   fi
}

chk_tubes() {
  printf "\nChecking your tubes..."
  if ! ping -c 1 google.com > /dev/null 2>&1  ; then
      if ! ping -c 1 yahoo.com > /dev/null 2>&1  ; then
         if ! ping -c 1 bing.com > /dev/null 2>&1 ; then
             clear
             printf "\n\nDo you have an internet connection???\n\n"
             exit
         fi
      fi
  fi
  printf "\n\ntubes working....\n\n"

}

get_aptpkg() {
   if ! apt-get -y install $1; then
       printf "\n\nAPT failed to install "$1", are your repos working?\nexiting...\n\n"
       exit
   fi
}

# func requires arguments (full path/file name)
make_runlog() {
   touch $1
   printf "\nscript run on\n"$(tstamp)"\n" > $1
}

get_permission() {
   while [[ $ansr != "n" || $ansr != "N" || $ansr != "y" || $ansr != "Y" ]]; do
         read ansr
            if [[ $ansr == "n" || $ansr == "N" ]]; then
                   printf "\n\nexiting....\n"
                   exit
              elif [[ $ansr == "y" || $ansr == "Y" ]]; then
                   printf "\ncontinuing....\n\n"
                   break
              else
                   printf "\n\n not a valid entry, please try again."
                   printf "\n(y/n)?\n"
            fi
   done
}

# you may have to tweak this if your wireless device doesn't start with wlan, for example ath0
chk_wlan() {
   if ! test=$(iwconfig 2>/dev/null | grep -o "^\w*"); then
        printf "\nwlan device not detected? \n\n"
        exit
   fi
}

chk_wpasup() {
   if [ ! -d "/etc/wpa_supplicant/" ]; then
      printf "\n/etc/wpa_supplicant not detected, attempting to install..."
      if ! get_aptpkg wpasupplicant; then
           printf "\n\nwpa-supplicant failed to install, exiting...\n"
           printf "\nThis bash program will not be able to function without wpa_supplicant....\n\n"
           exit
      fi
   fi
}


spath="$( cd "$(dirname "$0")" ; pwd -P )"
if [[ ! -e  $spath/tracking.conf ]]; then
      printf "the tracking.conf file was not found, cannot continue\nexiting.."
      exit
fi
source $spath/tracking.conf

while true; do
chk_usr root
if [[ $PINGTN != 'on' && $PINGTN != 'off' ]]; then
      # unset PINGTN
      # PINGTN=off
      echo ""$PINGTN""
       printf "\nYou probably changed the ping tunnel values incorrectly, ignoring values until corrected.\n\n"
fi

# Performing check if already configured previously if not installing packages.
if [ ! -f "/var/log/first-run" ]; then

   if [ $USR == 'foo' ]; then
         printf "\nYou have not changed the server user name, check the ip address, port number as well.\n\n"
         exit
     else
         chk_tubes
         if [ $PINGTN == 'on' ]; then
               printf "\nBy turning the PINGTN option on it means you have a server setup with\na configured ptunnnel service"
               printf "\nDo you wish to continue? (y/n) \n"
               get_permission
         fi

         printf "\n\nthis script works best with a vanilla .img of Raspbian"
         printf "\nit will make changes to the network configuration, dedicating it to WiFi and gps functions."
         printf "\nif you use this device as a server or for any other services stop the script now!"
         printf "\n\nContinue? (y/n) \n"
         get_permission
         while true; do
             if ! ( get_aptpkg gpsd-clients && get_aptpkg ptunnel && get_aptpkg secure-delete ); then
                   printf "\ntrying again...\n"
                   apt-get update
              else
                   break
             fi
         done
         make_runlog /var/log/first-run
   fi

fi

# Setting up cron job which performs periodic updates to server
if [ ! -f "/etc/cron.d/geo-tracker" ]; then

   chk_wlan
   chk_wpasup
   printf "\n" > /etc/udev/rules.d/70-persistent-net.rules
   printf "\n\nWarning the network interfaces will restart as they are configured."
   printf "\nyou may have to reboot the device."
   printf "\n\nIf your using ssh it's going to hang, heads up\n\n"
   /etc/init.d/networking restart > /dev/null 2>&1
   set -e
   if ! wlan=$(iwconfig 2>/dev/null | grep -o "^\w*"); then   # you may have to tweak this if your wireless device doesn't start with wlan
         printf "\nfailed to set wlan variable, wlan device not detected, maybe it's ath0? $(tstamp) \n\n" >> /var/log/tracking-log
         exit
     else
	# the following are modifications to set up wireless roaming
	# you may add additional network profiles, see (man wpa_supplicant.conf) for details
	# do so at your own risk
	cat > /etc/network/interfaces <<-EOL
	auto lo
	iface lo inet loopback
	
	auto eth0
	iface eth0 inet dhcp
	
	allow-hotplug $wlan
	iface wlan0 inet manual
	wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf
	iface default inet dhcp
	EOL

	# here you can add access point profiles but before doing so read up on the .conf format
	cat > /etc/wpa_supplicant/wpa_supplicant.conf <<-EOL
	ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
	update_config=1
	
	network={
	key_mgmt=NONE
	}
	network={
		ssid="default"
		key_mgmt=NONE
	}
	EOL

        # adding root to wpa_supplicant netdev group for wifi roaming under root
        usermod -a -G netdev root

	# here the dhclient settings are set aggressively
	cat > /etc/dhcp/dhclient.conf <<-EOL
	# Configuration file for /sbin/dhclient, which is included in Debian's
	# dhcp3-client package.
	# the file has been modified to work better for WiFi roaming
	backoff-cutoff 1;
	initial-interval 1;
	#link-timeout 10;
	#reboot 0;
	retry 10;
	select-timeout 0;
	timeout 15;
	option rfc3442-classless-static-routes code 121 = array of unsigned integer 8;
	request subnet-mask, broadcast-address, time-offset, routers,
		domain-name, domain-name-servers, domain-search, host-name,
		netbios-name-servers, netbios-scope, interface-mtu,
		rfc3442-classless-static-routes, ntp-servers,
		dhcp6.domain-search, dhcp6.fqdn,
		dhcp6.name-servers, dhcp6.sntp-servers;
	EOL


	# enabling GPIO UART for use by TTL Serial GPS device
	if [ -e /boot/cmdline.txt ]; then
        cat > /boot/cmdline.txt <<-EOL
	dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait
	EOL
        fi

        if [ -e /etc/inittab ]; then
        sed -i 's/T0:23:respawn:\/sbin\/getty -L ttyAMA0/#T0:23:respawn:\/sbin\/getty -L ttyAMA0/' /etc/inittab
        fi

        #getting operating path of script and copying the necessary files for cron to a discreet location.
        if [ -d /root/tracking-engine ]; then
              rm -rf /root/tracking-engine
        fi
        mkdir /root/tracking-engine > /dev/null 2>&1
        cp -f $spath/{rpi-tracker.sh,cron-check.sh,tracking.conf} /root/tracking-engine/
	# the cron job, once created the above configurations to the interface and wpa-roam.conf will not repeat.
	cat > /etc/cron.d/geo-tracker <<-EOL
	PATH=/sbin:/usr/sbin:/bin:/usr/bin
	@reboot root /usr/sbin/gpsd $GPSDEVICE -n -F /var/run/gpsd.sock
	* * * * * root /bin/sh -c /root/tracking-engine/cron-check.sh
	EOL

        service networking stop > /dev/null 2>1 && service networking start
        printf "\nFinished....\n"
        exit 0
   fi
fi

printf "\n\nYou have installed this before, to proceed the configuration files will be replaced."
printf "\nDo you wish to continue? (y/n)\n"
get_permission
rm -f /var/log/first-run
rm -f /etc/cron.d/geo-tracker
rm -rf /root/geo-data

done
exit
