::cisco::eem::event_register_syslog pattern "ROUTING-FIB-3-PLATF_UPD_FAIL.*Platform upd failed" maxrun 600

#------------------------------------------------------------------
# asr9k_fib_collection EEM Script
#
# December 2015 - Scott Search (ssearch@cisco.com)
#
# This EEM script will be triggered off the following syslog message:
#   %ROUTING-FIB-3-PLATF_UPD_FAIL : Platform upd failed: Obj=DATA_TYPE_LOADINFO[ptr=99e60d94,refc=0x1
#
# Once this syslog message is received on the router the EEM script will collect a number of captures
#
# EEM Script is dependent on the following event manager environment variables:
#   _asr9k_fib_collection_storage_location <storage>  -Disk/hardisk storage location "harddisk:/eem"
#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
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
#
# Hardcoded this within the script below
#if {![info exists _asr9k_fib_collection_storage_location]} {
#  set result "EEM policy error: environment var _asr9k_fib_collection_storage_location not set"
#  error $result $errInfo
#}

# Below var flag is used to verify if the asr9k_fib_collection.tcl script has run previously:
#set run_flag "$_asr9k_fib_collection_storage_location/asr9k_fib_collection_run_flag"

##################################
# PROCs:
##################################
proc get_location {line} {
  set location ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
  regsub -all {[ ]$} $line "" line

  if {[regexp {^time_sec} $line]} {
    regexp "\{(.*): .*" $line - msg
    set location [ lindex [split $msg ":"] 0 ]
    regsub {^LC\/} $location "" location
  } else {
    set location [ lindex [split $line ":"] 0 ]
    regsub {^LC\/} $location "" location
  }

  return $location
} ;# get_location


proc send_syslog {msg repeat} {
  set kont 0

  while {$kont < $repeat} {
    action_syslog msg $msg
    incr kont
  }
} ;# send_syslog


proc send_email {node syslog_msg msg} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending ASR9K FIB Collections run notification to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "The $node node run the asr9k_fib_collection EEM script for syslog:"]
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
global _asr9k_fib_collection_storage_location

set _asr9k_fib_collection_storage_location "harddisk:/eem"
set repeat 1 
set locations ""

# Capture the scripts start time:
set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "asr9k_fib_collection.$date_time"
set output_file "$_asr9k_fib_collection_storage_location/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp the script start time to the output log file:
puts $FH "Start Timestamp: $date"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)

# Get the location, head and tail values from the triggering syslog_msg
set location [get_location $syslog_msg]

set config ""
lappend config "rcc ipv4 unicast enable"
lappend config "rcc ipv6 unicast enable"
lappend config "lcc ipv4 unicast enable"
lappend config "lcc ipv6 unicast enable"

set CMDs ""
lappend CMDs "debug cef assert location 0/0/CPU0"
lappend CMDs "debug cef assert location 0/1/CPU0"
lappend CMDs "show logging"
lappend CMDs "show cef ipv4 platform trace common hal all location $location"
lappend CMDs "show cef ipv4 platform trace common hal all location 0/0/cpu0"
lappend CMDs "show cef ipv4 platform trace common hal all location 0/1/cpu0"
lappend CMDs "show cef mpls platform trace common hal all loca $location"
lappend CMDs "show cef mpls platform trace common hal all loca 0/0/cpu0"
lappend CMDs "show cef mpls platform trace common hal all loca 0/1/cpu0"
lappend CMDs "show cef ipv4 trace location $location"
lappend CMDs "show cef ipv4 trace location 0/0/cpu0"
lappend CMDs "show cef ipv4 trace location 0/1/cpu0"
lappend CMDs "show cef mpls trace location $location"
lappend CMDs "show cef mpls trace location 0/0/cpu0"
lappend CMDs "show cef mpls trace location 0/1/cpu0"
lappend CMDs "show cef platform event stats location $location"
lappend CMDs "show cef platform event stats location 0/0/cpu0"
lappend CMDs "show cef platform event stats location 0/1/cpu0"
lappend CMDs "show cef unresolved location $location"
lappend CMDs "show cef unresolved location 0/0/cpu0"
lappend CMDs "show cef unresolved location 0/1/cpu0"

lappend CMDs "show rcc ipv4 unicast stat"
lappend CMDs "show rcc ipv4 unicast stat summ"
lappend CMDs "show rcc ipv4 unicast stat scan-id 120"
lappend CMDs "show rcc ipv6 unicast stat"
lappend CMDs "show rcc ipv6 unicast stat summ"
lappend CMDs "show rcc ipv6 unicast stat scan-id 120"

lappend CMDs "show lcc ipv4 unicast stat"
lappend CMDs "show lcc ipv4 unicast stat summ"
lappend CMDs "show lcc ipv4 unicast stat scan-id 120"
lappend CMDs "show lcc ipv6 unicast stat"
lappend CMDs "show lcc ipv6 unicast stat summ"
lappend CMDs "show lcc ipv6 unicast stat scan-id 120"


# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}


# Configure the RCC and LCC features
if [catch {cli_exec $cli(fd) "config"} result] {
  error $result $errorInfo
}

foreach cmd $config {
  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
}

if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}


# Run all the show command collections
foreach cmd $CMDs {
  puts $FH "Running CMD: $cmd\n"

  if [catch {cli_exec $cli(fd) $cmd} result] {
    error $result $errorInfo
  }
  puts $FH "$result\n\n"
}


# Un-Configure the RCC and LCC features
if [catch {cli_exec $cli(fd) "config"} result] {
  error $result $errorInfo
}

foreach cmd $config {
  if [catch {cli_exec $cli(fd) "no $cmd"} result] {
    error $result $errorInfo
  }
}

if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}


# Log the nodes hostname to the output log file:
set node [info hostname]
set email_subject "**Node $node ASR9K FIB Collections**"

set msg "EEM script asr9k_fib_collection ($node) COMPLETED.  EEM script captures saved to file:\n$output_file"
send_syslog $msg $repeat

# Send an email message if all below exists:
if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
  # Call on the send_email proc to generate an email message
  send_email $node $syslog_msg $msg
}

close $FH
