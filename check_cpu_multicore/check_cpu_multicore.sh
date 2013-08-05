#!/bin/bash
#
# DATE : Sun 15th Apr 2012
#
# AUTHOR : jascbu@gmail.com
#
# AIM : To have visibility of the activity of all the cores on a machine.
#	
# WHY : Originally I was using a check that averaged CPU usage.  I had a
#	problem on a server running Java code. I thought the problem was
#	CPU bound but the check showed me 50% CPU usage which then steered
#	my troubleshoot in the wrong direction.  I later realise that one 
#	CPU core was at 0% and the other was pegged at 100% by a blocked
# 	Java thread. I then wrote this check.
#
# HOW : Polls the SNMP OID for processor load.  This returns a value for
#	each core. This value is an average of the percentage of time the
#	core was not-idle.  The script then create  a total average for
# 	the system. It outputs the values for each core and the total system.
# 	If PNP4Nagios is installed and the partner file for this check is
# 	configured to be used then the PNP4Nagios will create a graph
#	showing the values for each core and the system average. For more
#	info see partner script "check_cpu_multicore.php"
# 
# DEPENDENCIES :
# 	1) If the target server is Linux based then snmpd needs to be 
#	installed and running, OR, if the targer server is Windows based then
#	the SNMP service to be installed and running
#	2) On the target server SNMP daemon/service to be serving data from 
#	the MIB "HOST-RESOURCES-MIB" - this should be default on both OSes.
#	3) On the Nagios server "snmpwalk" command tool to be available. In
#	Debian based systems this can be found in the "snmp" package
#	4) On the Nagios server "bc" to be installed to do some non-integer
#	calculation. In Debian based systems this can be found in the "bc"
#	package
#
# NOTES :
# 	1) If you are troubleshooting press enter after
#	all "#HELP#" to move the script behind it to
#	below it and make it active
#	2) The SNMP MIB Object that is poller is "hrProcessorLoad" with
#	OID "1.3.6.1.2.1.25.3.3.1.2".  Here is more detail: 
# 	Object = hrProcessorLoad
# 	OID = 1.3.6.1.2.1.25.3.3.1.2
# 	Type = Integer32 
# 	Permission = read-only
# 	Status = current
# 	Range = 0 - 100
# 	MIB = HOST-RESOURCES-MIB 
# 	Description = "The average, over the last minute, of the percentage
# 	of time that this processor was not idle.
# 	Implementations may approximate this one minute
# 	smoothing period if necessary."
#
#



##################################################
#
# GET ARGUMENTS
#
##################################################


while getopts 'a:b:c:d:e:f:hp' OPT; do
  case $OPT in
    a)  targetIP=$OPTARG;;
    b)  snmpCommunityString=$OPTARG;;
    c)  warningForCpu=$OPTARG;;
    d)  criticalForCpu=$OPTARG;;
    e)  warningForCore=$OPTARG;;
    f)  criticalForCore=$OPTARG;;
    h)  hlp="yes";;
    *)  unknown="yes";;
  esac
done

# Usage
HELP="
  
    Usage: $0 -a IP address   -b SNMP community string   -c warning CPU threshold   -d Critical CPU threshold -e warning Core threshold   -f Critical Core threshold [ -h ]

    Syntax:

            -a --> Target server IP address
            -b --> SNMP community string
            -c --> warning threshold for CPU as %
            -d --> critical threshold for CPU as %
            -e --> warning threshold for any Core as % (Set this high to avoid false positives when normal spikes occur)
            -f --> critical threshold for any Core as % (Set this high to avoid false positives when normal spikes occur)
            -h --> print this help screen

    Example:  $0 -a machine.company.com -b public -c 80 -d 95 -e 98 -f 100 

"

if [ "$hlp" = "yes" -o $# -lt 1 ]; then
  echo "$HELP"
  exit 0
fi



##################################################
#
# Step 1: Get data - Make SNMP request to server 
# to be measured. Extract returned data set in to 
# arrays for each metric.  
#
##################################################

## Make SNMP request for percentage usage for each CPU core to the server to be measured
snmpCpuSet=( `snmpwalk -v 1 -c $snmpCommunityString $targetIP -On .1.3.6.1.2.1.25.3.3.1.2 | grep -o ":.*" | grep -o "[0-9][0-9]*" `)
#HELP#echo targetIP=$targetIP



## Exit with warning if no data returned and therefore array is empty
if [ -z ${snmpCpuSet[0]} ]
then 
  echo -n "WARNING - NO DATA FROM SERVER | Total=0%;$warningForCpu;$criticalForCpu;0; core1=0%;0;0;0;"
      exit "1";
fi
#HELP#echo ${snmpCpuSet[@]}



##################################################
#
# Step 2: Process data - Pull out individual core
# values and calculate total system vallue. 
#
##################################################

## Get number of cores
cores=${#snmpCpuSet[@]}
#HELP#echo "cores=$cores"


## Create "output" string containing each core value
## Calculate "cpuTotal" as sum of all core values
output=""
cpuTotal=0
index=0
highestCoreValue=0
highestCoreNumber=""
while [ "$index" -lt "$cores" ]
do 
  coreNumber=$(($index + 1))
  output="$output core${coreNumber}=${snmpCpuSet[$index]}%;0;0;0;"  
  #HELP#echo output=$output
  if [ "${snmpCpuSet[$index]}" -gt "$highestCoreValue" ];
  then 
    highestCoreValue=${snmpCpuSet[$index]}
    highestCoreNumber=$coreNumber
  fi
  #HELP#echo highestCoreValue=$highestCoreValue highestCoreNumber=$highestCoreNumber 
  cpuTotal=$(($cpuTotal + ${snmpCpuSet[$index]}))
  #HELP#echo cpuTotal=$cpuTotal
  index=$(($index + 1))
done



## If "cpuTotal" is greater than 0 then divide by number of total cores to get overall CPU percentage used
if [ "$cpuTotal" -gt "0" ]
then 
  cpuTotalPercent=$(echo "scale=2; $cpuTotal / $cores;" | bc)
else
  cpuTotalPercent=0.00
 fi
#HELP#echo "cpuTotalPercent=$cpuTotalPercent"



## Put a zero infront of any number starting with a dot
if [ $(echo $cpuTotalPercent | grep "^\.") ] ; then cpuTotalPercent=0$cpuTotalPercent; fi;



## Get an integer version of overall CPU percentage used for comparison against thresholds
cpuTotalPercentInt=$(echo $cpuTotalPercent | grep -o ^[0-9][0-9]* )
#HELP#echo "cpuTotalPercentInt=$cpuTotalPercentInt"


##################################################
#
# Step 3: Output results - Compare CPU usage and 
# core usage against thresholds and exit passing
# back appropriate message to Nagios
# There are 5 possible outcomes:
#   1) CPU below warning and all cores below warning
#   2) CPU equal or above critical
#   3) A core equal or above crtical
#   4) CPU equal or above warning
#   5) A core equal or above warning
#################################################

## 1) CPU below warning and all cores below warning
if [ "$cpuTotalPercentInt" -lt "$warningForCpu" ] && [ "$highestCoreValue" -lt "$warningForCore" ]
then 
  echo -n "OK - CPU ${cpuTotalPercent}% used | Total=${cpuTotalPercent}%;$warningForCpu;$criticalForCpu;0;$output"
  exit "0"

## 2) CPU equal or above critical
elif [ "$cpuTotalPercentInt" -ge "$criticalForCpu" ]
then 
  echo -n "CRITICAL - CPU ${cpuTotalPercent}% used | Total=${cpuTotalPercent}%;$warningForCpu;$criticalForCpu;0;$output"
  exit "2"

## 3) A core equal or above crtical
elif [ "$highestCoreValue" -ge "$criticalForCore" ]
then
  echo -n "CRITICAL - Core${highestCoreNumber} ${highestCoreValue}% used, CPU ${cpuTotalPercent}% used | Total=${cpuTotalPercent}%;$warningForCpu;$criticalForCpu;0;$output"
  exit "2" 

## 4) CPU equal or above warning
elif [ "$cpuTotalPercentInt" -ge "$warningForCpu" ]
then 
  echo -n "WARNING - CPU ${cpuTotalPercent}% used | Total=${cpuTotalPercent}%;$warningForCpu;$criticalForCpu;0;$output"
  exit "1"

## 5) A core equal or above warning
else
  echo -n "WARNING - Core${highestCoreNumber} ${highestCoreValue}% used, CPU ${cpuTotalPercent}% used | Total=${cpuTotalPercent}%;$warningForCpu;$criticalForCpu;0;$output"
  exit "1"        
fi;

exit

