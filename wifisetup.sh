#!/bin/sh

. /usr/share/libubox/jshn.sh  


ssid=""
password=""
auth=""
bScanFailed=0


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
	RESP=$(ubus call iwinfo scan '{"device":"wlan0"}')
	                              
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
	bFoundType1=0
	bFoundType2=0

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

	# read the arguments
	if [ $# -ge 2 ]
	then
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


## setup the wifi
echo ""
echo "Connecting to $ssid network..."

# use UCI to set the network to client mode
uci set wireless.@wifi-iface[0].mode="sta"

# use UCI to set the ssid and encryption
uci set wireless.@wifi-iface[0].ssid="$ssid"
uci set wireless.@wifi-iface[0].encryption="$auth"

# set the network key based on the authentication
case "$auth" in
	psk|psk2)
		uci set wireless.@wifi-iface[0].key="$password"
    ;;
    wep)
		uci set wireless.@wifi-iface[0].key=1
		uci set wireless.@wifi-iface[0].key1="$password"
    ;;
    none)
		# set no keys for open networks
		uci set wireless.@wifi-iface[0].key=""
    ;;
    *)
		echo "ERROR: invalid network authentication specified"
		echo "	See possible authentication types below"
		echo ""
		echo ""
		Usage
esac

# commit the changes
uci commit wireless

# reset the wifi adapter
wifi

echo "Done!"




