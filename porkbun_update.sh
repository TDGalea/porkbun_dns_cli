#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Written by Thomas Galea.                                                                                                                        #
# github.com/TDGalea/porkbun_dns_cli                                                                                                              #
#                                                                                                                                                 #
# You are free to do whatever you like with this script. I simply ask that you preserve my credit.                                                #
#                                                                                                                                                 #
# Porkbun record update script. When automated (by a cron job, etc.) this script can be used to create a DDNS updater for your Porkbun domain(s). #
# This script supports updating multiple domains and records in one execution, whether under one API key or multiple.                             #
#                                                                                                                                                 #
# This script was originally for GoDaddy, but then they went and restricted their API to those with 20+ domains. Well, their loss.                #
# That script is still available to those using GoDaddy who are applicable to the new API restriction.                                            #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# No arguments passed, or -h.
if [[ "$1" == "-h" ]] || [[ -z $1 ]]; then
	printf "Usage:\n"
	printf "	$0 {-k key} {-s secret} {-d domain1} {-r record1} [-n] ...\n"
	printf "	You must specify all four values at least once. If you specify -n, you can update any entry\n"
	printf "	(key, secret, domain, host) for another domain. Any you don't update before the next -n (or end of line) will be reused.\n\n"

	printf "	Valid options are:\n"
	printf "		-k : API Key. Visit https://porkbun.com/account/api if you need one.\n"
	printf "		-s : API Secret. Visit https://porkbun.com/account/api if you need one.\n"
	printf "		-d : Domain name (example.com).\n"
	printf "		-r : Record. If updating the domain itself, use '@', otherwise, this is used to update hosts under a domain, for example, 'another' in 'another.example.com'.\n"
	printf "		-t : TTL (Time To Live). Defaults to 600 seconds (10 minutes) if not specified.\n"
	printf "		-i : IP address to point the record at. If omitted, the script will pull your current public IP address automatically.\n"
	printf "		-x : Delete the specified record. This option will NOT persist across multiple records; it must be specified for every one.\n"
	printf "		-n : Specify  more records, domains, etc. for batch updating.\n"
	printf "		-h : Print this help.\n"
	exit 0
fi

api="https://api.porkbun.com/api/json/v3/dns"

# Blank out all the variables. Bash doesn't need this, but I'm weird.
key=""
sec=""
dom=""
rec=""
ttl=""
ip=""
errCount=0
changeMade=0

# Loop until there are no arguments remaining.
until [[ -z $@ ]];do
	# I'm not going to allow recursive deletion. I feel like that could get accidentally destructive.
	del=0
	# Loop until current first argument is either -n or blank.
	until [[ "$1" = "-n" ]] || [[ -z $1 ]];do
		case $1 in
			-k ) [[ ! -z $2 ]] && key=$2 && shift || printf "'$1' has no argument!\n";;
			-s ) [[ ! -z $2 ]] && sec=$2 && shift || printf "'$1' has no argument!\n";;
			-d ) [[ ! -z $2 ]] && dom=$2 && shift || printf "'$1' has no argument!\n";;
			-r ) [[ ! -z $2 ]] && rec=$2 && shift || printf "'$1' has no argument!\n";;
			-t ) [[ ! -z $2 ]] && ttl=$2 && shift || printf "'$1' has no argument!\n";;
			-i ) [[ ! -z $2 ]] && ip=$2  && shift || printf "'$1' has no argument!\n";;
			-x ) del=1;;
			-egg ) printf "¯\\_(ツ)_/¯\n" && shift;;
			 * ) printf "Unrecognised argument '$1'\n" && shift;;
		esac
		shift
	done

	# If no TTL was specified, use 600 seconds (10 minutes).
	[[ -z $ttl ]] && ttl=600
	# Make sure all required params are occupied.
	con=1
	[[ -z $key ]] && printf "Missing key! Use '-h' if you need help.\n"    && con=0
	[[ -z $sec ]] && printf "Missing secret! Use '-h' if you need help.\n" && con=0
	[[ -z $dom ]] && printf "Missing domain! Use '-h' if you need help.\n" && con=0
	[[ -z $rec ]] && printf "Missing record! Use '-h' if you need help.\n" && con=0
	[[ -z $ip ]] && ip=`curl ipv4.icanhazip.com 2>/dev/null`
	# Exit if any were missing.
	[[ $con = 0 ]] && exit 2

	# Porkbun doesn't use '@' - it instead wants nothing there for the root. As such, if we use another var, 'prec', which we actually pass to the API. This is blank if $rec is '@'.
	[[ "$rec" == "@" ]] && prec="" || prec="$rec"

	# Find what the current IP of the Porkbun record is.
	pbip=`curl --header "Content-type: application/json" --request POST --data "{\"secretapikey\":\"$sec\",\"apikey\":\"$key\"}" $api/retrieveByNameType/$dom/A/$prec 2>/dev/null`
	pbip=`printf "$pbip" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"`

	# Check if the record exists. Blank $pbip means it does not.
	if [[ "$pbip" == "" ]]; then
		# If we were asked to delete, there's nothing to do. Otherwise, we need to create the record rather than update.
		if [[ $del == 1 ]]; then
			printf "Record '$prec' doesn't exist for domain '$dom'. Nothing to delete.\n"
		else
			printf "Creating record '$prec' of domain '$dom': "
			response=`curl --header "Content-type: application/json" --request POST --data "{\"secretapikey\":\"$sec\",\"apikey\":\"$key\",\"name\":\"$prec\",\"type\":\"A\",\"content\":\"$ip\",\"ttl\":\"$ttl\"}" $api/create/$dom 2>/dev/null`
			[[ ! "$(printf $response | grep SUCCESS)" == "" ]] && printf "Success.\n" || printf "Failed. JSON response was:\n	$response\n" || let errCount+=1
		fi
	else
		if [[ $del == 1 ]]; then
			printf "Deleting record '$prec' of domain '$dom': "
			response=`curl --header "Content-type: application/json" --request POST --data "{\"secretapikey\":\"$sec\",\"apikey\":\"$key\"}" $api/deleteByNameType/$dom/A/$prec 2>/dev/null`
			[[ ! "$(printf $response | grep SUCCESS)" == "" ]] && printf "Success.\n" || printf "FAiled. JSON response was:\n	$response\n" || let errCount+=1
		else
			# Only bother updating if the IPs are actually different.
			if [[ "$pbip" = "$ip" ]]; then
				printf "Record '$prec' of domain '$dom' is already up to date.\n"
			else
				printf "Updating record '$prec' of domain '$dom': "
				response=`curl --header "Content-type: application/json" --request POST --data "{\"secretapikey\":\"$sec\",\"apikey\":\"$key\",\"content\":\"$ip\",\"ttl\":\"$ttl\"}" https://porkbun.com/api/json/v3/dns/editByNameType/$dom/A/$prec 2>/dev/null`
				[[ ! "$(printf $response | grep SUCCESS)" == "" ]] && printf "Success.\n" || printf "Failed. JSON response was:\n	$response\n" || let errCount+=1
			fi
   		fi
   	fi

	shift
done

[[ $errCount == 0 ]] && exit 0 || exit 1
