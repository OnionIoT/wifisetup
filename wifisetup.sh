#!/bin/sh

. /usr/share/libubox/jshn.sh

bSetupWifi=1
bKillAp=0
bUsage=0
bScanFailed=0

ssid=""
password=""
auth=""
authDefault="psk2"

intfCount=0
intfAp=-1
intfSta=-1

tmpPath="/tmp"
pingUrl="http://cloud.onion.io/api/util/ping"
timeout=3000


# function to print script usage
Usage () {
	echo "Functionality:"
	echo "	Setup WiFi on the Omega"
	echo ""
	echo "Usage:"
	echo "$0"
	echo "	Accepts user input"
	echo ""
	echo "$0 -ssid <ssid> -password <password>"
	echo "	Specify ssid and password, default auth is wpa2"
	echo "$0 -ssid <ssid> -password <password> -auth <authentication type>"
	echo "	Specify ssid, authentication type, and password"
	echo "	Possible authentication types"
	echo "		psk2"
	echo "		psk"
	echo "		wep"
	echo "		none	(note: password argument will be discarded)"
	echo ""
	echo "$0 -killap"
	echo "	Disables any existing AP networks"
	echo ""
}

# function to scan wifi networks
ScanWifi () {
	# run the scan command and get the response
	local RESP=$(ubus call iwinfo scan '{"device":"wlan0"}')
	
	# read the json response
	json_load "$RESP"
	
	# check that array is returned  
	json_get_type type results

	# find all possible keys
	json_select results
	json_get_keys keys
	
	
	if 	[ "$type" == "array" ] &&
		[ "$keys" != "" ];
	then
		echo ""
		echo "Select Wifi network:"
		
		# loop through the keys
		for key in $keys
		do
			# select the array element
			json_select $key
			
			# find the ssid
			json_get_var cur_ssid ssid
			if [ "$cur_ssid" == "" ]
			then
				cur_ssid="[hidden]"
			fi
			echo "$key) $cur_ssid"

			# return to array top
			json_select ..
		done

		# read the input
		echo ""
		echo -n "Selection: "
		read input;
		
		# get the selected ssid
		json_select $input
		json_get_var ssid ssid
		
		echo "Network: $ssid"

		# detect the encryption type 
		ReadNetworkAuthJson

		echo "Authentication type: $auth"
	else
		# scan returned no results
		bScanFailed=1
	fi
}

# function to read network encryption from 
ReadNetworkAuthJson () {
	# select the encryption object
	json_get_type type encryption

	# read the encryption object
	if [ "$type" == "object" ]
	then
		# select the encryption object
		json_select encryption

		# read the authentication type
		json_select authentication
		json_get_keys auth_arr
		
		json_get_values auth_type 
		json_select ..

		# read psk specifics
		if [ "$auth_type" == "psk" ]
		then
			ReadNetworkAuthJsonPsk
		else
			auth=$auth_type
		fi
	else
		# no encryption, open network
		auth="none"
	fi
}

# function to read wpa settings from the json
ReadNetworkAuthJsonPsk () {
	local bFoundType1=0
	local bFoundType2=0

	# check the wpa object
	json_get_type type wpa

	# read the wpa object
	if [ "$type" == "array" ]
	then
		# select the wpa object
		json_select wpa

		# find all the values
		json_get_values values

		# read all elements
		for value in $values
		do
			# parse value
			if [ $value == 1 ]
			then
				bFoundType1=1
			elif [ $value == 2 ]
			then
				bFoundType2=1
			fi
		done

		# return to encryption object
		json_select ..

		# select the authentication type based on the wpa values that were found
		if [ $bFoundType1 == 1 ]
		then
			auth="psk"
		fi
		if [ $bFoundType2 == 1 ]
		then
			# wpa2 overrides wpa
			auth="psk2"
		fi

	fi
}

# function to read network encryption from user
ReadNetworkAuthUser () {
	echo ""
	echo "Select network authentication type:"
	echo "1) WPA2"
	echo "2) WPA"
	echo "3) WEP"
	echo "4) none"
	echo ""
	echo -n "Selection: "
	read input
	

	case "$input" in
    	1)
			auth="psk2"
	    ;;
	    2)
			auth="psk"
	    ;;
	    3)
			auth="wep"
	    ;;
	    4)
			auth="none"
	    ;;
	esac

}

# function to read user input
ReadUserInput () {
	echo "Onion Omega Wifi Setup"
	echo ""
	echo "Select from the following:"
	echo "1) Scan for Wifi networks"
	echo "2) Type network info"
	echo "q) Exit"
	echo ""
	echo -n "Selection: "
	read input

	# choice between scanning 
	if [ $input == 1 ]
	then
		# perform the scan and select network
		echo "Scanning for wifi networks..."
		ScanWifi

	elif [ $input == 2 ]
	then
		# manually read the network name
		echo -n "Enter network name: "
		read ssid;

		# read the authentication type
		ReadNetworkAuthUser
	else
		echo "Bye!"
		exit
	fi

	# read the network password
	if 	[ "$auth" != "none" ] &&
		[ $bScanFailed == 0 ];
	then
		echo -n "Enter password: "
		read password
	fi
}

# function to check for existing wireless UCI data
# 	populates intfAp with wifi-iface number of AP network
# 	populates intfSta with wifi-iface number of STA network
#	a value of -1 incicates not found
CheckCurrentUciWifi () {
	# default values
	intfAp=-1
	intfSta=-1
	intfCount=0

	# get the current wireless setup
	local RESP=$(ubus call network.wireless status)
	
	# read the json response
	json_load "$RESP"
	
	# check radio0 type
	json_get_type type radio0
	
	if [ "$type" == "object" ]; then
		# traverse down to radio0
		json_select radio0

		# check that interfaces is an array and get the keys
		json_get_type type interfaces
		json_get_keys keys interfaces
		
		
		if 	[ "$type" == "array" ] &&
			[ "$keys" != "" ];
		then
			# traverse down to interfaces
			json_select interfaces

			# loop through the keys
			for key in $keys
			do
				# find the type and select the array element
				json_get_type type $key
				json_select $key
				
				# find out if interface is set to ap
				json_get_type type config 
				if [ "$type" == "object" ]; then
					json_select config
					json_get_var wifiMode mode

					if [ "$wifiMode" == "ap" ]; then
						intfAp=`expr $key - 1`
					elif [ "$wifiMode" == "sta" ]; then
						intfSta=`expr $key - 1`
					fi

					json_select ..
				fi

				# increment the interface count
				intfCount=`expr $intfCount + 1`

				# return to array top
				json_select ..
			done
		
		fi # interfaces is a non-empty array
	fi # radio0 == object

}

# function to perform the wifi setup
UciSetupWifi () {
	local commit=1

	echo ""
	echo "> Connecting to $ssid network using intf $intfSta..."

	# setup new intf if required
	local iface=$(uci -q get wireless.\@wifi-iface[$intfSta])
	if [ "$iface" != "wifi-iface" ]; then
		#echo "  Adding intf $intfSta"
		uci add wireless wifi-iface > /dev/null
		uci set wireless.@wifi-iface[$intfSta].device="radio0" 
	fi

	# use UCI to set the network to client mode and wwan
	uci set wireless.@wifi-iface[$intfSta].mode="sta"
	uci set wireless.@wifi-iface[$intfSta].network="wwan"

	# use UCI to set the ssid and encryption
	uci set wireless.@wifi-iface[$intfSta].ssid="$ssid"
	uci set wireless.@wifi-iface[$intfSta].encryption="$auth"

	# set the network key based on the authentication
	case "$auth" in
		psk|psk2)
			uci set wireless.@wifi-iface[$intfSta].key="$password"
	    ;;
	    wep)
			uci set wireless.@wifi-iface[$intfSta].key=1
			uci set wireless.@wifi-iface[$intfSta].key1="$password"
	    ;;
	    none)
			# set no keys for open networks
			uci set wireless.@wifi-iface[$intfSta].key=""
	    ;;
	    *)
			echo "ERROR: invalid network authentication specified"
			echo "	See possible authentication types below"
			echo ""
			echo ""
			Usage
			commit=0
	esac

	# commit the changes
	if [ $commit == 1 ]; then
		uci commit wireless

		# reset the wifi adapter
		wifi
	fi
}

# function to disable any AP networks
UciDeleteAp () {
	local commit=1

	if [ $intfAp -ge 0 ]; then
		# ensure that iface exists
		local iface=$(uci -q get wireless.\@wifi-iface[$intfAp])
		if [ "$iface" != "wifi-iface" ]; then
			echo "> No AP network on intf $intfAp"
			commit=0
		fi

		# ensure that iface is in AP mode
		local mode=$(uci -q get wireless.\@wifi-iface[$intfAp].mode)
		if [ "$mode" != "ap" ]; then
			echo "> Network intf $intfAp is not set to AP mode"
			commit=0
		fi

		# delete the network iface
		if [ $commit == 1 ]; then
			echo "> Disabling AP network on intf $intfAp ..."

			uci delete wireless.@wifi-iface[$intfAp]
			uci commit wireless

			# reset the wifi adapter
			wifi
		fi
	else
		echo "> No AP networks to disable!"
	fi
}

# function to check if omega is connected to the internet
CheckInternetConnection () {
	local fileName="$tmpPath/ping.json"
	if [ -f $fileName ]; then
		# delete any local copy
		local rmCmd="rm -rf $fileName"
		eval $rmCmd
	fi

	# define the wget command
	local cmd="wget -t $timeout -q -O $fileName \"$pingUrl\""

	# fetch the ping file
	sleep 10
	echo "> Checking internet connection..."

	local count=0
	local bLoop=1
	while 	[ ! -f $fileName ] &&
			[ $bLoop == 1 ];
	do
		eval $cmd

		# implement time-out
		count=`expr $count + 1`
		if [ $count -gt $timeout ]; then
			bLoop=0
		fi
	done

	# check for wget time-out
	if 	[ $bLoop == 0 ] ||
		[ ! -f $fileName ];
	then
		echo "> ERROR: request timeout, internet connection not successful"
		return
	fi

	# parse the json file
	local RESP=$(cat $fileName)
	json_load "$RESP"

	# check the json file contents
	json_get_var response success
	if [ "$response" == "OK" ]; then
		echo "> Internet connection successful!!"
	else
		echo "> ERROR: internet connection not successful"
	fi
}



########################
##### Main Program #####

# read the arguments
if [ $# == 0 ]
then
	## accept all info from user interactions
	ReadUserInput
else
	## accept info from arguments
	while [ "$1" != "" ]
	do
		case "$1" in
	    	-h|-help|--help|help)
				bUsage=1
				shift
		    ;;
	    	-killap)
				bKillAp=1
				bSetupWifi=0
				shift
		    ;;
		    -ssid)
				shift
				ssid=$1
				shift
			;;
		    -password)
				shift
				password=$1
				shift
		    ;;
		    -auth)
				shift
				auth=$1
				shift
		    ;;
		    *)
				echo "ERROR: Invalid Argument"
				echo ""
				bUsage=1
		    ;;
		esac
	done
fi


# print the usage
if [ $bUsage == 1 ]; then
	Usage
	exit
fi


# check the variables
if [ $bSetupWifi == 1 ]; then
	# check for scan success
	if 	[ $bScanFailed == 1 ]
	then
		echo "ERROR: no networks detected... try again in a little while"
		exit
	fi

	# setup default auth if ssid and password are defined
	if 	[ "$ssid" != "" ] &&
		[ "$password" != "" ];
	then
		auth="$authDefault"
	fi

	# check that user has input enough data
	if 	[ "$ssid" == "" ]
	then 
		echo "ERROR: network ssid not specified"
		exit
	fi
	if 	[ "$auth" == "" ]
	then
		echo "ERROR: network authentication type not specified"
		exit
	fi
fi


## check current wireless setup
CheckCurrentUciWifi


## define new intf id based on existing intfAp and intfSta
#	case 	intfAp	intfSta		new intf
#	a  		0		-1			intfAp + 1
#	b 		0 		1			intfSta
#	c 		-1		-1			0
#	d 		-1		0			intfSta
if [ $intfSta -ge 0 ]; then
	# STA exists, overwrite it
	intfSta=$intfSta

	echo ""
	echo "Found existing wifi on intf $intfSta, overwriting"
elif [ $intfAp -ge 0 ]; then
	# AP exists, setup STA on next free intf id
	intfSta=$intfCount

	echo ""
	echo "Found Omega AP Wifi on intf id $intfAp"
else
	# no AP or STA, setup STA on next free intf id
	intfSta=$intfCount
fi


## setup the wifi
if [ $bSetupWifi == 1 ]; then
	# setup wifi
	UciSetupWifi

	# check internet connection
	CheckInternetConnection
fi

## kill the existing AP network 
if [ $bKillAp == 1 ]; then
	UciDeleteAp
fi


echo "> Done!"




