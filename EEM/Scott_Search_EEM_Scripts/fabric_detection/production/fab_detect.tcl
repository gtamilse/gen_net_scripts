::cisco::eem::event_register_syslog pattern "sysmgr.*sfe_drvr.*abnormally terminated.*restart scheduled" maxrun 180

#------------------------------------------------------------------
# Fabric Error Detection Script and Card Shutdown
#
#
# April 2010 - Scott Search (ssearch@cisco.com)
#
#
# This tool is an EEM policy to detect the syslog pattern above.  If the
# syslog message is generated by the node this eem script will start and
# detect the card location.  Then the script will verify the admin controller
# fabric all details.  The script then shuts down the problematic card.
# The script then generates an email, syslog message and a snmp trap.
#
#
# Copyright (c) 2010 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
#
#
# The namespace import commands that follow import some cisco TCL extensions
# that are required to run this script
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

#################################################################################################
# These vars below should be set via the IOX global configuration for event manager environment:
#set _email_server 9.3.3.249
#set _domainname "cisco.com"
#set _email_from "ssearch@cisco.com"
#set _email_to "ssearch@cisco.com"
#set _storage_location "harddisk:/eem"
#set _output_log "eem_fabric_detect.log"

# Verify the environment vars:
if {![info exists _storage_location]} {
  set result "EEM policy error: environment var _storage_location not set"
  error $result $errInfo
}
if {![info exists _output_log]} {
  set result "EEM policy error: environment var _output_log not set"
  error $result $errInfo
}

# Below var flag is used to verify if the fab_detect.tcl script has run previously:
set fab_detect_run_flag "$_storage_location/fab_detect_run_flag"

# Disabled the email sending environment check since the email option is disabled:
;#if {![info exists _email_server]} {
;#  set result "EEM policy error: environment var _email_server not set"
;#  error $result $errInfo
;#}
;#if {![info exists _email_from]} {
;#  set result "EEM policy error: environment var _email_from not set"
;#  error $result $errInfo
;#}
;#if {![info exists _email_to]} {
;#  set result "EEM policy error: environment var _email_to not set"
;#  error $result $errInfo
;#}
;#if {![info exists _domainname]} {
;#  set result "EEM policy error: environment var _domainname not set"
;#  error $result $errInfo
;#}

#################################################################################################


###########################################
# Procedures
###########################################
proc process_fabric_plane_all {retval} {
  global FH
  set ID ""
  set admin ""
  set oper ""
  set down_plane ""
  set kont 0

  puts $FH "Show controllers fabric plane all CHECK:"

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    if {[regexp {^\d+ \w+ \w+} $line]} {
      incr kont
      regexp {^(\d+) (\w+) (\w+).*} $line - ID admin oper
      #regexp {^(\d+) (\w+) (\w+)$} $line - ID admin oper
      puts $FH "Id: $ID - Admin: $admin - Oper: $oper"
      # Check to see if the Oper status is DOWN:
      if {[regexp -nocase "down" $oper]  && ![regexp -nocase "down" $admin]} {
        lappend down_plane $ID
      }
    }
  }
  return $down_plane
}

proc send_email {node syslog_msg nodename fab_plane_all msg} {
  global FH _email_to _email_from _email_server

  #action_syslog msg "Sending Fabric Error Detection to $_email_to"
  set email [format "Mailservername: %s" "$_email_server"]
  set email [format "%s\nFrom: %s" "$email" "$_email_from"]
  set email [format "%s\nTo: %s" "$email" "$_email_to"]
  set email [format "%s\nCc: %s" "$email" ""]
  set email [format "%s\nSubject: %s\n" "$email" "**Node $node Fabric Error Detection**"]
  # Email BODY:
  set email [format "%s\n%s" "$email" "The $node node experienced the following syslog:"]
  set email [format "%s\n%s\n" "$email" "$syslog_msg"]
  set email [format "%s\n%s" "$email" "$msg"]
  
  set email [format "%s\n%s" "$email" "Fabric Plane All Output (before card shutdown):"]
  set email [format "%s\n%s\n" "$email" "$fab_plane_all"]
  
  # Send email message:
  if [catch {smtp_send_email $email} result] {
    puts "smtp_send_email: $result"
  }

  puts $FH "EMAIL DATA BELOW SENT TO: $_email_to\n"
  puts $FH $email
}


###########################################
# MAIN/main
###########################################
   
###########################################
# Globals:
global FH _email_to _email_from _email_server

# Open the output file (for write):
if [catch {open $_storage_location/$_output_log w} result] {
    error $result
}
set FH $result

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"
puts $FH "Cisco Fabric Error Detection Script"
puts $FH "Designed for: IOX Embedded Event Manager (EEM)"
puts $FH "by: Scott Search (ssearch@cisco.com)\n"
 
###########################################
# Open Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

# Set node hostname:
set node [info hostname]
puts $FH "Node: $node"

set junk ""
set location ""
set nodename ""

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message:
set syslog_msg $arr_einfo(msg)

# Extract the nodename:
regexp {^(.*?):.*} $syslog_msg junk location
regexp {^\w+/(.*?)} $location - nodename

puts $FH "SYSLOG MSG:\n$syslog_msg"
puts $FH "Suspect location: $nodename\n"

# Enter Admin mode:
if [catch {cli_exec $cli(fd) "admin"} result] {
  error $result $errorInfo
}

# Gather the 'admin show controllers fabric plane all' info
if [catch {cli_exec $cli(fd) "show controllers fabric plane all"} result] {
  error $result $errorInfo
}
# Remove trailing router prompt
regexp {\n*(.*\n)([^\n]*)$} $result junk fab_plane_all

# Verify if there are any fabric down planes:
set down_plane [process_fabric_plane_all $fab_plane_all]
if {$down_plane != ""} {
  puts $FH "\nCurrent down Fabric Plane(s): $down_plane\n"
}

# If the $fab_detect_run_flag file exists exit from script:
if [file exists $fab_detect_run_flag] {
  # Exit Admin mode:
  if [catch {cli_exec $cli(fd) "exit"} result] {
    error $result $errorInfo
  }
  set msg "EEM policy fab_detect detected Fabric Error on card $nodename yet $fab_detect_run_flag exists No Action Taken!"
  ;#send_email $node $syslog_msg $nodename $fab_plane_all $msg
  action_syslog msg $msg

  set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
  puts $FH "\n*Timestamp = $date"
  set msg "$msg\nDelete $fab_detect_run_flag in order to activate the EEM fab_detect script."
  set msg "$msg\n\nThe $node node experienced the following syslog:"
  set msg "$msg\n$syslog_msg"
  set msg "$msg\n\nFabric Plane All Output:"
  set msg "$msg\n$fab_plane_all\n\n"
  puts $FH $msg
  close $FH
  exit
}

# Create the $fab_detect_run_flag file
if [catch {open $fab_detect_run_flag w} result] {
    error $result
}
set RUN $result
set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $RUN "*Timestamp = $date"
close $RUN

# Finally shutdown the CARD
# Enter config terminal:
if [catch {cli_exec $cli(fd) "config t"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "hw-mod shut loc $nodename"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}
# End of CARD shutdown tasks

# Exit Admin mode:
if [catch {cli_exec $cli(fd) "exit"} result] {
  error $result $errorInfo
}

###########################################
# Craft up the email message:
#disabled email option per Gaurav
;#set msg "The fab_detect eem policy script has shutdown the following card:\n$nodename"
;#send_email $node $syslog_msg $nodename $fab_plane_all

set msg "\n\n**Node: $node Fabric Error Detection**"
set msg "$msg\nThe $node node experienced the following syslog:"
set msg "$msg\n$syslog_msg"
set msg "$msg\n\nThe fab_detect eem policy script has shutdown the following card location:"
set msg "$msg\n$nodename"
set msg "$msg\n\nFabric Plane All Output (before card shutdown):"
set msg "$msg\n$fab_plane_all\n\n"
set msg "$msg\nThe $fab_detect_run_flag file exists. Be sure to delete the file in order to"
set msg "$msg\nActivate the EEM fab_detect script.\n"

puts $FH $msg

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "\n*Timestamp = $date"
 
close $FH

# Send syslog message:
action_syslog msg "EEM policy fab_detect detected a Fabric Error and has SHUTDOWN CARD: $nodename"
