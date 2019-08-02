::cisco::eem::event_register_timer cron name test cron_entry "* * * * *" maxrun_sec 300

#------------------------------------------------------------------
# 7600_DiagCheck EEM Script
#
# April 2017 - Scott Search (ssearch@cisco.com)
#
# Description:
#   The EEM script is run in a crontab mode.  The script runs every minute and checks the diagnostic consecutive
#   failure count value. The script will collect show commands and then execute RSP switchover if either of the below conditions become true.
# 	  	If the TestFabricFlowControlStatus diag test fails consecutively more than 10 times on active RSP720.
#  		If the TestFabricCh0Health diag test fails simultaneously on both line cards. 
#
# Email Option
# To activate the email option the following EEM environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
# Copyright (c) 2017 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*


set cmds "
enable
show tech-support
show redundancy
show fabric errors 
show fabric drop
show fabric channel-counters
remote command module 1 show log
remote command module 2 show log
remote command switch show fabric resync
remote command switch show platform hardware earl status
remote command switch show platform hardware earl statistics
remote command switch show platform hardware earl interrupt throttle status
remote command switch show platform software earl reset history
remote command switch show platform software earl reset counter
remote command switch show platform software earl reset data
remote command switch test platform firmware me_argos register read all 0 231
remote command switch test platform firmware me_krypton register read all 0  769
remote command switch test platform firmware ssantaana register read 0 all
remote command switch test platform firmware ssantaana register read 1 all
remote command switch test platform firmware telesto register read 0 0 1756
remote command switch test platform firmware scruz fpoe regs dump 0 1 1
remote command switch test platform firmware scruz dump chico 0  1 0
remote command switch test platform firmware kailash reg lprint 0 0x180 0x199 25 1 
remote command switch test platform firmware kailash reg lprint 0 0x1a0 0x1b9 25 1 
remote command switch test platform firmware kailash reg mprint 0 0x152 3 1
remote command switch test platform firmware kailash reg mprint 0 0x420 31 1 
remote command switch test platform firmware kailash reg lprint 0 0x440 0x449 15 1
show logging
"


proc get_ActiveRP {output} {
  set active 5 

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "^Active Location =" $line]} {
      regexp {^Active Location = slot (\d+)} $line - active
    }
  }
  return $active
} ;# get_ActiveRP


proc get_StandbyRP {output} {
  set active 5 

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "^Standby Location =" $line]} {
      regexp {^Standby Location = slot (\d+)} $line - active
    }
  }
  return $active
} ;# get_StandbyRP


proc parse_diagnostic {output} {
  set count 0

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "^Consecutive failure count" $line]} {
      regexp {^Consecutive failure count .* (\d+)} $line - count
    }
  }
  return $count
} ;# parse_diagnostic


proc send_email {node msg} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending 7600 DiagCheck email to: $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "Router $node executed the 7600_DiagCheck EEM script, and  possibly the RSP switchover."]
    set email [format "%s\n%s\n\n" "$email" "$msg"]
    set email [format "%s\n%s" "$email" "\n"]

    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }

    puts $FH "EMAIL DATA BELOW SENT TO: $_email_to\n"
    puts $FH $email
  }
} ;# send_email



####################
# MAIN
####################
global FH
global _email_to _email_from
global _email_server _domainname
global email_subject

set run_flag "disk0:/eem/7600_DiagCheck_run_flag"

# Capture the scripts start time:
set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

# If the $run_flag file exists exit from script:
if [file exists $run_flag] {
  set msg "EEM policy 7600_DiagCheck.tcl detected possible previous RSP switchover due to previous 7600_DiagCheck_run_flag exists!"
  action_syslog msg $msg

  set msg "$msg\nDelete $run_flag in order to activate the EEM 7600_DiagCheck.tcl script."
  puts "\n$msg\n"
  exit
}

set filename "7600_DiagCheck.$date_time"
set output_file "disk0:/eem/$filename"

# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

if [catch {cli_exec $cli(fd) "show redundancy"} result] {
  error $result $errorInfo
}
set ActiveRP [get_ActiveRP $result]
set StandbyRP [get_StandbyRP $result]

set cmd1 "show diagnostic events module $ActiveRP\n"
set cmd2 "show diagnostic result module $ActiveRP detail\n"
set cmd3 "show diagnostic events module $StandbyRP\n"
set cmd4 "show diagnostic result module $StandbyRP detail\n"

# Update the cmds to run 
append cmds $cmd1
append cmds $cmd2
append cmds $cmd3
append cmds $cmd4

set triggerFO 0

if [catch {cli_exec $cli(fd) "show diagnostic result module $ActiveRP test TestFabricFlowControlStatus detail"} result] {
  error $result $errorInfo
}

set continue [parse_diagnostic $result]

if {$continue >= 10} {
	set triggerFO 1
	}
	
if [catch {cli_exec $cli(fd) "show diagnostic result module 1 test TestFabricCh0Health detail"} result1] {
    error $result1 $errorInfo
	}
if [catch {cli_exec $cli(fd) "show diagnostic result module 2 test TestFabricCh0Health detail"} result2] {
    error $result2 $errorInfo
    }
  set mod1Count [parse_diagnostic $result1]
  set mod2Count [parse_diagnostic $result2]


if {$mod1Count >= 1 && $mod2Count >= 1} {
	set triggerFO 1
   }	
if {$triggerFO == 1} {
	# Create the $run_flag file
    if [catch {open $run_flag w} result] {
        error $result
    }
    set RUN $result
    puts $RUN "Timestamp = $date"
    close $RUN


	# EEM script found TestFabricFlowControlStatus failure on RSP720 or both modules 1 and 2 consecutive failure counts non-zero 
	# Now collect additional captures and eventually perform a switch-over

    # Open the output file (for write):
    if [catch {open $output_file w} result] {
        error $result
    }
    set FH $result

    # Timestamp the script start time to the output log file:
    puts $FH "7600 Diag Check - Start Timestamp: $date"

    # Log the nodes hostname to the output log file:
    set node [info hostname]
    set email_subject "**Node $node 7600 Diag Check Run**"
    puts $FH "Node: $node"

    # Running the list of capture commands before RSP switch-over
	foreach CMD [split $cmds "\n"] {
      if {$CMD == ""} { continue }
	  if [catch {cli_exec $cli(fd) $CMD} result] {
        error $result $errorInfo
      }
      puts $FH "$result\n\n"
    }

    set msg "EEM script 7600_DiagCheck ($node) Executed.  EEM script captures saved to file: $output_file"
    action_syslog msg $msg


    # Send/Generate a SNMP trap
    sys_reqinfo_snmp_trapvar var vbinds oid 1.3.6.1.4.1.33333.2.0 string "$msg"
    sys_reqinfo_snmp_trap enterprise_oid 1.3.6.1.4.1.33333.1 generic_trapnum 6 specific_trapnum 1 trap_oid 1.3.6.1.4.1.33333.1.0.1 trap_var vbinds

#    # Send an email message if the following event manager environment variables exists:
#    if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
#      # Call on the send_email proc to generate an email message
#      send_email $node $msg
#    }
	
	if [catch {cli_exec $cli(fd) "wr mem\n\n\n"} result] {
        error $result $errorInfo
      }
	  
    # Finally execute the RSP switchover
    if [catch {cli_exec $cli(fd) "redundancy force-switchover\n\n\n"} result] {
      error $result $errorInfo
    }
    puts $FH "$result\n\n"

    close $FH
  }



