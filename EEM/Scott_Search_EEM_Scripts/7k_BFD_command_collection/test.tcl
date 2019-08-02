#!/usr/bin/tclsh

#set fd [open "syslog:" "w"]

set fd [open "/log:/messages" "w"]
puts $fd {%BGP-5-ADJACENCY: blah blah}
close $fd


