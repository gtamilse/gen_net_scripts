::cisco::eem::event_register_syslog pattern "L2-BM-4-SELECTION : Selection Logic for.*is in LACP loopback" maxrun 180

#------------------------------------------------------------------
#
# LACP Loopback Detection EEM Script
#
# February 2015 - Scott Search (ssearch@cisco.com)
#
# This EEM script will be triggered off the following syslog message:
#
# L2-BM-4-SELECTION : Selection Logic for bundle Bundle-POS3131: Member PO0/3/3/3 (0x01380420) is in LACP loopback
#
# Once the script is triggered the script will run some lacp packet-capture commands
#
# EEM Script is dependent on the following event manager environment variables:
#   _LACP_LoopDetection_storage_location <storage>  -Disk/hardisk storage location "harddisk:/eem"
#
# EEM Script Logic:
#
# The script is triggered by the syslog pattern above. Once the script is triggered the script will run a single
# lacp packet-capture command.  Then stop the lacp packet-capture and restart the capture.  Issue the show
# commands a number of additional times.  Then the script will stop and wait for the next occurrence.
#
# Copyright (c) 2015 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _LACP_LoopDetection_storage_location]} {
  set result "EEM policy error: environment var _LACP_LoopDetection_storage_location not set"
  action_syslog msg $result
  exit 1
}

# Below var flag is used to verify if the LACP_LoopDetection.tcl script has run previously:
set run_flag "$_LACP_LoopDetection_storage_location/run_flag_LACP_LoopDetection"

##################################
# PROCs:
##################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}


proc GetMemberInterfaces {syslog} {
  set member ""
  set members ""

  foreach line [split $syslog "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "BM-DISTRIB.*L2-BM-4-SELECTION : .* is in LACP loopback" $line]} {
      regexp { Member (\w+\d+\/\d+\/\d+\/\d+)} $line - member
      lappend members $member
    }
  }

  set members [lsort -unique $members]
  return $members
}


proc send_email {node syslog_msg msg} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending LACP_LoopDetection run notification to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "The $node node run the LACP_LoopDetection EEM script for syslog:"]
    set email [format "%s\n%s\n\n" "$email" "$syslog_msg"]
    set email [format "%s\n%s" "$email" "$msg"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
 
    puts $FH "EMAIL DATA BELOW SENT TO: $_email_to\n"
    puts $FH $email
  }
} ;# send_email


##################################
# MAIN/main
##################################
global FH
global _email_to _email_from
global _email_server _domainname
global email_subject

# Capture the scripts start time:
set time_now [clock seconds]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "LACP_LoopDetection.$date_time"
set output_file "$_LACP_LoopDetection_storage_location/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp the script start time to the output log file:
puts $FH "Start Timestamp: $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
set email_subject "**Node $node LACP Loop Detection**"
puts $FH "Node: $node"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)

# Get the bundle member interface
set members [GetMemberInterfaces $syslog_msg]

## If the $run_flag file exists exit from script:
#if [file exists $run_flag] {
#  set msg "EEM policy LACP_LoopDetection.tcl detected a possible LACP Loopback, yet $run_flag exists No Action Taken!"
#  action_syslog msg $msg
#
#  set msg "$msg\nDelete $run_flag in order to activate the EEM LACP_LoopDetection.tcl script."
#  set msg "$msg\n\nThe $node node experienced the following syslog:"
#  set msg "$msg\n$syslog_msg"
#  puts $FH $msg
#  close $FH
#  exit
#}

# Create the $fab_detect_run_flag file
if [catch {open $run_flag w} result] {
    error $result
}
set RUN $result
puts $RUN "Timestamp = $date"
close $RUN


puts $FH "\n"
puts $FH "Final Syslog Trigger:"
puts $FH $syslog_msg
puts $FH "\n"

set msg "EEM script LACP_LoopDetection triggered and collecting a number of LACP Packet-Captures"
action_syslog msg $msg

puts $FH "Opening router connection\n"

# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

foreach member [split $members " "] {
  set cmd "show lacp packet-capture $member"
  puts $FH "Running CMD: $cmd"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
  sleep 2

  set cmd "lacp packet-capture $member stop"
  puts $FH "Running CMD: $cmd"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
  sleep 2

  set cmd "lacp packet-capture $member 100"
  puts $FH "Running CMD: $cmd"
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
  sleep 2


  for {set n 0} {$n < 9} {incr n} {
    set cmd "show lacp packet-capture $member"
    puts $FH "Running CMD: $cmd"
    if [catch {cli_exec $cli(fd) $cmd} result] {
      error $result $errorInfo
    }
    puts $FH "$result\n\n"
    sleep 2
  }
}

close $FH


