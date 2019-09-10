::cisco::eem::event_register_syslog pattern  "HA-HA_EEM-6-ACTION_SYSLOG_LOG_INFO.*EEM policy vrr_remediation_script.*node.*config_file_location.*vRR_MGMT_IP.*vRR_Loop_IP.*start.*" maxrun 750

######################################################################################################################################################
#
#  Revision No	      : v8
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

action_syslog msg "EEM policy vrr_remediation_script.tcl has started"

#################################################################################################
#
# USER MUST DEFINE THE FOLLOWING VARIABLE!!
# set cbb_ip [ list cbbloopbackip1 cbbloopbackip2 ...]
#
# Example:
# set cbb_ip [list 12.122.0.7 12.122.0.4]
# set sleeptimer 30

set cbb_ip [list 12.122.0.7 12.122.0.4]
set sleeptimer 30

#################################################################################################

# Verify the environment vars:
if {![info exists _remediation_storage_location]} {
  set result "EEM policy error: environment var _remediation_storage_location not set"
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

proc unregister_detection {} {
    global FH node detpolicy_exist
    global errorInfo cli
    
    ################################################################################
    # Procedure call to unregister the previous EEM SCript
    ################################################################################

    puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Unregister Detection Policy \n"
    action_syslog msg "------EEM policy vrr_remediation_script for node $node - unregister_detection procedure started------"
    
    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

    config_terminal

    if [catch {cli_exec $cli(fd) "no event manager policy vrr_detection_script.tcl username eem-user"} result] {
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
    set detpolicy_exist [regexp -all {detection} $result]

    return $detpolicy_exist
}

proc load_config {fileloc} {
    global FH node load_stat 
    global _remediation_storage_location _output_log
    global cli 
    
    ################################################################################
    # Procedure call to load and commit the configuration needed for this backup router to become the Active Router.
    ################################################################################

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Load the configuration on vRRb\n"
    action_syslog msg "------EEM policy vrr_remediation_script for node $node on backup vRR - load_commit_file procedure started------"
    
    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

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
            puts $FH "vrr_remediation_script load_config procedure FAILED to load $loadfile \n"
            puts $FH "------------------------------------------------------------------\n" 
            action_syslog msg "vrr_remediation_script load_config procedure FAILED to load $loadfile \n"   
        } else {
            puts $FH "vrr_remediation_script load_config procedure SUCCESSFUL to load $loadfile \n"
            puts $FH "------------------------------------------------------------------\n"
            action_syslog msg "vrr_remediation_script load_config procedure SUCCESSFUL to load $loadfile \n"
        }
    }

    # Check the load operation result for an errors. If load_file matches on No or file text it indicates a problem condition.
    # Load_fail value of 1 or greater is considered a failure of load operation
    # Load_fail value should be 0 if load operation is successful

    if {$checkval >= 1} {

        # Load operation failed, script will exit and send an email alert.
        puts $FH "vrr_remediation_script for node $node - load_config procedure failed at load operation.\n"
        puts $FH "Load operation Failed, Manunal intervention required to load the config files. "

        set load_stat 1

        action_syslog msg "EEM policy vrr_remediation_script - Config load operation FAILED, when loading config for prior active node $node"


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

        puts $FH "vrr_remediation_script for node $node - load_config procedure load operation successful, moving on to commit action.\n"

        set load_stat 0
        
        action_syslog msg "EEM policy vrr_remediation_script - Config load operation completed SUCCESSFULLY with config for prior active node $node"

        # Use flush command to flush buffered output to logfile
        flush $FH

    }

    return $load_stat
}

proc commit_config {} {
    global FH node 
    global cli errInfo 

    #puts $FH "--------------------------------------------------------------------------"
    puts $FH "Running commit_config procedure"
    
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
        puts $FH "vrr_remediation_script for node $node - commit_config procedure failed at commit config operation.\n"
        puts $FH "Commit operation Failed, Manunal intervention required to commit the config in file \n"

        set commit_stat 1

        action_syslog msg "EEM policy vrr_remediation_script - Config commit operation FAILED, to commit with config for prior active node $node"

        # Use flush command to flush buffered output to logfile
        flush $FH

    } else {
        
        # Commit_fail value of 0 indicates no problems with commit operation, script can continue on with the checks.

        puts $FH "vrr_remediation_script for node $node - commit_config procedure commit operation SUCCESSFUL, script will continue the checks.\n"

        set commit_stat 0

        action_syslog msg "EEM policy vrr_remediation_script - Config commit operation completed SUCCESSFULLY, with config for prior active node $node"

        if [catch {cli_exec $cli(fd) "end"} result] {
        error $result $errorInfo
        }

        # Use flush command to flush buffered output to logfile
        flush $FH

    }

    return $commit_stat
}

proc ping_check {cbb_ip loop_ip} {
    global  FH node lping_stat sleeptimer 

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running ping_check procedure"
    action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - ping_check procedure started------"

    ################################################################################
    # Check the Active Router's Loopback0 IP Address Reachability
    ################################################################################

    set checkval 0

    foreach cbloop_ip $cbb_ip {

        set lping_counter 0

        set cmd "ping $cbloop_ip source $loop_ip"
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
            puts $FH "$result\n\n"
            #set lping_stat 0
            incr checkval
            set msg "EEM Remediation Script - PING to CBB Loopback0 $cbloop_ip successful."
            puts $FH "Loopback Ping Stat Counter = $lping_stat > Reachable"
            puts $FH "$msg\n"
            puts $FH "------------------------------------------------------------------\n"
            action_syslog msg "EEM Remediation Script - CBB Loopback Ping check for $cbloop_ip SUCCESSFUL, script will continue with the checks."

            # Use flush command to flush buffered output to logfile
            flush $FH
            
        } else {
            puts $FH "$result\n\n"
            set msg "EEM Remediation Script - PING to CBB Loopback0 $cbloop_ip Failed, script will enter loop condition"
            puts $FH "$msg\n"
            puts $FH "------------------------------------------------------------------\n"
            action_syslog msg "EEM Remediation Script - CBB Loopback Ping check for $cbloop_ip FAILED, script will wait and check again."

            while {$lping_counter <= 4} {
                puts $FH "Waiting 30 Seconds before ping retry"

                # Sleep time before performing ping check again
                sleep $sleeptimer

                set cmd "ping $cbloop_ip source $loop_ip"
                set result [getcmd $cmd]

                if { [regexp {!} $result]} {
                    puts $FH "$result\n"
                    set lping_counter 6
                    incr checkval
                    #set lping_stat 0
                    puts $FH "Loopback Ping Stat Counter = $lping_stat > Reachable"
                    puts $FH "EEM Remediation Script - PING to CBB Loopback0 $cbloop_ip SUCCESSFUL. Lping_counter = $lping_counter\n"
                    #action_syslog msg "EEM Remediation Script - Loopback Ping check for $loop_ip FAILED, script will wait and check again."


                    # Use flush command to flush buffered output to logfile
                    flush $FH
                    
                } else {
                    puts $FH "$result\n"
                    puts $FH "EEM Remediation Script - PING to CBB Loopback0 $cbloop_ip UNSUCCESSFUL. Lping_counter = $lping_counter\n"
                    incr lping_counter

                    # Use flush command to flush buffered output to logfile
                    flush $FH
                }
            }
 
        }

    }

    if { $checkval > 0 } {
        set lping_stat 0
        set msg "EEM Remediation Script - CBB Loopback Ping check SUCCESSFUL, script will continue with the checks.\n"
        puts $FH "Lping Stat Counter = $lping_stat > Ping Successful\n"
        puts $FH "$msg\n"
        #action_syslog msg "EEM Remediation Script - Loopback Ping check for $loop_ip SUCCESSFUL, script will continue with the checks."

        # Use flush command to flush buffered output to logfile
        flush $FH

    } else {
        set lping_stat 1
        set msg "EEM Remediation Script - CBB Loopback Ping check FAILED, script will continue with the checks.\n"
        puts $FH "Lping Stat Counter = $lping_stat > Ping Failed\n"
        puts $FH "$msg\n"
        #action_syslog msg "EEM Remediation Script - Loopback Ping check for $loop_ip FAILED, script will continue with the checks."

        # Use flush command to flush buffered output to logfile
        flush $FH
    }  

    #Return the lping_stat variable for final counter check at the end of the script
    return $lping_stat
}

proc bgp_check {} {
    global FH node bgp_stat sleeptimer

    #puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Running bgp_check procedure"
    action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure started------"

    set total_sessions 0
    set down_sessions 0
    set down_percentage 0

    #####################################################################################################
    # Check the BGP Sessions to ensure at least 50% of the session have come up on the now active router
    #####################################################################################################

    # Collect the following command to get the full count of sessions configured for vpnv4 af on this vRR

    set cmd "show bgp vpnv4 uni sum | ex Admin | utility egrep ^\[0-9]+.\[0-9]+.\[0-9]+.\[0-9]+ | utility wc"
    
    set full_result [getcmd $cmd]

    puts $FH "CLI OPEN successful for : $cmd\n"

    # Sample of CLI Output
    # RP/0/RP0/CPU0:RR253-VRR(config)#do show bgp ipv4 unicast summary | utility egrep ^\[0-9]+.\[0-9]+.\[0-9]+.\[0-9]+ | util wc
    # Tue Aug 13 16:41:07.386 UTC
    #   4      40     306

    puts $FH "$full_result\n"

    flush $FH
    
    set total_sessions [regexp -inline {\s\s\s\s\d+} $full_result]

    if { $total_sessions > 0} {

        puts $FH "Total number of vpnv4 sessions present = $total_sessions\n"
        puts $FH "------------------------------------------------------------------\n"

        action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure total number of vpnv4 sessions $total_sessions ------"


    } else {
        
        puts $FH "Total number of vpnv4 sessions = $total_sessions -> Sessions not found\n"
        puts $FH "------------------------------------------------------------------\n"

        action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure total vpnv4 sessions $total_sessions not found ------"

        set $total_sessions 0

    }

    # Collect the following command to get the full count of sessions configured for vpnv4 af on this vRR

    set cmd "show bgp vpnv4 unicast summary | ex Admin | utility egrep ^\[0-9]+.\[0-9]+.\[0-9]+.\[0-9]+ | utility egrep Active | utility wc"
    
    set result [getcmd $cmd]

    puts $FH "CLI OPEN successful for : $cmd\n"

    puts $FH "$result\n"

    flush $FH

    set act_result [regexp -inline {\s\s\s\s\d+} $result]

    puts $FH "Total number of vpnv4 sessions in Active state = $act_result\n"
    puts $FH "------------------------------------------------------------------\n"

    action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure total number of vpnv4 sessions Active $act_result ------"


    # Collect the following command to get the full count of sessions configured for vpnv4 af on this vRR

    set cmd "show bgp vpnv4 unicast summary | ex Admin | utility egrep ^\[0-9]+.\[0-9]+.\[0-9]+.\[0-9]+ | utility egrep Idle | utility wc"
    
    set result [getcmd $cmd]

    puts $FH "CLI OPEN successful for : $cmd\n"

    puts $FH "$result\n"

    flush $FH

    set idle_result [regexp -inline {\s\s\s\s\d+} $result]

    puts $FH "Total number of vpnv4 sessions in Idle state =  $idle_result\n"
    puts $FH "------------------------------------------------------------------\n"


    action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure total number of vpnv4 sessions Idle $idle_result ------"

    set down_sessions [ expr $act_result + $idle_result]

    if { $down_sessions > 0} {

        puts $FH "Total number of Active and Idle vpnv4 sessions = $down_sessions\n"
        action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure found $down_sessions down vpnv4 sessions ------"

    } else {
        
        puts $FH "Total number of Active and Idle vpnv4 sessions = $down_sessions\n"
        action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure found $down_sessions down vpnv4 sessions ------"
    }

    if { $total_sessions == 0  } {

        set total_sessions 1

        set down_percentage [ expr double($down_sessions) / double($total_sessions)]

        puts $FH "Down_percentage = $down_percentage"
        puts $FH "Error - Number of Total Session was equal to 0, cant divide by 0 so set value to 1."
        puts $FH "EEM Remediation Script - BGP check FAILED, but recommend to MANUALLY check the BGP sessions!\n"

        action_syslog msg "------EEM policy vrr_syslog_remediation script for backup vRR - bgp_check procedure down percentage for vpnv4 sessions $down_percentage not accurate, manually check the count------"        

        set bgp_stat 1

    } else {

        set down_percentage [ expr double($down_sessions) / double($total_sessions)]

        if { $down_percentage > 0.5 } {

            set bgp_counter 0
            
            puts $FH "Down_percentage = $down_percentage"
            set msg "EEM Remediation Script - BGP Session Down Percentage > 0.5, script will enter loop condition"
            puts $FH "$msg\n"
            action_syslog msg "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage > 0.5, script will wait and check again"

            while {$bgp_counter <= 4} {
                puts $FH "---------------------Loop $bgp_counter------------------\n"
                puts $FH "Waiting 30 Seconds before BGP Down Session collection retry"

                # Sleep time before performing ping check again
                sleep $sleeptimer

                # Collect the following command to get the full count of sessions configured for vpnv4 af on this vRR

                set cmd "show bgp vpnv4 unicast summary | ex Admin | utility egrep ^\[0-9]+.\[0-9]+.\[0-9]+.\[0-9]+ | utility egrep Active | utility wc"
                set result [getcmd $cmd]

                puts $FH "CLI OPEN successful for : $cmd\n"
                puts $FH "$result\n"

                flush $FH
                set act_result [regexp -inline {\s\s\s\s\d+} $result]
                puts $FH "Total number of vpnv4 sessions in Active state = $act_result\n"
                puts $FH "---------------------------------------\n"

                # Collect the following command to get the full count of sessions configured for vpnv4 af on this vRR

                set cmd "show bgp vpnv4 unicast summary | ex Admin | utility egrep ^\[0-9]+.\[0-9]+.\[0-9]+.\[0-9]+ | utility egrep Idle | utility wc"
                set result [getcmd $cmd]

                puts $FH "CLI OPEN successful for : $cmd\n"
                puts $FH "$result\n"

                flush $FH
                set idle_result [regexp -inline {\s\s\s\s\d+} $result]
                puts $FH "Total number of vpnv4 sessions in Idle state =  $idle_result\n"
                puts $FH "---------------------------------------\n"

                set down_sessions [ expr $act_result + $idle_result]
                
                set down_percentage [ expr double($down_sessions) / double($total_sessions)]

                if { $down_percentage > 0.5 } {
                    
                    puts $FH "Down_percentage = $down_percentage"
                    puts $FH "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage > 0.5, script will wait and check again." 
                    puts $FH "BGP_counter = $bgp_counter\n"
                    action_syslog msg "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage > 0.5, loop $bgp_counter, script will wait and check again."

                    incr bgp_counter

                    
                    # Use flush command to flush buffered output to logfile
                    flush $FH

                } else {
                    
                    puts $FH "Down_percentage = $down_percentage"
                    puts $FH "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage > 0.5, script will continue with the checks." 
                    puts $FH "BGP_counter = $bgp_counter\n"
                    action_syslog msg "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage < 0.5, script will contine with the checks."

                    set bgp_counter 6
                    
                    # Use flush command to flush buffered output to logfile
                    flush $FH
                }

            }

            if { $bgp_counter <= 5 } {
                set bgp_stat 1
                # puts $FH "EEM Remediation Script - PING to Loopback0 $loop_ip UNSUCCESSFUL. Lping_counter = $lping_counter\n"

            } else {
                set bgp_stat 0
                # puts $FH "EEM Remediation Script - PING to Loopback0 $loop_ip SUCCESSFUL. Lping_counter = $lping_counter\n"
            }  
 

        } else {

            puts $FH "Down_percentage = $down_percentage"
            puts $FH "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage < 0.5, script will continue with the checks.\n" 
            action_syslog msg "EEM Remediation Script - BGP VPNv4 Session check down percentage $down_percentage < 0.5, script will contine with the checks."

            set bgp_stat 0
        }
        
    }
    
    #Return the bgp_stat variable for final counter check at the end of the script
    return $bgp_stat
    
}

proc register_recovery {} {
    global FH node recpolicy_exist
    global errorInfo cli

    
    ################################################################################
    # Procedure call to Register the EEM Recovery Script
    # Script name = vrr_recovery_script.tcl
    ################################################################################

    puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Starting Procedure to Register the EEM Recovery Script \n"
    action_syslog msg "------EEM policy vrr_remediation_script for node $node - register_recovery procedure started------"

    #if [catch {cli_open} result] {
    #    error $result $errorInfo
    #} else {
    #    array set cli $result
    #}

    #if [catch {cli_exec $cli(fd) "configure terminal"} result] {
    #    error $result $errorInfo
    #}

    config_terminal
    
    if [catch {cli_exec $cli(fd) "event manager policy vrr_recovery_script.tcl username eem-user"} result] {
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
    set recpolicy_exist [regexp -all {recovery} $result]

    return $recpolicy_exist
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

    close $FH

    # Send syslog message:
    action_syslog msg "------EEM policy vrr_remediation_script for node $node completed!!------"
}

proc send_email {node syslog_msg bodytext} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending Email Alert - EEM vRR Remediation Script for node $node to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "Route Reflector $node triggered vRR EEM Remediation Script"]
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
set _output_log "eem_vrr_remediation_$stamp"

set detpolicy_exist 0
set load_commit_stat 0
set lping_stat 0
set bgp_stat 0
set recpolicy_exist 0

###############################################################
# Procedure (get_hostname) to get the router's hostname
###############################################################
set bknode [get_hostname]

###############################################################
# Open the output file (for write):
###############################################################

if [catch {open $_remediation_storage_location/$_output_log w} result] {
    error $result
}
set FH $result

puts $FH "====================================================================================================================================="
puts $FH "*Timestamp = $date"
puts $FH "Cisco vRRb $bknode Remediation Script"
puts $FH "=====================================================================================================================================\n"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message:
set syslog_msg $arr_einfo(msg)

###############################################################
# Procedure (extract_data) to get the Neighbor IP address from the triggering syslog_msg
###############################################################

set idfail [extract_data $syslog_msg]
set node        [lindex $idfail 0]
set configloc   [lindex $idfail 1]
set mgmt_ip     [lindex $idfail 2]
set loop_ip     [lindex $idfail 3]
set bgp_ip      [lindex $idfail 4]

puts $FH "SYSLOG MSG:\n$syslog_msg\n"
puts $FH "Backup vRR: $bknode\n"
puts $FH "Active vRR Node: $node"
puts $FH "Node Config File Location: $configloc"
puts $FH "Node MGMT IP: $mgmt_ip"
puts $FH "Node Loopback IP: $loop_ip"
puts $FH "Node BGP Session IP: $bgp_ip"

########################################################################
# Check if vrr-remediation-active file exists, and quit if it does
########################################################################
set bkp_ext "$_eem_storage_location/vrr-remediation-active"

# If the $run_flag file exists exit from script:
if [file exists $bkp_ext] {

    if [catch {open $bkp_ext r} result] {
        error $result   
    }

    set BFH [read $result]

    puts $FH "Backup file already exists for $BFH\n"
    puts $FH "Script was initiated for Active vRR $node on backup vRR $bknode but will exit now since vrr-remediation-active file already exists\n"

    # Use flush command to flush buffered output to logfile
    flush $FH

    action_syslog msg "------EEM policy vrr_remediation_script initiated for Active vRR $node on backup vRR $bknode but will exit now since vrr-remediation-active file already exists.------"


    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** RR $node triggered EEM Remediation Script on backup vRR $bknode but will exit now since vrr-remediation-active file already exists"

    if [catch {open $_remediation_storage_location/$_output_log r} result] {
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

    # Since there is no vrr-remediation-active file, create one and insert the node name of the active RR. 
    # So future remediations scripts will know this backup router is already in progress to become an active router.

    if [catch {open $bkp_ext w} result] {
        error $result
    }

    set CBFH $result
    puts $CBFH "node $node config_file_location $configloc vRR_MGMT_IP $mgmt_ip vRR_Loop_IP $loop_ip vRR_BGP_IP $bgp_ip"
    close $CBFH

    puts $FH "vrr_remediation_script Backup file (vrr-remediation-active) created for node $node \n"
}


########################################################################
# Starting Conditional Checks
########################################################################

# Sleep 5 seconds before starting the checks
sleep 5

########################################################################
# Unregister the Detection Script first before starting Remediation Checks on vRRb
########################################################################

set detpolicy_exist [unregister_detection]

if { $detpolicy_exist == 1} {
    puts $FH "Detection policy unregisteration Stat = $detpolicy_exist  > unregistration unsuccessful"
    puts $FH "Detection Script policy unregistration UNSUCCESSFUL, manually remove prior EEM Script!\n"
    action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - unregister_detection procedure completed------"
} else {
    puts $FH "Detection policy unregisteration Stat = $detpolicy_exist  > unregistration successful"
    puts $FH "Detection Script policy unregistration SUCCESSFUL, script will continue with the checks\n"
    action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - unregister_detection procedure completed------"
}

# Use flush command to flush buffered output to logfile
flush $FH

########################################################################
# LOAD AND COMMIT OPERATION LOGIC
#
# First load the remove_detection_cfg file, it load is successfulful then commit else quit and send alert.
# If commit was successful, then load the RR config file, if load is successful then commit else quit and send alert.
# If either commit fails, then the script will quit. Meaning if the first commit failed then script will not load and commit the second file.
#
# Load the configuration on vRRb to become Active Router
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nLoad the RR Config file located in disk0:/eem/configs/remove_detection_cfg so vRRb $bknode can become the new Active Router\n"

#set temploc "disk0:/eem/configs/remove_detection_cfg"
set loadfiles "$configloc"

set load_stat [load_config $loadfiles]


if { $load_stat == 1} {
    puts $FH "load_stat = $load_stat  > Load operation unsuccessful\n"
    puts $FH "Load UNSUCCESSFUL for file $configloc, script will exit and MANUAL INTERVENTION NEEDED to load and commit the configs required for node $node!!"
    action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - load_config procedure FAILED and script has exitted!------"

    # Use flush command to flush buffered output to logfile
    flush $FH

    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** Route Reflector $node triggered vRR EEM Remediation Script on backup vRR $bknode but load operation FAILED, manual intervention needed!!"

    if [catch {open $_remediation_storage_location/$_output_log r} result] {
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
    puts $FH "Load SUCCESSFUL for $configloc, script will continue with the checks\n"
    action_syslog msg "------EEM policy vrr_remediation_script for node $node on backup vRR $bknode - load_config procedure completed------"

    # Use flush command to flush buffered output to logfile
    flush $FH

    ########################################################################
    # Commit the configuration on vRRb to become Active Router
    ########################################################################
    puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
    puts $FH "Ready to commit the config and become the Active vRR for node $node on backup vRR $bknode \n"

    set commit_stat [commit_config]

    if { $commit_stat == 1} {

        puts $FH "Commit_stat = $commit_stat  > Commit operation unsuccessful\n"
        puts $FH "Commit UNSUCCESSFUL, script will exit and MANUAL INTERVENTION NEEDED to load and commit the configs required for node $node!!"
        action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - commit_config procedure FAILED and script has exitted!------"

        # Use flush command to flush buffered output to logfile
        flush $FH

        ########################################################################
        # Calling send_email procedure to send alert to OPs team
        ########################################################################
        set email_subject "** Route Reflector $node triggered vRR EEM Remediation Script on backup vRR $bknode but load operation FAILED, manual intervention needed!!"

        if [catch {open $_remediation_storage_location/$_output_log r} result] {
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
        action_syslog msg "------EEM policy vrr_remediation_script for node $node on backup vRR $bknode - commit_config procedure completed------"

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
# Check the Active Router's Loopback0 IP Address Reachability
########################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nPing Check between the new Active vRRb $bknode and CBB Core Routers to ensure reachability\n"

set lping_stat [ping_check $cbb_ip $loop_ip]

puts $FH "Post ping_stat = $lping_stat \n"
puts $FH "ping_check procedure completed on $bknode, script will continue with the checks.\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - ping_check procedure completed------"


##################################################################################
# Check the Active Router's BGP Sessions to ensure at least 50% of session are up
##################################################################################
puts $FH "-------------------------------------------------------------------------------------------------------------------------------------"
puts $FH "\nCheck the new Active vRRb's ($bknode) number of established BGP sessions\n"

set bgp_stat [bgp_check]

puts $FH "Post bgp_stat = $bgp_stat after bgp_check\n"
puts $FH "bgp_check procedure completed on $bknode, script will continue with the checks.\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - bgp_check procedure completed------"

##################################################################################
# Final Checks
##################################################################################

puts $FH "====================================================================================================================================="
puts $FH "FINAL REMEDIATION SCRIPT SUMMARY\n"
puts $FH "Stat value of 0 indicate a successful completion of that procedure, and value of 1 indicate a failure in that procedure execution.\n"

puts $FH "Detection policy unregisteration Stat = $detpolicy_exist"
puts $FH "Load and Commit Stat = $load_commit_stat"
puts $FH "Loopback Ping Stat Counter = $lping_stat"
puts $FH "BGP Session Stat = $bgp_stat\n"

# Use flush command to flush buffered output to logfile
flush $FH

action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - final check completed------"


########################################################################
# Calling send_email procedure to send alert to OPs team
########################################################################
set email_subject "** Route Reflector $node vRR EEM Remediation Script on backup vRR $bknode completed succesfully, vRRb is now an active router"

if [catch {open $_remediation_storage_location/$_output_log r} result] {
    error $result   
}
set bodytext [read $result]

# Call on the send_email proc to generate an email message
send_email $node $syslog_msg $bodytext

########################################################################
# Unregister the Detection Script first before starting Remediation Checks on vRRb
########################################################################

set recpolicy_exist [register_recovery]

if { $recpolicy_exist == 0} {
    puts $FH "Recovery Policy Registeration Stat = $recpolicy_exist  > registration unsuccessful"
    puts $FH "Recovery Script policy registration UNSUCCESSFUL, manually register the vrr_recovery_script.tcl!\n"
    action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - register_recovery procedure unsuccessful, manual intervention needed------"

    ########################################################################
    # Calling send_email procedure to send alert to OPs team
    ########################################################################
    set email_subject "** Route Reflector $node vRR EEM Remediation Script on backup vRR $bknode is not able to register the recovery policy, manual intervention needed!"

    #if [catch {open $_detection_storage_location/$_output_log r} result] {
    #    error $result   
    #}

    set bodytext {
        vRR EEM Remediation Script is unable to register the recovery script.

        Manual Intervention is needed to register the recovery script. Perform the following actions:

        Register the policy:
            event manager policy vrr_recovery_script.tcl username eem-user persist-time 3600
        
        Check the last captures inside the log file generated to identify the failure condition during Registeration.
        Log file is located on the vRRb router - disk0:/eem/vRR_remediation_logs/
    }
    #set bodytext [read $result]

    # Call on the send_email proc to generate an email message
    send_email $node $syslog_msg $bodytext



} else {
    puts $FH "Recovery Policy Registeration Stat = $recpolicy_exist  > registration successful"
    puts $FH "Recovery Script policy registration SUCCESSFUL, script will finish and exit\n"
    action_syslog msg "------EEM policy vrr_remediation_script on backup vRR $bknode - register_recovery procedure completed successfully------"
}

# Use flush command to flush buffered output to logfile
flush $FH

######################################################################################
# Calling runtime procedure to calculate total script runtime and close the log file.
######################################################################################

runtime

exit
