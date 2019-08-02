::cisco::eem::event_register_syslog pattern "ROUTING-BGP-5-ADJCHANGE.*neighbor.*Down.*Interface flap.*VRF: 13979:32545" maxrun 300

#------------------------------------------------------------------
# Customer 7/11 BGP peer bounce
#
# September 2012 - Scott Search (ssearch@cisco.com)
#
# Syslog message:
# %ROUTING-BGP-5-ADJCHANGE : neighbor 10.242.3.158 Down - Interface flap (VRF: 13979:32545)
#
# EEM script will be triggered off the above syslog message.  The script will extract the bgp peer
# IP.  The EEM script will then shutdown the 7/11 VRF bgp peer for 20 seconds then turn it back up.
#
# Copyright (c) 2012 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

#################################################################################################
# These vars below should be set via the IOX global configuration for event manager environment:
#set _email_server 135.82.2.249 -OR- 135.82.2.245
#set _domainname "att.com"
#set _email_from "eem@att.com"
#set _email_to "ssearch@cisco.com"
#set _storage_location "disk0:/eem"
#set _output_log "eem_7-11_BGP_Bounce.log"

# Verify the environment vars:
if {![info exists _storage_location]} {
  set result "EEM policy error: environment var _storage_location not set"
  error $result $errInfo
}
if {![info exists _output_log]} {
  set result "EEM policy error: environment var _output_log not set"
  error $result $errInfo
}

# Below is for generating emails
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
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc send_email {node syslog_msg msg} {
  global FH _email_to _email_from _email_server

  action_syslog msg "7/11 Customer BGP Bounce - Sending email to: $_email_to"
  set email [format "Mailservername: %s" "$_email_server"]
  set email [format "%s\nFrom: %s" "$email" "$_email_from"]
  set email [format "%s\nTo: %s" "$email" "$_email_to"]
  set email [format "%s\nCc: %s" "$email" ""]
  set email [format "%s\nSubject: %s\n" "$email" "**Node $node 7/11 BGP Bounce**"]
  # Email BODY:
  set email [format "%s\n%s" "$email" "The $node node experienced the following syslog:"]
  set email [format "%s\n%s\n" "$email" "$syslog_msg"]
  
  # Send email message:
  if [catch {smtp_send_email $email} result] {
    puts "smtp_send_email: $result"
  }

  puts $FH "EMAIL DATA BELOW SENT TO: $_email_to\n"
  puts $FH $email
}

proc extract_bgp_data {syslog} {
  # Trim up the line remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $syslog " " syslog
  # Remove any leading white space:
  regsub -all {^[ ]} $syslog "" syslog
  # Remove any ending white space:
  regsub -all {[ ]$} $syslog "" syslog

  regexp {neighbor (\d+\.\d+\.\d+\.\d+)} $syslog - IP
  return $IP
}


###########################################
# MAIN
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
puts $FH "Cisco 7/11 customer bgp bounce"
puts $FH "by: Scott Search (ssearch@cisco.com)\n"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message:
set syslog_msg $arr_einfo(msg)

set peer_IP [extract_bgp_data $syslog_msg]

puts $FH "SYSLOG MSG:\n$syslog_msg\n\n"
puts $FH "BGP Peer down: $peer_IP\n"

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

## Enter Admin mode:
#if [catch {cli_exec $cli(fd) "admin"} result] {
#  error $result $errorInfo
#}

## Gather the 'admin show platform' info BEFORE
#if [catch {cli_exec $cli(fd) "show platform"} result] {
#  error $result $errorInfo
#}
## Remove trailing router prompt
#regexp {\n*(.*\n)([^\n]*)$} $result junk sh_platform


# Shutdown the BGP peer
if [catch {cli_exec $cli(fd) "config"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "router bgp 13979"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "vrf 13979:32545"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "neighbor $peer_IP"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "shutdown"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}

# Sleep 20 seconds
sleep 20

if [catch {cli_exec $cli(fd) "no shutdown"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}


###########################################
# Craft up the email message:
set msg "\n\n**Node: $node 7/11 BGP customer peer flap**"
set msg "$msg\nThe $node node experienced the following syslog:"
set msg "$msg\n$syslog_msg"
set msg "$msg\n\nThe 7-11_bgp_bounce eem policy script has bounced the BGP peer for:"
set msg "$msg\n$peer_IP"

send_email $node $syslog_msg $msg

puts $FH $msg

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "\n*Timestamp = $date"
 
close $FH

# Send syslog message:
action_syslog msg "EEM policy 7-11_bgp_bounce has bounced BGP peer: $peer_IP"
