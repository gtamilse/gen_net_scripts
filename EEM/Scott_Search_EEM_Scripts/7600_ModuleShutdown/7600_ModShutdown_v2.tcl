#!/usr/bin/tclsh

#------------------------------------------------------------------
# 7600_ModShutdown EEM Script
#
# September 2017 - Scott Search (ssearch@cisco.com)
#
# EEM script triggered off the following syslog message:
#     "DIAG-SP-3-MAJOR: Module 9: Online Diagnostics detected a Major Error"
#
# Description:
#
#     Shutdown module if the Online Diagnostics major error was detected
#
# Copyright (c) 2017 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

set rawmsg [lindex $argv 0]
set cleanmsg [string map { "\"" "" } $rawmsg]

regexp {Module (\d+): Online} $cleanmsg - module

exec "enable"
ios_config "no power enable module $module"
exec "exit"


