<?php
# DATE : Sun 15th Apr 2012
#
# AUTHOR : jascbu@gmail.com
#
# AIM : To have visibility of the activity of all the cores on a machine.
#
# DEPENDENCIES :
# 	1) This is the partner script for "check_cpu_multicore.sh" written to 
#	output CPU usage values to Nagios, including a value for each core. As
#	such you need to have that check running to make PNP4Nagios graphs with 
#	this script
#	2) Remember to name your command/service in Nagios the same name as this
#	script "check_cpu_multicore" so this script is called.
#


## Set line colours : purplegrey  pink      brown   luminousgreen pinkpurple  orange    lightblue  darkgreen darkblue
$colourArray = array("#FF91C5", "#FC00EC", "#A6524C", "#26FF00", "#C600FC", "#FFA600", "#78B7FA", "#088040", "#4300FC");



## Count the data sets being passed in to calculate how many cores there are
$totalCoreStats=0;
foreach($DS as $i => $VAL){
$totalCoreStats++;
}



## Set datasource name and graph top label
$ds_name[1] = "Server CPU Usage";
$opt[1] = "--vertical-label Percent -l0 --upper=101 --title \"CPU Usage -- $hostname\" ";



## Store total CPU value for system
## ***Change MAX to AVG or MIN for storage as you need***
$def[1]  = rrd::def("var1", $RRDFILE[1], $DS[1], "MAX");



## Loop through each core on the server storing its CPU value 
## ***Change MAX to AVG or MIN for storage as you need***
for ($coreIndexStore = 2; $coreIndexStore <= $totalCoreStats; $coreIndexStore++) {
$def[1] .= rrd::def("var$coreIndexStore", $RRDFILE[$coreIndexStore], $DS[$coreIndexStore], "MAX");
}



## Loop through each core on the server in opposite order printing its line on the graph and data under it
for ($coreIndexWrite = 2; $coreIndexWrite <= $totalCoreStats; $coreIndexWrite++) {
$coreNumber = $coreIndexWrite - 1;
$def[1] .= rrd::line1("var$coreIndexWrite", $colourArray[$coreNumber], "CPU_Core$coreNumber") ;
$def[1] .= rrd::gprint("var$coreIndexWrite", array("LAST", "AVERAGE", "MAX"), "%3.1lf $UNIT[$coreIndexWrite]");
}



## Print Total CPU usage data and graph contents
$def[1] .= rrd::line2("var1", "#000000", "CPU_TOTAL") ;
$def[1] .= rrd::gprint("var1", array("LAST", "AVERAGE", "MAX"), "%3.1lf $UNIT[1]");



## Print yellow warning line and red critical line if these values are passed in.
if ($WARN[1] != "") {
$def[1] .= "HRULE:$WARN[1]#FFFF00 ";
}
if ($CRIT[1] != "") {
$def[1] .= "HRULE:$CRIT[1]#FF0000 ";
}

?>

