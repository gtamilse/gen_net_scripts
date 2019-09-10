::cisco::eem::event_register_syslog pattern  "ROUTING-BGP-5-ADJCHANGE.*neighbor.*Up.*VRF: default.*AS: 13979.*" maxrun 600

#::cisco::eem::event_register_syslog pattern  "HA-HA_EEM-6-ACTION_SYSLOG_LOG_INFO.*EEM policy vrr_recovery_script.*node.*start.*" maxrun 600

######################################################################################################################################################
#
#  Revision No	      : v5
#  Last Updated	      : September 3, 2019
#  Created by         : Cisco Systems, Inc./Advanced Services Team
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

action_syslog msg "EEM policy vrr_recovery_script.tcl has started"

#################################################################################################
#
# USER MUST DEFINE THE FOLLOWING VARIABLES BELOW: recoveryfile, and sleeptimer
#
# Example:
# set recoveryfile "disk0:/eem/configs/recovery_cleanup_cfg"
# set sleeptimer 30

set recoveryfile "disk0:/eem/configs/recovery_cleanup_cfg"

set sleeptimer 30

#################################################################################################

# Verify the environment vars:
if {![info exists _recovery_storage_location]} {
  set result "EEM policy error: environment var _recovery_storage_location not set"
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


#################################################################################################


###########################################
# Procedures
###########################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
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

proc extract_ip {syslog} {

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
    
    # Extract the node name from the syslog
    regexp {node (\w+)} $syslog - node
    
    # Extract the config file location from the syslog
    regexp {config_file_location ((\w+:/)(\w+/)(\w+/)(\w+))} $syslog - configloc

    # Extract the failed active RR's MGMT IP address from the syslog
    regexp {vRR_MGMT_IP (\d+\.\d+\.\d+\.\d+)} $syslog - mgmt_ip

    # Extract the failed active RR's MGMT IP address from the syslog
    regexp {vRR_Loop_IP (\d+\.\d+\.\d+\.\d+)} $syslog - loop_ip

    # Extract the failed active RR's MGMT IP address from the syslog
    regexp {vRR_BGP_IP (\d+\.\d+\.\d+\.\d+)} $syslog - bgp_ip

    # Return the IP address from the syslog 
    return [list $node $configloc $mgmt_ip $loop_ip $bgp_ip]
  
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

proc ping_check {ip} {
   global  FH node

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running ping_check procedure"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - ping_check procedure started------"

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
            puts $FH "EEM Recovery Script - PING to IP $loop_ip of $node SUCCESSFUL\n"
            incr checkval 
            puts $FH "Ping Sucess counter value - $checkval"
            action_syslog msg "EEM policy vrr_recovery_script PING to IP $loop_ip of $node successful, script will exit and send alert.\n"


        } else {
            puts $FH "$result\n"
            puts $FH "EEM Recovery Script - PING to IP $loop_ip of $node FAILED\n"
            puts $FH "Ping Sucess counter value - $checkval"
            action_syslog msg "EEM policy vrr_recovery_script PING to IP $loop_ip of $node Failed, script will continue with the checks.\n" 

        }

    }

    if { $checkval > 0} {
    set ping_stat 0
    puts $FH "EEM policy vrr_recovery_script PING check for $node successful, script will continue with the checks."
    } else {
    set ping_stat 1
    puts $FH "EEM policy vrr_recovery_script PING check for $node Failed, script will exit and send alert."     
    }

    #Return the lping_stat variable for final counter check at the end of the script
    return $ping_stat
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

        if [catch {open $_recovery_storage_location/$_output_log r} result] {
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

proc unregister_remediation {} {
    global FH node
    global errorInfo cli

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to unregister Remediation Policy \n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - unregister_remediation procedure started------"

    config_terminal
    
    if [catch {cli_exec $cli(fd) "no event manager policy vrr_remediation_script.tcl username eem-user"} result] {
        error $result $errorInfo
    }
    
    if [catch {cli_exec $cli(fd) "commit"} result] {
        error $result $errorInfo
    }

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


proc load_config {fileloc} {
    global FH node load_stat 
    global _recovery_storage_location _output_log
    global cli 
    
    ################################################################################
    # Procedure call to load and commit the configuration needed for this  router to become the Backup Router.
    ################################################################################

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "EEM vrr_recovery_script - Starting Procedure to Load the configuration on vRRb\n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node on backup vRR - load_commit_file procedure started------"

    config_terminal
    
    set checkval 0

    foreach loadfile $fileloc {

        # Load config from disk0:/eem/configs/ Dir, EEM event manager global variable _config_storage_location must be set!
        if [catch {cli_exec $cli(fd) "load $loadfile"} result] {
            error $result $errorInfo
        }
        puts $FH "Load operation captures: \n$result\n"

        # Example of successful Load operation
        #
        #load disk0:/eem/configs/RR252_bgp_cfg
        #
        #Loading.
        #411 bytes parsed in 1 sec 
        #RP/0/RP0/CPU0:RR253-VRR(config-bgp-nbr-af)#
        #
        # Example for failure case
        #
        # RP/0/RP0/CPU0:RR253-VRR(config)#load disk0:/eem/configs/RR252_bgp_cfgerd
        # % Couldn't open file disk0:/eem/configs/RR252_bgp_cfgerd: No such file or directory
        # RP/0/RP0/CPU0:RR253-VRR(config)#

        # Check the load operation result for an errors. See below comments.

        set load_fail [regexp -all {No|file} $result]
        puts $FH "load_fail value = $load_fail\n"

        if [catch {cli_exec $cli(fd) "root"} result] {
            error $result $errorInfo
        }

        if [catch {cli_exec $cli(fd) "show"} result] {
            error $result $errorInfo
        }
        # Copy loaded config to log file
        puts $FH "Show loaded config before committing: \n$result\n"

        # Use flush command to flush buffered output to logfile
        flush $FH

        if {$load_fail >= 1} {
            incr checkval
            puts $FH "vrr_recovery_script load_config procedure FAILED to load $loadfile \n"
            puts $FH "------------------------------------------------------------------\n" 
            action_syslog msg "vrr_recovery_script load_config procedure FAILED to load $loadfile \n"   
        } else {
            puts $FH "vrr_recovery_script load_config procedure SUCCESSFUL to load $loadfile \n"
            puts $FH "------------------------------------------------------------------\n"
            action_syslog msg "vrr_recovery_script load_config procedure SUCCESSFUL to load $loadfile \n"
        }
    }

    # Check the load operation result for an errors. If load_file matches on No or file text it indicates a problem condition.
    # Load_fail value of 1 or greater is considered a failure of load operation
    # Load_fail value should be 0 if load operation is successful

    if {$checkval >= 1} {

        # Load operation failed, script will exit and send an email alert.
        puts $FH "vrr_recovery_script for node $node - load_config procedure failed at load operation.\n"
        puts $FH "Load operation Failed, Manunal intervention required to load the config files. "

        set load_stat 1

        action_syslog msg "EEM policy vrr_recovery_script - Config load operation FAILED, when loading config for prior active node $node"


        # Use flush command to flush buffered output to logfile
        flush $FH

        # Exit without commiting since load operation failed

        if [catch {cli_exec $cli(fd) "root"} result] {
        error $result $errorInfo
        }

        if [catch {cli_exec $cli(fd) "end"} result] {
        error $result $errorInfo
        }

        if [catch {cli_exec $cli(fd) "no\n"} result] {
        error $result $errorInfo
        }

    } else {
        
        # Load_fail value of 0 indicates no problems with load operation, script can continue on with the commit.

        puts $FH "vrr_recovery_script for node $node - load_config procedure load operation successful, moving on to commit action.\n"

        set load_stat 0
        
        action_syslog msg "EEM policy vrr_recovery_script - Config load operation completed SUCCESSFULLY with config for prior active node $node"

        # Use flush command to flush buffered output to logfile
        flush $FH

    }

    return $load_stat
}

proc commit_config {} {
    global FH node 
    global cli errInfo 

    #puts $FH "--------------------------------------------------------------------------"
    puts $FH "EEM policy vrr_recovery_script - Starting commit_config procedure"
    
    # COMMIT the loaded config
    if [catch {cli_exec $cli(fd) "commit"} result] {
        error $result $errorInfo
    } 

    # Wait 30 sec for config changes to apply
    sleep 5

    # Caputre the commit operation output and write it to the log file
    puts $FH "Commit operation captures: $result\n"
    
    # Chceck the commit output for any commit errors
    set commit_fail [regexp -all {Failed|Syntax|Error} $result]
    puts $FH "commit_fail value = $commit_fail\n"
    
    # Use flush command to flush buffered output to logfile
    flush $FH

    # Check the commit operation result for an errors. If commit_fail matches on Failed or Syntax or Error text it indicates a problem condition.
    # Commit_fail value of 1 or greater is considered a failure of commit operation
    # Commit_fail value should be 0 if commit operation is successful

    if {$commit_fail >= 1} {

        # Capture the show configuration failed output and store it in log file
        if [catch {cli_exec $cli(fd) "show configuration failed"} result] {
        error $result $errorInfo
        }

        puts $FH "Show configuration failed output: $result\n"

        # Load operation failed, exit script and send email alert.
        puts $FH "vrr_recovery_script for node $node - commit_config procedure failed at commit config operation.\n"
        puts $FH "Commit operation Failed, Manunal intervention required to commit the config in file \n"

        set commit_stat 1

        action_syslog msg "EEM policy vrr_recovery_script - Config commit operation FAILED, to commit with config for prior active node $node"

        # Use flush command to flush buffered output to logfile
        flush $FH

    } else {
        
        # Commit_fail value of 0 indicates no problems with commit operation, script can continue on with the checks.

        puts $FH "vrr_recovery_script for node $node - commit_config procedure commit operation SUCCESSFUL, script will continue the checks.\n"

        set commit_stat 0

        action_syslog msg "EEM policy vrr_recovery_script - Config commit operation completed SUCCESSFULLY, with config for prior active node $node"

        if [catch {cli_exec $cli(fd) "end"} result] {
        error $result $errorInfo
        }

        # Use flush command to flush buffered output to logfile
        flush $FH

    }

    return $commit_stat
}

proc shut_uplink {} {
    global FH node
    global errorInfo cli

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Shutdown vRRb router's uplink interfaces \n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - shut_uplink procedure started------"


    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

    config_terminal
    
    if [catch {cli_exec $cli(fd) "interface GigabitEthernet0/0/0/0 "} result] {
        error $result $errorInfo
    }
    
    if [catch {cli_exec $cli(fd) "shutdown"} result] {
        error $result $errorInfo
    }

    if [catch {cli_exec $cli(fd) "interface GigabitEthernet0/0/0/1 "} result] {
        error $result $errorInfo
    }
    
    if [catch {cli_exec $cli(fd) "shutdown"} result] {
        error $result $errorInfo
    }

    if [catch {cli_exec $cli(fd) "root"} result] {
        error $result $errorInfo
    }

    if [catch {cli_exec $cli(fd) "commit"} result] {
        error $result $errorInfo
    }

    if [catch {cli_exec $cli(fd) "exit"} result] {
        error $result $errorInfo
    }
    
    if [catch {cli_exec $cli(fd) "show ip interface brief | in Giga"} result] {
        error $result $errorInfo
    } 
    puts $FH "$result\n"
    set intf_down [regexp -all {Shutdown} $result]

    return $intf_down
}

proc route_check {loop_ip} {
    global FH node sleeptimer

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running route_check procedure"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - loopback 0 route_check procedure started------"

    set route_count 0

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
    set route_count [regexp -all {ospf} $result]

    if { $route_count == 0 } {
        set route_counter 0
        puts $FH "Route Not Found - Script will wait 30 sec and check again."
        puts $FH "$result\n"
        
        while {$route_counter <= 4} {
            puts $FH "Waiting $sleeptimer Seconds" 
            sleep $sleeptimer

            set cmd "show route ipv4 $loop_ip/32 | in Known"
            set result [getcmd $cmd]
            
            set route_count [regexp -all {ospf} $result]

            if { $route_count == 0} {
                incr route_counter
                puts $FH "$result\n"
                puts $FH "No Routes Found - after $route_counter iterations, Route_count = $route_count Script will continue waiting\n"
            } else {
                puts $FH "$result\n"
                puts $FH "Routes Found - $route_count after $route_counter iterations.\n"
                set route_counter 6
            }
        }
        if { $route_counter <= 5 } {
            set route_stat 1
            set msg "EEM Recovery Script - RIB Route check for $loop_ip of $node Failed, route not found, script will continue with the checks."
            puts $FH "Route Count = $route_count > no routes found"
            puts $FH "RIB Route Stat Counter = $route_stat > Route Not Present"
            puts $FH "$msg\n"
            action_syslog msg "EEM Recovery Script - RIB Route check for $loop_ip of $node Failed, route not found, script will continue with the checks."
        } else {
            set route_stat 0
            set msg "EEM Recovery Script - RIB Route check for $loop_ip of $node show route is PRESENT after $route_counter iterations of waiting, script will continue with the checks."
            puts $FH "Route Count = $route_count > routes found"
            puts $FH "RIB Route Stat Counter = $route_stat > Route PRESENT"
            puts $FH "$msg\n"
            action_syslog msg "EEM Recovery Script - RIB Route check for $loop_ip of $node successful, route found, script will continue with the checks."


        }      

    } elseif { $route_count == 1 } {
        puts $FH "$result\n\n"
        set route_stat 0
        set msg "EEM Recovery Script - RIB Route check for $loop_ip of $node show route is PRESENT (elseif condition), script will continue with the checks."
            puts $FH "Route Count = $route_count > routes found"
            puts $FH "RIB Route Stat Counter = $route_stat > Route PRESENT"
        puts $FH "$msg\n"
        action_syslog msg "EEM Recovery Script - RIB Route check for $loop_ip of $node show route is PRESENT, script will continue with the checks."
    } else {
        puts $FH "$result\n\n"
        set route_stat 0
        set msg "EEM Recovery Script - RIB Route check for $loop_ip of $node show route is PRESENT (else condition), script will continue with the checks."
            puts $FH "Route Count = $route_count > routes found"
            puts $FH "RIB Route Stat Counter = $route_stat > Route PRESENT"
        puts $FH "$msg\n"
        action_syslog msg "EEM Recovery Script - RIB Route check for $loop_ip of $node show route is PRESENT, script will continue with the checks."
    }

    #return $loop_ip
    return $route_stat
}

proc register_detection {} {
    global FH node 
    global errorInfo cli

    ################################################################################
    # Procedure call to Register the EEM Detection Script
    # Script name = vrr_recovery_script.tcl
    ################################################################################

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Register the EEM Detection Script \n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - register_detection procedure started------"

    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

    config_terminal
    
    if [catch {cli_exec $cli(fd) "event manager policy vrr_detection_script.tcl username eem-user"} result] {
        error $result $errorInfo
    }

    #if [catch {cli_exec $cli(fd) "event manager policy vrr_cleanup_script.tcl username eem-user"} result] {
    #    error $result $errorInfo
    #}
    
    if [catch {cli_exec $cli(fd) "commit"} result] {
        error $result $errorInfo
    }

    if [catch {cli_exec $cli(fd) "exit"} result] {
        error $result $errorInfo
    }
    
    if [catch {cli_exec $cli(fd) "show event manager policy registered"} result] {
        error $result $errorInfo
    } 
    puts $FH "$result\n"
    set detpolicy_exist [regexp -all {detection} $result]

    return $detpolicy_exist
}

proc remove_files {} {
    global FH node 

    ################################################################################
    # Procedure call to Remove Files created by EEM vRR Scripts
    # Script name = vrr_recovery_script.tcl
    ################################################################################

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Remove Files created by EEM vRR Scripts \n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - remove_files procedure started------"


    # Use flush command to flush buffered output to logfile
    flush $FH

    ###########################################
    # Attach to LC and run some show commands:
    ###########################################

    if [catch {cli_open} result] {
        error $result $errorInfo
    } else {
        array set cli $result
    }

    set cmd "run"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    # Use flush command to flush buffered output to logfile
    flush $FH

    set cmd "cd eem"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    set cmd "ls | grep active"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    set cmd "rm vrr-detection-active"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    set cmd "rm vrr-remediation-active"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    set cmd "rm vrr-recovery-active"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    puts $FH "After files have been removed!"

    set cmd "ls | grep active"
    puts $FH "Running Shell CMD: $cmd"
    if [catch {cli_write $cli(fd) $cmd} result] {
        error $result $errorInfo
    }
    if [catch {cli_read_pattern $cli(fd) "xr-vm_node0_RP0_CPU0"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"
    
    set files_exist [regexp -all {active} $result]

    if [catch {cli_exec $cli(fd) "exit"} result] {
        error $result $errorInfo
    } 

    return $files_exist
}

proc unregister_recovery {} {
    global FH node
    global errorInfo cli

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to unregister Recovery Policy \n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node - unregister_recovery procedure started------"


    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

    config_terminal
    
    if [catch {cli_exec $cli(fd) "no event manager policy vrr_recovery_script.tcl username eem-user"} result] {
        error $result $errorInfo
    }
    puts $FH "$result\n"

    flush $FH

    sleep 2

    if [catch {cli_exec $cli(fd) "commit"} result] {
        error $result $errorInfo
    }

}


proc runtime {} {
    global FH t0 node

    ################################################################################
    # TimeStamp to indicate toatl Script Runtime and close the log file.
    # runtime procedure is called at the end when script near completion.
    ################################################################################

    set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]

    puts $FH "\n*Timestamp = $date"
    puts $FH "\nScript Runtime = [expr {([clock clicks -millisec]-$t0)/1000.}] sec"
    puts $FH "====================================================================================================================================="

    #Close the log file and finish the script
    #close $FH

    # Send syslog message:
    action_syslog msg "------EEM policy vrr_recovery_script on node $node completed!!------"
}

proc send_email {node syslog_msg bodytext} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending Email Alert - EEM vRR Recovery Script for node $node to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "Route Reflector $node triggered vRR EEM Recovery Script"]
    set email [format "%s\n%s\n\n" "$email" "$syslog_msg\n"]
    set email [format "%s\n%s" "$email" "$bodytext"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
 
    puts $FH "\n****EMAIL ALERT SENT TO: $_email_to *****\n"
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
#set _output_log "${_output_log_vrrrem}_$stamp"
set _output_log "eem_vrr_recovery_$stamp"

set mping_stat 0
set load_stat 0
set commit_stat 0
set lping_stat 0

###############################################################
# Procedure (get_hostname) to get the router's hostname
###############################################################
set bknode [get_hostname]


###############################################################
# Open the output file (for write):
###############################################################

if [catch {open $_recovery_storage_location/$_output_log w} result] {
    error $result
}
set FH $result

puts $FH "====================================================================================================================================="
puts $FH "*Timestamp = $date"
puts $FH "Cisco vRRb $bknode Recovery Script"
puts $FH "=====================================================================================================================================\n"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message:
set syslog_msg $arr_einfo(msg)


###############################################################
# Get the Neighbor IP address from the triggering syslog_msg
###############################################################

set sysbgp_ip [extract_ip $syslog_msg]

#####################################################################################
# Extract data from the vrr-remediation-active file, quit if file does not exist
#####################################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nvRR Recovery Script initated on backup vRR $bknode, script will extract data from vrr-remediation-active file\n"

set bkp_ext "$_eem_storage_location/vrr-remediation-active"

# Sample vrr-remediation-active output
# $cat vrr-remediation-active 
# node RR251 config_file_location disk0:/eem/configs/RR251_bgp_cfg vRR_MGMT_IP 1.3.249.251 vRR_Loop_IP 12.122.249.251 vRR_BGP_IP 12.122.250.251

# If the $vrr-remediation-active file exists then extract the data for the recovery script
if [file exists $bkp_ext] {

    if [catch {open $bkp_ext r} result] {
        error $result   
    }

    set BFH [read $result]

    set idfail [extract_data $BFH]
    set node        [lindex $idfail 0]
    set configloc   [lindex $idfail 1]
    set mgmt_ip     [lindex $idfail 2]
    set loop_ip     [lindex $idfail 3]
    set bgp_ip      [lindex $idfail 4]

    puts $FH "SYSLOG MSG:\n$syslog_msg"
    puts $FH "Syslog MSG BGP IP: $sysbgp_ip\n"

    puts $FH "Backup vRR: $bknode\n"

    puts $FH "Active vRR Node: $node"
    puts $FH "Node Config File Location: $configloc"
    puts $FH "Node MGMT IP: $mgmt_ip"
    puts $FH "Node Loopback IP: $loop_ip"
    puts $FH "Node BGP Session IP: $bgp_ip\n"

    # Use flush command to flush buffered output to logfile
    flush $FH

    if { $sysbgp_ip == $bgp_ip } {

        puts $FH  "EEM policy vrr_recovery_script on backup node $bknode - extract_data procedure SUCCESSFUL\n"
        action_syslog msg "------EEM policy vrr_recovery_script on backup node $bknode - extract_data procedure SUCCESSFUL.------"

    } else {
        puts $FH "BGP Syslog Trigger IP $sysbgp_ip does not match Original Active RR's BGP IP $bgp_ip"
        puts $FH "BGP Syslog Trigger IP and vrr-remediation-active file BGP_IP do not match, recovery script will exit now\n" 

        # Use flush command to flush buffered output to logfile
        flush $FH

        action_syslog msg "------BGP Syslog Trigger IP and vrr-remediation-active file BGP_IP do not match, recovery script will exit------"
        
        exit
    }


# If the $vrr-remediation-active file does not exists then exit the recovery script since we do not have the required variables
} else {

    puts $FH "EEM policy vrr_recovery_script on backup node $bknode - extract_data procedure FAILED \n"
    puts $FH "Unable to find vrr-remediation-active file to extract data needed by the recovery script \n"
    puts $FH "EEM policy vrr_recovery_script will exit and send email alert" 

    action_syslog msg "------EEM policy vrr_recovery_script on backup node $bknode - extract_data procedure FAILED, file not found script will exit.------"


    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** vRR triggered EEM Recovery Script started on backup node $bknode but had to quit beacuse vrr-remediation-active file not found"

    if [catch {open $_recovery_storage_location/$_output_log r} result] {
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


# Sleep 5 seconds
sleep 5

########################################################################
# Check the Active Router's MGMT IP Address Reachability
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nPing Check between vRRb $bknode and the Old Active Router's $node MGMT IP address\n"

set mping_stat [ping_check $mgmt_ip]

if { $mping_stat == 0} {

    puts $FH "Active Router's MGMT Ping Stat Counter = $mping_stat > Reachable after ping_check\n"
    #set mping_stat 0
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - ping_check procedure for Old Active vRR's MGMT IP $mgmt_ip SUCCESSFUL------"

} else {
    puts $FH "Active Router's MGMT Ping Stat Counter = $mping_stat > Not Reachable after ping_check\n"
    #set mping_stat 1
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - ping_check procedure for Old Active vRR's MGMT IP $mgmt_ip FAILED------"

    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** vRR triggered EEM Recovery Script started on backup vRR $bknode but had to quit beacuse Ping to Old Active vRR's ($node) MGMT IP $mgmt_ip FAILED"

    if [catch {open $_recovery_storage_location/$_output_log r} result] {
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

puts $FH "ping_check procedure for Old Active Routers MGMT IP completed\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - ping_check procedure for Old Active vRR's MGMT IP completed------"



########################################################################
# Check if vrr-remediation-active file exists, and quit if it does
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nvRR-recovery-active file check on backup vRR $bknode \n"


set bkrec_ext "$_eem_storage_location/vrr-recovery-active"

# If the $run_flag file exists exit from script:
if [file exists $bkrec_ext] {

    if [catch {open $bkrec_ext r} result] {
        error $result   
    }

    set BFH [read $result]

    puts $FH "Backup file already exists for $BFH\n"
    puts $FH "Script was initiated for $node but will exit now since vrr-recovery-active file already exists\n"

    # Use flush command to flush buffered output to logfile
    flush $FH

    action_syslog msg "------EEM policy vrr_recovery_script initiated for $node but will exit now since vrr-recovery-active file already exists------"


    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** vRR $node triggered EEM Recovery Script on backup vRR $bknode, but will exit now since vrr-recovery-active file already exists"

    if [catch {open $_recovery_storage_location/$_output_log r} result] {
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

    # Since there is no vrr-recovery-active file, create one and insert the node name of the active RR. 
    # So future remediations scripts will know this backup router is already in progress to become an active router.

    if [catch {open $bkrec_ext w} result] {
        error $result
    }

    set CBFH $result
    puts $CBFH "node $node config_file_location $configloc vRR_MGMT_IP $mgmt_ip vRR_Loop_IP $loop_ip vRR_BGP_IP $bgp_ip"
    close $CBFH

    # Sample vrr-recovery-active output
    # $cat vrr-recovery-active 
    # node RR251 config_file_location disk0:/eem/configs/RR251_bgp_cfg vRR_MGMT_IP 9.3.249.251 vRR_Loop_IP 12.122.249.251 vRR_BGP_IP 12.122.250.251

    puts $FH "vrr_recovery_script Backup file (vrr-recovery-active) created for node $node \n"

    action_syslog msg "------EEM policy vrr_recovery_script Backup file (vrr-recovery-active) created for $node on backup node $bknode------"

}

#########################################################################################################
# Unregister the Remediation Script before start the load and commit to move vRRb to backup router role
#########################################################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nUnregister the remediation script on backup vRR $bknode\n"

set rempolicy_exist [unregister_remediation]
puts $FH "Remediation Policy Exist value = $rempolicy_exist"


if { $rempolicy_exist == 1} {
    set rempolicy_stat 1
    puts $FH "Remediation policy unregisteration Stat = $rempolicy_stat  > unregistration unsuccessful"
    puts $FH "Remediation Script policy unregistration UNSUCCESSFUL, manually remove prior EEM Script!\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - unregister_remediation procedure completed - Failed------"
} else {
    set rempolicy_stat 0
    puts $FH "Remediation policy unregisteration Stat = $rempolicy_stat  > unregistration successful"
    puts $FH "Remediation Script policy unregistration SUCCESSFUL, script will continue with the checks\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - unregister_remediation procedure completed - Successful------"
}

# Use flush command to flush buffered output to logfile
flush $FH

########################################################################
# Calling send_email procedure to send alert to OPs team
########################################################################
set email_subject "** vRR $node triggered EEM Recovery Script on backup vRR $bknode - vRRb is going to load and commit the backup router config"

set bodytext {
    vRR EEM Recovery Script is has detected the old Active vRR to be up and active. 
    
    So this router will go back to being the backup vRR - vRRb role.

    Check the last captures inside the log file generated to identify the failure condition during Registeration.
    Log file is located on the vRRb router - disk0:/eem/vRR_recovery_logs/
}

# Call on the send_email proc to generate an email message
send_email $node $syslog_msg $bodytext

# Sleep 5 seconds
sleep 5


########################################################################
# LOAD AND COMMIT OPERATION LOGIC
#
# Load the recovery_cleanup_cfg file, if the load is successfulful then commit else quit and send alert.
#
# Load the configuration on vRRb to become the Backup Router
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nLoad the vRR Config file located in disk0:/eem/configs/recovery_cleanup_cfg so vRRb can become the new Active Router\n"

# recoveryfile - defined at the top of the script

set load_stat [load_config $recoveryfile]


if { $load_stat == 1} {
    puts $FH "load_stat = $load_stat  > Load operation unsuccessful\n"
    puts $FH "Load UNSUCCESSFUL for file $recoveryfile, script will exit and MANUAL INTERVENTION NEEDED to load and commit the configs required for node $node!!"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - load_config procedure FAILED!------"
    
    
    ########################################################################
    # Shutting down vRRbs uplink interfaces since recovery script failed after detecting Active RR coming up
    ########################################################################
    puts $FH "Shutting down vRRb $bknode uplink interfaces since recovery script failed after detecting Active RR coming up\n"
    set intf_down [shut_uplink]

    if { $intf_down >= 2} {
        puts $FH "intf_down = $intf_down  > Uplink Interfaces Shutdown on vRRb, MANUAL INTERVENTION NEEDED\n"
    } else {
        puts $FH "intf_down = $intf_down  > Uplink Interfaces NOT Shutdown on vRRb, MANUAL INTERVENTION NEEDED\n"
    }

    puts $FH "EEM policy vrr_recovery_script on backup vRR $bknode FAILED to revert node to backup role, script will exit\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - shut_uplink procedure completed------"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode FAILED to revert node to backup role, script will exit!------"

    # Use flush command to flush buffered output to logfile
    flush $FH

    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** Route Reflector $node triggered vRR EEM Recovery Script on backup vRR $bknode but config load operation FAILED, manual intervention needed!!"

    if [catch {open $_recovery_storage_location/$_output_log r} result] {
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
    puts $FH "load_stat = $load_stat  > Load operation SUCCESSFUL\n"
    puts $FH "Load SUCCESSFUL for $recoveryfile, script will continue with the checks\n"
    action_syslog msg "------EEM policy vrr_recovery_script for node $node on backup vRR $bknode - load_config procedure completed------"

    # Use flush command to flush buffered output to logfile
    flush $FH

    ########################################################################
    # Commit the configuration on vRRb to become Active Router
    ########################################################################
    puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Ready to commit the config and become the Backup vRR on $bknode \n"

    set commit_stat [commit_config]

    if { $commit_stat == 1} {

        puts $FH "Commit_stat = $commit_stat  > Commit operation unsuccessful\n"
        puts $FH "Commit UNSUCCESSFUL, script will exit and MANUAL INTERVENTION NEEDED to load and commit the configs required for node $node!!"
        action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode  - commit_config procedure FAILED!------"

        ########################################################################
        # Shutting down vRRbs uplink interfaces since recovery script failed after detecting Active RR coming up
        ########################################################################
        puts $FH "Shutting down vRRbs $bknode uplink interfaces since recovery script failed after detecting Active RR coming up\n"
        set intf_down [shut_uplink]

        if { $intf_down >= 2} {
            puts $FH "intf_down = $intf_down  > Uplink Interfaces Shutdown on vRRb, MANUAL INTERVENTION NEEDED\n"
        } else {
            puts $FH "intf_down = $intf_down  > Uplink Interfaces NOT Shutdown on vRRb, MANUAL INTERVENTION NEEDED\n"
        }

        puts $FH "EEM policy vrr_recovery_script on backup vRR $bknode FAILED to revert node to backup role, script will exit\n"
        action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode  - shut_uplink procedure completed------"
        action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode  FAILED to revert node to backup role, script will exit!------"

        # Use flush command to flush buffered output to logfile
        flush $FH

        ########################################################################
        # Calling send_email procedure to send alert to OPs team
        ########################################################################
        set email_subject "** Route Reflector $node triggered vRR EEM Recovery Script on backup vRR $bknode but config commit operation FAILED, manual intervention needed!!"

        if [catch {open $_recovery_storage_location/$_output_log r} result] {
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

        puts $FH "commit_stat = $commit_stat  > Commit operation SUCCESSFUL\n"
        puts $FH "Commit SUCCESSFUL, script will continue with the checks\n"
        action_syslog msg "------EEM policy vrr_recovery_script for node $node on backup vRR $bknode  - commit_config procedure completed------"

        # Use flush command to flush buffered output to logfile
        flush $FH

    }

}

########################################################################
# Starting Conditional Checks
########################################################################

# Sleep 30 seconds before starting the checks
sleep $sleeptimer

########################################################################
# Check the RIB Route Table for the Active Router's Loopback0 IP Address
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nRIB Route Check for the Active Router's Loopback0 address on backup vRR $bknode \n"

set route_stat [route_check $loop_ip]

if { $route_stat == 0} {

    puts $FH "RIB Route Stat Counter = $route_stat > check for Old active Router's Loopback0 SUCCESSFUL\n"
    #set lping_stat 0
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - route_check procedure for Old Active vRR's Loopback0 IP $loop_ip SUCCESSFUL------"

} else {
    puts $FH "RIB Route Stat Counter = $route_stat > check for Old active Router's Loopback0 FAILED\n"
    #set lping_stat 1
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - route_check procedure for Old Active vRR's Loopback0 IP $loop_ip FAILED------"

}

puts $FH "pingroute_check_check procedure for Old Active Routers Loopback IP $loop_ip completed\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - route_check procedure for Old Active vRR's Loopback0 IP completed------"

########################################################################
# Check the Active Router's Loopback IP Address Reachability
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nPing Check between vRRb and the Old Active Router's Loopback IP address\n"

set lping_stat [ping_check $loop_ip]

if { $lping_stat == 0} {

    puts $FH "Active Router's Loopback0 Ping Stat Counter = $lping_stat > Reachable after ping_check\n"
    #set lping_stat 0
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode  - ping_check procedure for Old Active vRR's Loopback0 IP $loop_ip SUCCESSFUL------"

} else {
    puts $FH "Active Router's Loopback0 Ping Stat Counter = $lping_stat > Not Reachable after ping_check\n"
    #set lping_stat 1
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode  - ping_check procedure for Old Active vRR's Loopback0 IP $loop_ip FAILED------"

}

puts $FH "ping_check procedure for Old Active Routers Loopback0 IP $loop_ip completed\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - ping_check procedure for Old Active vRR's Loopback0 IP completed------"



#########################################################################################################
# Remove the files created by the EEM Scripts { vrr-detection-active, vrr-remediation-active, and vrr-recovery-active}
#########################################################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nRemove the Files created by the EEM Scripts on backup vRR $bknode \n"

set files_exist [remove_files]
puts $FH "Files Exist value = $files_exist"

if { $files_exist > 3} {
    set file_stat 1
    puts $FH "Recovery policy File Removal Stat = $file_stat  > File Removal unsuccessful"
    puts $FH "Files to remove - vrr-detection-active, vrr-remediation-active, and vrr-recovery-active!\n"
    puts $FH "Recovery Script policy Removal UNSUCCESSFUL, MANUAL INTERVENTION NEEDED to remove the files\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - remove_files procedure completed - Failed, MANUAL INTERVENTION NEEDED------"
} else {
    set file_stat 0
    puts $FH "Recovery policy File Removal Stat = $file_stat  > File Removal successful"
    puts $FH "Files Removed - vrr-detection-active, vrr-remediation-active, and vrr-recovery-active!\n"
    puts $FH "Recovery Script policy Removal SUCCESSFUL, script will continue with the checks\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - remove_files procedure completed - Successful------"
}

#########################################################################################################
# Register the Detection Script
#########################################################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nRegister the Detection script\n"

set detpolicy_exist [register_detection]
puts $FH "Detection Policy Exist value = $detpolicy_exist"

if { $detpolicy_exist == 1} {
    set detpolicy_stat 0
    puts $FH "Detection policy registeration Stat = $detpolicy_stat  > registration successful"
    puts $FH "Detection Script policy registration SUCCESSFUL, script will continue with the checks\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - register_detection procedure completed - Successful------"
} else {
    set detpolicy_stat 1
    puts $FH "Detection policy registeration Stat = $detpolicy_exist  > registration unsuccessful"
    puts $FH "Detection Script policy registration UNSUCCESSFUL, manually register the EEM Detection Script!\n"
    action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - register_detection procedure completed - Failed------"
}

# Use flush command to flush buffered output to logfile
flush $FH

##################################################################################
# Final Checks
##################################################################################

puts $FH "====================================================================================================================================="
puts $FH "FINAL RECOVERY SCRIPT SUMMARY ON BACKUP vRR $bknode \n"
puts $FH "Stat value of 0 indicate a successful completion of that procedure, and value of 1 indicate a failure in that procedure execution.\n"

puts $FH "Active Router's MGMT Ping Stat Counter = $mping_stat"
puts $FH "Remediation policy unregisteration Stat = $rempolicy_stat"
puts $FH "Recovery File Load Stat = $load_stat"
puts $FH "Recovery File Commit Stat = $commit_stat"
puts $FH "RIB Route Stat Counter = $route_stat" 
puts $FH "Active Router's Loopback Ping Stat Counter = $lping_stat"
puts $FH "Recovery policy File Removal Stat = $file_stat" 
puts $FH "Detection policy registeration Stat = $detpolicy_stat"


puts $FH "EEM Recovery Script will send email summary and then unregister itself, leaving only the detection script registered."

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_remediation_script for node $node - Final Check completed------"



########################################################################
# Calling send_email procedure to send alert to OPs team
########################################################################
set email_subject "** RR $node triggered EEM Recovery Script on backup vRR $bknode - successful - vRRb is a backup router again"

if [catch {open $_recovery_storage_location/$_output_log r} result] {
    error $result   
}
set bodytext [read $result]

# Call on the send_email proc to generate an email message
send_email $node $syslog_msg $bodytext

######################################################################################
# Calling runtime procedure to calculate total script runtime and close the log file.
######################################################################################
runtime

# Sleep 5 seconds for file write to catch up before unregistering the script
sleep 5

#########################################################################################################
# Unregister the Recovery Script 
#########################################################################################################
puts $FH "\nUnregister the Recovery script\n"

action_syslog msg "------EEM policy vrr_recovery_script on backup vRR $bknode - Recovery script will unregister itself\n"

# Procedure to unregister the recovery script
unregister_recovery

#Close the log file and finish the script
close $FH

exit