#!/bin/sh

. /usr/share/libubox/jshn.sh

ssid=""
password=""
auth=""
bScanFailed=0

intfCount=0
intfAp=-1
intfSta=-1


# function to print script usage
Usage () {
	echo "Functionality:"
	echo "\tSetup WiFi on the Omega"
	echo ""
	echo "Usage:"
	echo "$0"
	echo "	Accepts user input"
	echo "$0 <ssid> <password>"
	echo "	Uses command line arguments, default auth is wpa2"
	echo "$0 <ssid> <password> <authentication type>"
	echo "	Uses command line arguments"
	echo "	Possible authentication types"
	echo "		psk2"
	echo "		psk"
	echo "		wep"
	echo "		none	(note: password argument will be discarded)"
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
	echo "Connecting to $ssid network using intf $intfSta..."

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





########################
##### Main Program #####

# read the arguments
if [ $# == 0 ]
then
	## accept all info from user interactions
	ReadUserInput
else
	## accept info from arguments

	# print script usage
	if 	[ $1 == "help" ] ||
		[ $1 == "-help" ] ||
		[ $1 == "--help" ] ||
		[ $1 == "-h" ];
	then
		Usage
		exit
	fi

	## read the arguments
	if [ $# -ge 2 ]
	then
		## cli arguments define the network info
		ssid=$1
		password=$2

		# read the authentication type (or set the default)
		if [ $# -eq 3 ]
		then
			auth=$3
		else
			auth="psk2"
		fi
	fi
fi


# check the variables
if 	[ $bScanFailed == 1 ]
then
	echo "ERROR: no networks detected... try again in a little while"
	exit
fi
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
UciSetupWifi

echo "Done!"




