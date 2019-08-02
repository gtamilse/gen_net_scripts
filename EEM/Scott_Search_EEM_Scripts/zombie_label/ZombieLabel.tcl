::cisco::eem::event_register_syslog pattern "ROUTING-FIB-5-ROUTE_UPDATE_DROP : LABEL-RECYCLING: label" maxrun 180

#------------------------------------------------------------------
# Zombie Label EEM Script
#
# January 2017 - Scott Search (ssearch@cisco.com)
#
# This EEM script will be triggered off the following syslog message:
#   %ROUTING-FIB-5-ROUTE_UPDATE_DROP : LABEL-RECYCLING: label=26412 new-prefix=172.28.202.32/28, tbl=13979:6760
#
# EEM Script Logic:
#
# Copyright (c) 2017 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##################################
# Verify the environment vars:
##################################

##################################
# PROCs:
##################################
proc xmit {cmd} {
  global errorInfo
  global term_rows
  global FH
  upvar cli cli
 
  if [catch {cli_exec $cli(fd) "$cmd"} result] {
    error $result $errorInfo
  } else {
    set term_rows $result
  }
  puts $FH "$result\n\n\n"

  return $term_rows
} ;# xmit


proc get_labels {output} {
  set labels ""

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "show mpls" $line]} { continue }

    set label [lindex [split $line " "] 1]

    if {$label != "" && [regexp -nocase "zombie" $line]} {
      lappend labels $label
    }
  }
  return $labels
} ;# get_labels


proc determine_activity {output} {
  set alert ""

  foreach line [split $output "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp -nocase "^BGP Label Entry" $line] && ![regexp -nocase "inactive" $line] } {
      set alert 1
    }
  }
  return $alert
} ;# proc determine_activity


proc send_syslog {msg repeat} {
  set kont 0

  while {$kont < $repeat} {
    action_syslog msg $msg
    incr kont
  }
} ;# send_syslog

proc send_email {node syslog_msg msg} {
  global _email_to _email_from
  global _email_server _domainname
  global email_subject
  global FH

  action_syslog msg "Sending Zombie Collections run notification to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "The $node node run the Zombie Collections EEM script for syslog:"]
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
global term_rows FH
global _email_to _email_from
global _email_server _domainname
global email_subject
global storage_location

set errorInfo ""
set term_rows ""
set storage_location "disk0:/eem"
set repeat 1 

# Capture the scripts start time:
set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "Zombie_collections.$date_time"
set output_file "$storage_location/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp the script start time to the output log file:
puts $FH "Start Timestamp: $date"

 
# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}
xmit "term len 0"

# Collect some comand collections
xmit "show mpls lsd pri | inc zom"

set output [xmit "show mpls label table private | inc Zombie"]

# Parse out the labels
set labels [get_labels $output]

foreach label [split $labels " "] {
  set output [xmit "show bgp label $label det"]

  set alert [determine_activity $output]

  if {$alert == 1} {
    set output [xmit "show mpls label table private | inc Zom | inc $label"]

    if {[regexp -nocase "Zombie" $output]} {
      xmit "show mpls label table lab $label detail"
      xmit "show mpls lsd trace"
      xmit "show bgp trace"
      xmit "dumpcore running bgp"
    }
  }
}


set msg "EEM script ZombieLabel ($node) COMPLETED.  EEM script captures saved to file:\n$output_file"
send_syslog $msg $repeat

# Send an email message if all below exists:
if {[info exists _email_server] && [info exists _domainname] && [info exists _email_from] && [info exists _email_to]} {
  # Call on the send_email proc to generate an email message
  send_email $node $syslog_msg $msg
}

close $FH


