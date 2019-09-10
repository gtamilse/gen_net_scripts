::cisco::eem::event_register_syslog pattern  "ROUTING-BGP-5-ADJCHANGE.*neighbor.*Down.*VRF: default.*AS: 13979.*" maxrun 750

######################################################################################################################################################
#
#  Revision No	      : v9
#  Last Updated	      : September 3, 2019
#  Created by         : Cisco Systems, Inc./Advanced Services Team
#
#
#  Description        : This EEM script will run on vRR backup routers and monitor the bgp session between the vRRb and the Primary Active RRs. If the
#                       BGP session goes down, then the script will be triggered to check the state of Primary Router to determine if this backup RR 
#                       will need to assume the role of the primary vRR.  			
#
#   ---EEM Event Trigger---
#
#		1. Triggered when BGP Session between vRRb (this router) and an Active Primary Router goes down.
#
#   Sample of Syslog Trigger:
# RP/0/RP0/CPU0:Jul 26 2019 UTC 15:37:54.658 :bgp[1060]: %ROUTING-BGP-5-ADJCHANGE : neighbor 12.122.249.252 Down - Peer closing down the session (VRF: default) (AS: 13979) 
#
#       ---EEM Checks---
#
#		    2. EEM Script will check BGP state between backup and active router (proc bgp_check), if BGP session is down then
#		    3. EEM Script will check if backup router can ping active router's loopback IP (proc lping_check), if LB ping fails then
#		    4. EEM Script will check if backup router can ping active router's MGMT IP (proc mping_check), if MGMT ping fails then
#		    5. EEM Script will check if Active Router's LB IP is present in RIB (proc route_check), if route is not present then
#		    6. EEM Script will check its reachability status to other CBB core routers to ensure it can reach other nodes and the problem is just with this one active RR (proc ltping_check),
#              if CBB Ping check indicates no problem with other connections then
#		    7. EEM Script will confirm a problem condition has been detected with one of the primary active vRRs. (proc finalcheck)
#
#           ---EEM Action---
#               8. EEM Script will then create a vrr-detection-active file to prevent other instances of detection scripts from running a remediation trigger.
#               9. EEM Script will send an email alert with full logs collected to OPs Team. (proc send_email)
#               10. EEM Script will register the remeidation script, and trigger it via a specific syslog message. (proc register_remediation)
#
#
# Pre-requisites      : This EEM scipt is designed with the understanding that the backup vRR router will only take over for one active router failure,
#                       despite being the backup for 5 active routers. In condition with multiple router failures, the backup will only take over for one
#                       active router.
#			
#		---Config required for EEM Default Login via Tacacs+ and Fallback as a Local user---
#		   Local username configured on the device and Tacacs EEM username should be same
#			username <eem-user>
#			group netadmin
#			
#			aaa authorization eventmanager default group tacacs+ local
#			
#			vty-pool eem 100 105				
#			
#
#  		---Configure the following EEM Event Manager Variables--- 
#
#           <EEM config needed for email>
#           event manager environment _email_to <email address of receipents> 
#           event manager environment _domainname <domain name>
#           event manager environment _email_from <email address of sender> 
#           event manager environment _email_server < address of email server> 
#
#           <Configure the following event manager variables and create the directories in disk0>
#           event manager environment _eem_storage_location disk0:/eem
#           event manager environment _config_storage_location disk0:/eem/configs
#           event manager environment _recovery_storage_location disk0:/eem/vRR_recovery_logs
#           event manager environment _detection_storage_location disk0:/eem/vRR_detection_logs
#           event manager environment _remediation_storage_location disk0:/eem/vRR_remediation_logs
#           event manager directory user policy disk0:/eem
#			
#		  	
#                                             
# Cisco Product tested 			: XRv9K
# Cisco IOS XR Software Version tested  : 6.5.3
#
# Copyright (c) 2019 by cisco Systems, Inc.
# All rights reserved.
#
######################################################################################################################################################

# Import EEM Libraries 
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

action_syslog msg "EEM policy vrr_detection_script.tcl has started"

#################################################################################################
#
# USER MUST DEFINE THE FOLLOWING NODE VARIABLES FOR EACH OF THE FIVE PRIMARY ACTIVE VRRS!!
# set activeRR1 [ list loop0_ip nodename mgmt_ip loop250_ip configfilelocation sleeptimer]
#
# Example:
# set activeRR1 [list 12.122.249.251 RR251 1.3.249.251 $_config_storage_location/RR251_bgp_cfg 30]

set activeRR1 [list 12.122.249.245 RR245 1.3.249.245 12.122.250.245 $_config_storage_location/RR245_bgp_cfg 30]

set activeRR2 [list 12.122.249.252 RR252 1.3.249.252 12.122.250.252 $_config_storage_location/RR252_bgp_cfg 30]

set activeRR3 [list 12.122.249.246 RR246 1.3.249.246 12.122.250.246 $_config_storage_location/RR246_bgp_cfg 30]

set activeRR4 [list 12.122.249.248 RR248 1.3.249.248 12.122.250.248 $_config_storage_location/RR248_bgp_cfg 30]

set activeRR5 [list 12.122.249.251 RR251 1.3.249.251 12.122.250.251 $_config_storage_location/RR251_bgp_cfg 30]

set cbb_ip [list 12.122.0.7 12.122.0.4]

#################################################################################################

# Verify the environment vars:
if {![info exists _detection_storage_location]} {
  set result "EEM policy error: environment var _detection_storage_location not set"
  error $result $errInfo
}
if {![info exists _config_storage_location]} {
  set result "EEM policy error: environment var _config_storage_location not set"
  error $result $errInfo
}
if {![info exists _eem_storage_location]} {
  set result "EEM policy error: environment var _eem_storage_location not set"
  error $result $errInfo
}
if {![info exists _email_server]} {
  set result "EEM policy error: environment var _email_server not set"
  error $result $errInfo
}
if {![info exists _email_from]} {
  set result "EEM policy error: environment var _email_from not set"
  error $result $errInfo
}
if {![info exists _email_to]} {
  set result "EEM policy error: environment var _email_to not set"
  error $result $errInfo
}
if {![info exists _domainname]} {
  set result "EEM policy error: environment var _domainname not set"
  error $result $errInfo
}

################################################################################


################################################################################
# Procedures
################################################################################

proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc extract_data {syslog} {

    ################################################################################
    # Procedure call to extract the IP address from the BGP syslog message.
    ################################################################################
    
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $syslog " " syslog
    
    # Remove any leading white space:
    regsub -all {^[ ]} $syslog "" syslog
    
    # Remove any ending white space:
    regsub -all {[ ]$} $syslog "" syslog
    
    regexp {neighbor (\d+\.\d+\.\d+\.\d+)} $syslog - IP
    
    # Return the IP address from the syslog 
    return $IP
  
}

proc identify_failure {IP} {

    ################################################################################
    # Identify which Active router went down and set the variables for the checks 
    #
    # These variables will need to be manually configured for each active RR!!
    ################################################################################

    global _config_storage_location activeRR1 activeRR2 activeRR3 activeRR4 activeRR5 
    
    # BGP Session IP is the 4 item in the list, so will use lindex of 3.

    if { $IP == [lindex $activeRR1 3]} {
        set id_fail $activeRR1
    } elseif { $IP == [lindex $activeRR2 3]} {
        set id_fail $activeRR2
    } elseif { $IP == [lindex $activeRR3 3]} {
        set id_fail $activeRR3
    } elseif { $IP == [lindex $activeRR4 3]} {
        set id_fail $activeRR4
    } elseif { $IP == [lindex $activeRR5 3]} {
        set id_fail $activeRR5
    }  else {

        action_syslog msg "------EEM policy vrr_detection_script initiated but node not recognized, script will exit.------"

        ######################################################################################
        # Calling runtime procedure to calculate total script runtime and close the log file.
        ######################################################################################

        runtime

        exit
    }

    set loop_ip [lindex $id_fail 0]
    set node [lindex $id_fail 1]
    set mgmt_ip [lindex $id_fail 2]
    set bgp_ip [lindex $id_fail 3]
    set configloc [lindex $id_fail 4]
    set sleep_timer [lindex $id_fail 5]
    
    #return $loop_ip
    return [list $loop_ip $node $mgmt_ip $bgp_ip $configloc $sleep_timer]
}

proc get_hostname {} {

    ################################################################################
    # Procedure call to extract the Hostname of the router
    ################################################################################

    # Open up the CLI connection to collect the show run | in hostname output

    if [catch {cli_open} result] {
        error $result $errorInfo
    } else {
        array set cli $result
    }

    if [catch {cli_exec $cli(fd) "show run | in hostname"} result] {
        error $result $errorInfo
    }

    # Extract the hostname of the Backup Router active RR's MGMT IP address from the syslog
    regexp {hostname (\w+)} $result - bknode

    # Return the hostname 
    return $bknode  
}

proc getcmd {cmd} {
    global errorInfo

    ################################################################################
    # Procedure call to collect a single command on the backup router
    ################################################################################

    if [catch {cli_open} result] {
        error $result $errorInfo
    } else {
        array set cli $result
    }
    #If its just a single command to collect
    if [catch {cli_exec $cli(fd) $cmd} result] {
        error $result $errorInfo
    } 

    #If there are multiple commands to collect
    #foreach cmd $cmds {
    #    if { [catch {cli_exec $cli(fd) $cmd} result] } {
    #        error "Failed to execute the command '$cmd': '$result'" $errorInfo
    #    }
    #}

    catch {cli_close $cli(fd) $cli(tty_id)}

    return $result
}

proc config_terminal {} {
    global errorInfo FH node
    global _recovery_storage_location _output_log
    global syslog_msg cli

    if [catch {cli_open} result] {
        error $result $errorInfo
    } else {
        array set cli $result
    }

    if [catch {cli_exec $cli(fd) "config terminal"} result] {
        error $result $errorInfo
    }

    puts $FH "Config mode outupt: $result\n"

    # Use flush command to flush buffered output to logfile 
    flush $FH

    set config_mode [regexp -all {config} $result]
    puts $FH "Config mode value: $config_mode\n"

    if { $config_mode > 1} {

        # Script is in config mode and can continue on
        puts $FH "vrr_recovery_script for node $node - config_terminal procedure successful, script entered config mode.\n"

    } else {

        # Script can not enter config mode so must quit and alert OPs team

        puts $FH "vrr_recovery_script for node $node - config_terminal procedure failed, script is unable to enter config mode.\n"
        
        action_syslog msg "EEM policy vrr_recovery_script - config_terminal procedure FAILED, script is unable to enter config mode and must quit!"

        # Use flush command to flush buffered output to logfile
        flush $FH

        ########################################################################
        # Calling send_email procedure to send alert to OPs team
        ########################################################################
        set email_subject "** Route Reflector $node triggered vRR EEM vrr_recovery_script could not enter config mode, so it quit manual intervention needed!!"

        if [catch {open $_detection_storage_location/$_output_log r} result] {
            error $result   
        }
        set bodytext [read $result]

        # Call on the send_email proc to generate an email message
        send_email $node $syslog_msg $bodytext

        ######################################################################################
        # Calling runtime procedure to calculate total script runtime and close the log file.
        ######################################################################################

        runtime

        exit

        }
    
}

proc bgp_check {bgp_ip} {
    global FH node

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running bgp_check procedure"
    action_syslog msg "------EEM policy vrr_detection_script for node $node - bgp_check procedure started------"

    ################################################################################
    # Check iBGP Between vRRb and the Active Router
    ################################################################################

    set cmd "show bgp ipv4 unicast neighbors $bgp_ip | in state "
    set result [getcmd $cmd]

    puts $FH "CLI OPEN successful for : $cmd\n"

    # Sample of CLI Output
    # RP/0/RP0/CPU0:RR253-VRR#show bgp ipv4 unicast neighbors 12.122.249.252 | in state
    # Mon Jul 29 22:19:01.190 UTC
    # BGP state = Idle (No route to multi-hop neighbor)
    #
    # RP/0/RP0/CPU0:RR253-VRR#show bgp ipv4 unicast neighbors 12.122.249.251 | in state
    # Mon Jul 29 22:19:06.064 UTC
    # BGP state = Established, up for 01:33:32

    #Regex match on "Estabilished/Idle" from output, set to variable bgp_con
    regexp {state = (\w+)} $result - bgp_con

    if { $bgp_con == "Established"} {
        puts $FH "$result\n"
        set bgp_stat 0
        set msg "EEM Dectection Script - iBGP Status between vRRb and vRR $node is in $bgp_con state, script will exit and send alert."
        puts $FH "BGP Stat Counter = $bgp_stat > $bgp_con state"
        puts $FH "$msg\n"
        action_syslog msg "EEM policy vrr_detection_script iBGP Status between vRRb and vRR $node is in $bgp_con state, script will exit and send alert."
    } elseif { $bgp_con == "Idle"} {
        puts $FH "$result\n\n"
        set bgp_stat 1
        set msg "EEM Dectection Script - iBGP Status between vRRb and vRR $node is in $bgp_con state, script will continue with the checks."
        puts $FH "BGP Stat Counter = $bgp_stat > $bgp_con state"
        puts $FH "$msg\n"
        action_syslog msg "EEM policy vrr_detection_script iBGP Status between vRRb and vRR $node is in $bgp_con state, script will continue with the checks." 
    } else {
        puts $FH "$result\n\n"
        set bgp_stat 1
        set msg "EEM Dectection Script - iBGP Status between vRRb and vRR $node is in $bgp_con state, script will continue with the checks."
        puts $FH "BGP Stat Counter = $bgp_stat > $bgp_con state (else condition)"
        puts $FH "$msg\n"
        action_syslog msg "EEM policy vrr_detection_script iBGP Status between vRRb and vRR $node is in $bgp_con state, script will continue with the checks." 
    }

    #Return the bgp_stat variable for final counter check at the end of the script
    return $bgp_stat
}

proc ping_check {ip} {
   global  FH node

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running ping_check procedure"
    action_syslog msg "------EEM policy vrr_detection_script for node $node - ping_check procedure started------"

    ################################################################################
    # Check the Active Router's Loopback0 IP Address Reachability
    ################################################################################

    set checkval 0

    foreach loop_ip $ip {

        set cmd "ping $loop_ip"
        set result [getcmd $cmd]

        puts $FH "CLI OPEN successful for : $cmd\n"

        # Sample of CLI Output
        # RP/0/RP0/CPU0:RR253-VRR#ping 12.122.249.251
        #Mon Jul 22 15:29:19.927 UTC
        #Type escape sequence to abort.
        #Sending 5, 100-byte ICMP Echos to 12.122.249.251, timeout is 2 seconds:
        #UUUUU
        #Success rate is 0 percent (0/5)

        if { [regexp {!} $result]} {
            puts $FH "$result\n"
            puts $FH "EEM Dectection Script - PING to IP $loop_ip of $node SUCCESSFUL\n"
            incr checkval 
            puts $FH "Ping Sucess counter value - $checkval"
            action_syslog msg "EEM policy vrr_detection_script PING to IP $loop_ip of $node successful."


        } else {
            puts $FH "$result\n"
            puts $FH "EEM Dectection Script - PING to IP $loop_ip of $node FAILED\n"
            puts $FH "Ping Sucess counter value - $checkval"
            action_syslog msg "EEM policy vrr_detection_script PING to IP $loop_ip of $node Failed." 

        }

    }

    if { $checkval > 0} {
    set ping_stat 0
    puts $FH "EEM policy vrr_detection_script PING check for $node successful."
    } else {
    set ping_stat 1
    puts $FH "EEM policy vrr_detection_script PING check for $node Failed."     
    }

    #Return the lping_stat variable for final counter check at the end of the script
    return $ping_stat
}

proc route_check {loop_ip} {
    global FH node sleep_timer

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running route_check procedure"
    action_syslog msg "------EEM policy vrr_detection_script for node $node - route_check procedure started------"

    ################################################################################
    # Check the RIB Route Table for the Active Router's Loopback0 IP Address
    ################################################################################

    set cmd "show route ipv4 $loop_ip/32 | in Known"
    set result [getcmd $cmd]

    puts $FH "CLI OPEN successful for : $cmd\n"
    #puts $FH "$result\n"

    # Sample of CLI Output
    #RP/0/RP0/CPU0:RR253-VRR#show route ipv4 12.122.249.251/32 | in Known
    #Tue Jul 23 15:02:15.063 UTC
    #RP/0/RP0/CPU0:RR253-VRR#show route ipv4 12.122.249.252/32 | in Known
    #Tue Jul 23 15:02:18.983 UTC
    #  Known via "ospf 2", distance 110, metric 65586, type intra area

    # Check the result to see if the "Known" key word is present in the output. 
    # Use the regexp -all option to count the number of matches in the output.
    set route_count [regexp -all {Known} $result]

    if { $route_count > 1 } {
        set route_counter 0
        puts $FH "Routes Found - Script will wait 30 sec and check again."
        puts $FH "$result\n"
        
        while {$route_counter <= 4} {
            puts $FH "Waiting $sleep_timer Seconds"
            sleep $sleep_timer

            set cmd "show route ipv4 $loop_ip/32 | in Known"
            set result [getcmd $cmd]
            
            set route_count [regexp -all {Known} $result]

            if { $route_count > 1} {
                incr route_counter
                puts $FH "$result\n"
                puts $FH "Routes Found - Script will wait 30 sec and check again. Loop Counter = $route_counter\n"
            } else {
                puts $FH "$result\n"
                puts $FH "No Routes Found After $route_counter iterations, Route_count = $route_count\n"
                set route_counter 6
            }
        }
        if { $route_counter <= 5 } {
            set route_stat 0
            set msg "EEM Dectection Script - RIB Route check for $loop_ip of $node show route is still present after $route_counter iterations of waiting, script will exit and send alert."
            puts $FH "Route Count = $route_count > routes found"
            puts $FH "RIB Route Stat Counter = $route_stat > Route Present"
            puts $FH "$msg\n"
            action_syslog msg "EEM Dectection Script - RIB Route check for $loop_ip of $node successful, route found, script will exit and send alert."
        } else {
            set route_stat 1
            set msg "EEM Dectection Script - RIB Route check for $loop_ip of $node Failed, route not found, script will continue with the checks."
            puts $FH "Route Count = $route_count > no routes found"
            puts $FH "RIB Route Stat Counter = $route_stat > Route Not Present"
            puts $FH "$msg\n"
            action_syslog msg "EEM Dectection Script - RIB Route check for $loop_ip of $node Failed, route not found, script will continue with the checks."
        }      

    } elseif { $route_count == 1 } {
        puts $FH "$result\n\n"
        set route_stat 1
        set msg "EEM Dectection Script - RIB Route check for $loop_ip of $node Failed, route not found (elseif condition), script will continue with the checks."
        puts $FH "Route Count = $route_count > no routes found"
        puts $FH "RIB Route Stat Counter = $route_stat > Route Not Present"
        puts $FH "$msg\n"
        action_syslog msg "EEM Dectection Script - RIB Route check for $loop_ip of $node Failed, route not found, script will continue with the checks."
    } else {
        puts $FH "$result\n\n"
        set route_stat 1
        set msg "EEM Dectection Script - RIB Route check for $loop_ip of $node Failed, route not found (else condition), script will continue with the checks."
        puts $FH "Route Count = $route_count > no routes found"
        puts $FH "RIB Route Stat Counter = $route_stat > Route Problem"
        puts $FH "$msg\n"
        action_syslog msg "EEM Dectection Script - RIB Route check for $loop_ip of $node Failed, route not found, script will continue with the checks."
    }

    #return $loop_ip
    return $route_stat
}

proc register_remediation {} {
    global FH node
    global errorInfo cli
    
    ################################################################################
    # Procedure call to Register the EEM Remediation Script
    ################################################################################

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Register the EEM Remediation Script \n"
    action_syslog msg "------EEM policy vrr_detection_script for node $node - register_remediation procedure started------"

    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

    config_terminal
    
    if [catch {cli_exec $cli(fd) "event manager policy vrr_remediation_script.tcl username eem-user"} result] {
        error $result $errorInfo
    }
    if [catch {cli_exec $cli(fd) "show"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    if [catch {cli_exec $cli(fd) "commit"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    if [catch {cli_exec $cli(fd) "exit"} result] {
        error $result $errorInfo
    }
    
    if [catch {cli_exec $cli(fd) "show event manager policy registered"} result] {
        error $result $errorInfo
    } 
    puts $FH "$result\n"
    set policy_exist [regexp -all {remediation} $result]

    return $policy_exist
}

proc runtime {} {
    global FH t0 node

    ################################################################################
    # TimeStamp to indicate total Script Runtime and close the log file.
    # runtime procedure is called at the end when script near completion.
    ################################################################################

    set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]

    puts $FH "\n*Timestamp = $date"
    puts $FH "\nScript Runtime = [expr {([clock clicks -millisec]-$t0)/1000.}] sec"
    puts $FH "====================================================================================================================================="

    #Close the log file and finish the script

    close $FH

    # Send syslog message:
    action_syslog msg "------EEM policy vrr_detection_script for node $node completed!!------"
}

proc finalcheck {} {
    global bgp_stat lping_stat route_stat mping_stat cbbping_stat node FH t0 bkp_ext
    global node configloc mgmt_ip loop_ip bgp_ip

    ###########################################################################################################
    # Final check of all the stat counters to see if failure event has occured 
    ###########################################################################################################

    if { ($bgp_stat + $lping_stat +$mping_stat + $route_stat + $cbbping_stat) == 5 } {

        set msg "EEM Dectection Script has detected a Failure for node $node"
        puts $FH "====================================================================================================================================="
        puts $FH "FINAL DETECTION SCRIPT SUMMARY\n"
        puts $FH "BGP Stat Counter = $bgp_stat > No Connetion"
        puts $FH "Loopback Ping Stat Counter = $lping_stat > Not Reachable"
        puts $FH "MGMT Ping Stat Counter = $mping_stat > Not Reachable"
        puts $FH "RIB Route Stat Counter = $route_stat > Route Not Present"
        puts $FH "CBB PING Stat Counter = $cbbping_stat > vRRb is working normally"
        puts $FH "\n$msg\n"

        action_syslog msg "EEM policy vrr_detection_script has detected a Failure for node $node"

        ################################################################################
        # Check if vrr-detection-active file exists, if it does not exist then create one.
        ################################################################################
        
        # Dont need to set bkp_ext again, already defined in global.
        #set bkp_ext "$_detection_storage_location/vrr-detection-active"

        # If the vrr-detection-active file already exists then quit the script, as this indicates that another detection script is in progress.
        if [file exists $bkp_ext] {

            if [catch {open $bkp_ext r} result] {
                error $result   
            }

            set BFH [read $result]
            puts $FH "Backup file already exists for node $BFH\n"
            puts $FH "Script was initated for node $node but will exit now since this backup router will become active router for node $BFH\n"

            # Use flush command to flush buffered output to logfile
            flush $FH

            action_syslog msg "------EEM policy vrr_detection_script initiated for node $node but will exit now since vrr-detection-active file exists.------"


            ########################################################################
            # Calling send_email procedure to send alert to OPs team
            ########################################################################
            set email_subject "** RR $node triggered EEM Detection Script but can not continue since vRRb is already becoming active for $BFH router"

            if [catch {open $_detection_storage_location/$_output_log r} result] {
                error $result   
            }
            set bodytext [read $result]

            # Call on the send_email proc to generate an email message
            send_email $node $syslog_msg $bodytext

            ######################################################################################
            # Calling runtime procedure to calculate total script runtime and close the log file.
            ######################################################################################

            runtime

            exit
            

        } else {

            # Since there is no vrr-detection-active file, create one and insert the node name of the active RR. 
            # So future detection scripts will know this backup router is already in progress to become an active router.

            if [catch {open $bkp_ext w} result] {
                error $result
            }

            set CBFH $result
            puts $CBFH "node $node config_file_location $configloc vRR_MGMT_IP $mgmt_ip vRR_Loop_IP $loop_ip vRR_BGP_IP $bgp_ip"
            close $CBFH

            puts $FH "Backup file (vrr-detection-active) created for node $node failure.\n"

        }

    } else {

        set msg "EEM Dectection Script has detected no failures for node $node"
        puts $FH "====================================================================================================================================="
        puts $FH "FINAL DETECTION SCRIPT SUMMARY\n"
        puts $FH "BGP Stat Counter = $bgp_stat > Connection OK"
        puts $FH "Loopback Ping Stat Counter = $lping_stat >  Reachable"
        puts $FH "RIB Route Stat Counter = $route_stat > Route Present"
        puts $FH "MGMT Ping Stat Counter = $mping_stat > Reachable"
        puts $FH "CBB PING Stat Counter = $cbbping_stat > vRRb is not working normally, cant reach core routers"
        puts $FH "\n$msg\n"

        action_syslog msg "EEM Dectection Script has detected no failures for node $node"
    }

}

proc send_email {node syslog_msg bodytext} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending Email Alert - EEM vRR Detection for node $node to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "Route Reflector $node triggered vRR EEM Detection Script"]
    set email [format "%s\n%s\n\n" "$email" "$syslog_msg\n\n"]
    set email [format "%s\n%s" "$email" "$bodytext"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
 
    puts $FH "\n****EMAIL ALERT SENT TO: $_email_to *****\n"
    #puts $FH $email
  }
}

################################################################################
# MAIN
################################################################################
   
########################################################################
# Set Globals Variables:
########################################################################

global FH
global _email_to _email_from
global _email_server _domainname
global email_subject

set t0 [clock clicks -millisec]
set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
set stamp [clock format [clock sec] -format "%T_%b_%d_%Y"]
regsub -all {:} $stamp "." stamp
set _output_log "eem_vrr_detection_$stamp"

set bgp_stat 0
set lping_stat 0
set route_stat 0
set mping_stat 0
set cbbping_stat 0

###############################################################
# Procedure (get_hostname) to get the router's hostname
###############################################################
set bknode [get_hostname]

###############################################################
# Open the output file (for write):
###############################################################

if [catch {open $_detection_storage_location/$_output_log w} result] {
    error $result
}
set FH $result

puts $FH "====================================================================================================================================="
puts $FH "*Timestamp = $date"
puts $FH "Cisco vRRb $bknode Detection Script"
puts $FH "=====================================================================================================================================\n"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message:
set syslog_msg $arr_einfo(msg)

###############################################################
# Get the Neighbor IP address from the triggering syslog_msg
###############################################################

set IP [extract_data $syslog_msg]

puts $FH "SYSLOG MSG:\n$syslog_msg\n"
puts $FH "Backup vRR: $bknode\n"
puts $FH "BGP Neighbor IP Address: $IP"

###############################################################
#Use the IP address of BGP session to extract key variables
###############################################################

set idfail [identify_failure $IP]
set loop_ip   [lindex $idfail 0]
set node      [lindex $idfail 1]
set mgmt_ip   [lindex $idfail 2]
set bgp_ip   [lindex $idfail 3]
set configloc [lindex $idfail 4]
set sleep_timer [lindex $idfail 5]

puts $FH "Node Loopback IP: $loop_ip"
puts $FH "Node Name: $node"
puts $FH "Node MGMT IP: $mgmt_ip"
puts $FH "Node BGP IP: $bgp_ip"
puts $FH "Node Config File Location: $configloc"
puts $FH "Sleep Timer: $sleep_timer\n"

########################################################################
# Check if vrr-detection-active file exists, quit if it does
########################################################################
set bkp_ext "$_eem_storage_location/vrr-detection-active"

# If the $run_flag file exists exit from script:
if [file exists $bkp_ext] {

    if [catch {open $bkp_ext r} result] {
        error $result   
    }

    set BFH [read $result]

    puts $FH "Backup file already exists for node $BFH\n"
    puts $FH "Script was initiated for active vRR $node on backup vRR $bknode but will exit now since this backup router will become active router for $BFH\n"

    # Use flush command to flush buffered output to logfile
    flush $FH

    action_syslog msg "------EEM policy vrr_detection_script initiated for active vRR $node on backup vRR $bknode but will exit now since vrr-detection-active file exists.------"


    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** RR $node triggered EEM Detection Script on backup vRR $bknode but can not continue since vRRb is already becoming active for $BFH router"

    if [catch {open $_detection_storage_location/$_output_log r} result] {
        error $result   
    }
    set bodytext [read $result]

    # Call on the send_email proc to generate an email message
    send_email $node $syslog_msg $bodytext

    ######################################################################################
    # Calling runtime procedure to calculate total script runtime and close the log file.
    ######################################################################################

    runtime

    exit
}


########################################################################
# Starting Conditional Checks
########################################################################

# Sleep 5 seconds before starting the checks
sleep 5

########################################################################
# Check iBGP Session Status between vRRb and the Active Router
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nBGP Session Status Check between vRRb ($bknode) and the Active Router ($node)\n"

set bgp_stat [bgp_check $bgp_ip]
puts $FH "Post bgp_stat = $bgp_stat after bgp_check\n"
puts $FH "bgp_check procedure completed\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_detection_script for active vRR $node on backup vRR $bknode - bgp_check procedure completed------"

if { $bgp_stat == 1 } {

    ########################################################################
    # Check the Active Router's Loopback0 IP Address Reachability
    ########################################################################
    puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "\nPing Check between vRRb ($bknode) and the Active Router's ($node) Loopback0 IP address\n"

    set ping_stat [ping_check $loop_ip]

    if { $ping_stat == 0} {

        puts $FH "Loopback Ping Stat Counter = $ping_stat > Reachable after loopback 0 ping_check\n"
        set lping_stat 0

    } else {
        puts $FH "Loopback Ping Stat Counter = $ping_stat > Not Reachable after loopback 0 ping_check\n"
        set lping_stat 1
    }

    puts $FH "ping_check procedure for Loopback0 IP completed on backup vRR $bknode\n"

    # Use flush command to flush buffered output to logfile
    flush $FH

    action_syslog msg "------EEM policy vrr_detection_script for active vRR $node on backup vRR $bknode - ping_check procedure for loopback0 completed------"

    if { $lping_stat == 1 } {

        ########################################################################
        # Check the Active Router's MGMT Interface IP Address Reachability
        ########################################################################
        puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
        puts $FH "\nPing Check between vRRb ($bknode) and the Active Router's ($node) MGMT IP address\n"

        set ping_stat [ping_check $mgmt_ip]

        if { $ping_stat == 0} {

            puts $FH "Loopback Ping Stat Counter = $ping_stat > Reachable after MGMT_IP ping_check\n"
            set mping_stat 0

        } else {
            puts $FH "Loopback Ping Stat Counter = $ping_stat > Not Reachable after MGMT_IP ping_check\n"
            set mping_stat 1
        }

        puts $FH "ping_check procedure for MGMT_IP completed on backup vRR $bknode\n"

        # Use flush command to flush buffered output to logfile
        flush $FH

        action_syslog msg "------EEM policy vrr_detection_script for active vRR $node on backup vRR $bknode - ping_check procedure for MGMT_IP completed------"

        if { $mping_stat == 1 } {

            ########################################################################
            # Check the RIB Route Table for the Active Router's Loopback0 IP Address
            ########################################################################
            puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
            puts $FH "\nRIB Route Check for the Active Router's Loopback0 address on backup vRR $bknode\n"

            set route_stat [route_check $loop_ip]
            puts $FH "Post route_stat = $route_stat after route_check\n"
            puts $FH "route_check procedure completed\n"

            # Use flush command to flush buffered output to logfile
            flush $FH

            action_syslog msg "------EEM policy vrr_detection_script for active vRR $node on backup vRR $bknode - route_check procedure completed------"

            if { $route_stat == 1 } {

                #################################################################################################################
                # Check the Backup Router's Reachability to the CBB core routers to ensure there is no fault on the vRRb Router
                #################################################################################################################
                puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
                puts $FH "\nPing Check between vRRb and CBB Core Routers to ensure vRRB ($bknode) is not isolated\n"

                set ping_stat [ping_check $cbb_ip]
                
                if { $ping_stat == 0} {
                    set cbbping_stat 1
                    puts $FH "Loopback Ping Stat Counter = $cbbping_stat > vRRb router is not isolated\n"
                
                } else {
                    set cbbping_stat 0
                    puts $FH "Loopback Ping Stat Counter = $ping_stat > vRRb router is isolated, cant reach Core Routers\n"

                }

                puts $FH "ping_check procedure completed on backup vRR $bknode\n"

                # Use flush command to flush buffered output to logfile
                flush $FH

                action_syslog msg "------EEM policy vrr_detection_script for active vRR $node on backup vRR $bknode - ping_check procedure for CBB Core Routers completed------"

                if { $cbbping_stat == 1 } {

                    ###############################################################################
                    # Calling finalcheck procedure to determine if failure condition was detected.
                    ###############################################################################

                    finalcheck

                    # Use flush command to flush buffered output to logfile
                    flush $FH

                    ########################################################################
                    # Calling send_email procedure to send alert to OPs team
                    ########################################################################
                    set email_subject "** Route Reflector $node has failed, backup Router ($bknode) has detected a failure and will now become the active router."

                    if [catch {open $_detection_storage_location/$_output_log r} result] {
                        error $result   
                    }
                    set bodytext [read $result]

                    # Call on the send_email proc to generate an email message
                    send_email $node $syslog_msg $bodytext


                    ########################################################################
                    # Register Remediation Script on vRRb router
                    ########################################################################
                    puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"

                    set policy_exist [register_remediation]

                    if { $policy_exist >= 1} {
                        puts $FH "policy_exist = $policy_exist  > Registration Successful"
                        puts $FH "Policy registration successful\n"
                        action_syslog msg "------EEM policy vrr_detection_script on backup vRR $bknode - remediation script registeration successful------"

                    } else {
                        puts $FH "policy_exist = $policy_exist  > Registration unsuccessful"
                        puts $FH "Policy registration unsuccessful, recommend manual intervention to check remediation script registeration\n"
                        action_syslog msg "------EEM policy vrr_detection_script on backup vRR $bknode - remediation script registeration unsuccessful, needs attention!------"

                        ########################################################################
                        # Calling send_email procedure to send alert to OPs team
                        ########################################################################
                        set email_subject "** Route Reflector $node vRR EEM Detection Script on backup vRR $bknode is not able to register the remediation policy, manual intervention needed!"

                        #if [catch {open $_detection_storage_location/$_output_log r} result] {
                        #    error $result   
                        #}

                        set bodytext {
                            vRR EEM Detection Script has detected and confirmed the failure of a primary vRR but is unable to register and trigger the remediation script.

                            Manual Intervention is needed to register and trigger the remediaton script. Perform the following actions:

                            Register the policy:
                                event manager policy vrr_remediation_script.tcl username eem-user persist-time 3600
                            
                            Check the last captures inside the log file generated to identify the trigger message needed to initiate the remediation script.
                            Log file is located on the vRRb router - disk0:/eem/vRR_detection_logs/
                        }
                        #set bodytext [read $result]

                        # Call on the send_email proc to generate an email message
                        send_email $node $syslog_msg $bodytext
                    }

                    # Use flush command to flush buffered output to logfile
                    flush $FH


                    action_syslog msg "------EEM policy vrr_detection_script on backup vRR $bknode- register_remediation procedure completed------"

                    ######################################################################################
                    # Identify the config file needed for the remediation script
                    ######################################################################################

                    # If the $run_flag file exists exit from script:
                    if [file exists $configloc] {

                        puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
                        puts $FH "Starting Procedure to Trigger the EEM Remediation Script \n"
                        puts $FH "RR $node Config file exists in $configloc location on backup router."
                        puts $FH "Remeidation syslog message can be sent to trigger remeidaiton script.\n"

                        action_syslog msg "------EEM policy vrr_syslog_detection script for node $node - $configloc config file exists------"
                        
                        puts $FH "Initiate Remediation Trigger Syslog message"
                        puts $FH "+++++EEM policy vrr_remediation_script for node $node config_file_location $configloc vRR_MGMT_IP $mgmt_ip vRR_Loop_IP $loop_ip vRR_BGP_IP $bgp_ip start now!!+++++"

                        # Use flush command to flush buffered output to logfile
                        flush $FH


                        ######################################################################################
                        # Calling runtime procedure to calculate total script runtime and close the log file.
                        ######################################################################################

                        runtime

                        action_syslog msg "+++++EEM policy vrr_remediation_script for node $node config_file_location $configloc vRR_MGMT_IP $mgmt_ip vRR_Loop_IP $loop_ip vRR_BGP_IP $bgp_ip start now!!+++++"

                        exit

                    } else {

                        puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
                        puts $FH "Procedure to Trigger the EEM Remediation Script Failed \n"
                        puts $FH "RR $node Config file does not exist in $configloc location on backup vRR $bknode."
                        puts $FH "Remeidation syslog message WILL NOT be sent, trigger remeidaiton script manually!!\n"

                        # Use flush command to flush buffered output to logfile
                        flush $FH

                        action_syslog msg "------EEM policy vrr_detection_script for node $node on backup vRR $bknode - $configloc config file does not exists------"


                        ######################################################################################
                        # Calling runtime procedure to calculate total script runtime and close the log file.
                        ######################################################################################

                        runtime

                        exit

                    }

                } elseif { $cbbping_stat == 0 } {

                    ###############################################################################
                    # Calling finalcheck procedure to determine if failure condition was detected.
                    ###############################################################################

                    finalcheck

                    # Use flush command to flush buffered output to logfile
                    flush $FH

                    ########################################################################
                    # Calling send_email procedure to send alert to OPs team
                    ########################################################################
                    set email_subject "** Route Reflector $node triggered vRR EEM Detection Script on backup vRR $bknode CBB Core Ping Check Failed"

                    if [catch {open $_detection_storage_location/$_output_log r} result] {
                        error $result   
                    }
                    set bodytext [read $result]

                    # Call on the send_email proc to generate an email message
                    send_email $node $syslog_msg $bodytext

                    ######################################################################################
                    # Calling runtime procedure to calculate total script runtime and close the log file.
                    ######################################################################################

                    runtime

                    exit
                }

            } elseif { $route_stat == 0 } {
                
                ###############################################################################
                # Calling finalcheck procedure to determine if failure condition was detected.
                ###############################################################################

                finalcheck
                
                    # Use flush command to flush buffered output to logfile
                flush $FH

                ########################################################################
                # Calling send_email procedure to send alert to OPs team
                ########################################################################
                set email_subject "** Route Reflector $node triggered vRR EEM Detection Script on backup vRR $bknode RIB Route Check Failed"

                if [catch {open $_detection_storage_location/$_output_log r} result] {
                    error $result   
                }
                set bodytext [read $result]

                # Call on the send_email proc to generate an email message
                send_email $node $syslog_msg $bodytext

                ######################################################################################
                # Calling runtime procedure to calculate total script runtime and close the log file.
                ######################################################################################
                
                runtime
                
                exit
            }

        } elseif { $ming_stat == 0 } {
            
            ###############################################################################
            # Calling finalcheck procedure to determine if failure condition was detected.
            ###############################################################################

            finalcheck

            # Use flush command to flush buffered output to logfile
            flush $FH

            ########################################################################
            # Calling send_email procedure to send alert to OPs team
            ########################################################################
            set email_subject "** Route Reflector $node triggered vRR EEM Detection Script on backup vRR $bknode but MGMT Ping Check Failed"

            if [catch {open $_detection_storage_location/$_output_log r} result] {
                error $result   
            }
            set bodytext [read $result]

            # Call on the send_email proc to generate an email message
            send_email $node $syslog_msg $bodytext

            ######################################################################################
            # Calling runtime procedure to calculate total script runtime and close the log file.
            ######################################################################################
            
            runtime

            exit
        }

    } elseif { $lping_stat == 0 } {
        
        ###############################################################################
        # Calling finalcheck procedure to determine if failure condition was detected.
        ###############################################################################

        finalcheck

        # Use flush command to flush buffered output to logfile
        flush $FH

        ########################################################################
        # Calling send_email procedure to send alert to OPs team
        ########################################################################
        set email_subject "** Route Reflector $node triggered vRR EEM Detection Script on backup vRR $bknode but Loopback Ping Check Failed"

        if [catch {open $_detection_storage_location/$_output_log r} result] {
            error $result   
        }
        set bodytext [read $result]

        # Call on the send_email proc to generate an email message
        send_email $node $syslog_msg $bodytext

        ######################################################################################
        # Calling runtime procedure to calculate total script runtime and close the log file.
        ######################################################################################

        runtime

        exit
    }


} elseif { $bgp_stat == 0 } {

    ###############################################################################
    # Calling finalcheck procedure to determine if failure condition was detected.
    ###############################################################################

    finalcheck

    # Use flush command to flush buffered output to logfile
    flush $FH

    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** Route Reflector $node triggered vRR EEM Detection Script on backup vRR $bknode but BGP Check failed"

    if [catch {open $_detection_storage_location/$_output_log r} result] {
        error $result   
    }
    set bodytext [read $result]

    # Call on the send_email proc to generate an email message
    send_email $node $syslog_msg $bodytext

    ######################################################################################
    # Calling runtime procedure to calculate total script runtime and close the log file.
    ######################################################################################

    runtime

    exit

}