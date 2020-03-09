#!/usr/bin/python3

##  Title:    psl-config-backup.py

##  Desc:     PSL Node config backup tool
##            Pulls configuration from PSL nodes, creates backup on node
##            
## 
##  Author:   Jason Froehlich
##            jafroehl@cisco.com
##
##  Created:  12/20/2019
##  Updated:  12/22/2019

## Requires yaml node file, see example_node_file.yaml

from datetime import datetime
#from yaml import Loader as Loader, Dumper as Dumper
import os
import netmiko
import telnetlib
import time
import yaml

## Constants
#YAML_FILE_NAME = 'psl-nodes-test.yaml'
YAML_FILE_NAME = 'psl-nodes.yaml'
REPORT_TIME = datetime.now().strftime("%Y-%m-%d")
#GROUPS_TO_BACKUP = ['Lab Infrastructure']
#GROUPS_TO_BACKUP = ['CBB Nodes', 'Special Nets Nodes']
GROUPS_TO_BACKUP = ['CBB Nodes', 'Special Nets Nodes', 'Lab Infrastructure']

OUTPUT_PATH = 'PSL-Config-Backups-' + REPORT_TIME + '/'

KNOWN_CREDENTIALS = {
    'TACACS' : ['abc', 'abc'],
    'FALLBACK' : ['abc', 'abc'],
    'admin-upper' : ['abc', 'abc'],
    'admin-lower' : ['abc', 'abc'],
    'admin/admin' : ['abc', 'abc'],
    'admn/admn' : ['abc', 'abc']
}

PLATFORMS = {
    'IOS' : {
        'SSH-Type' : 'cisco_ios',
        'Telnet-Type' : 'cisco_ios_telnet',
        'Type' : ['cisco_ios', 'cisco_ios_telnet'],
        'Collect' : [
            'show run'
        ],
        'Backup' : [
            'copy running-config start',
            'copy running-config config-backup-' + REPORT_TIME + '.txt',
            'dir'
        ]
    },
    'NXOS' : {
        'SSH-Type' : 'cisco_nxos',
        'Telnet-Type' : 'cisco_ios_telnet',
        'Type' : ['cisco_nxos', 'cisco_ios_telnet'],
        'Collect' : [
            'show run'
        ],
        'Backup' : [
            'copy running-config start',
            'copy running-config config-backup-' + REPORT_TIME + '.txt',
            'dir'
        ]
    },
    'IOS-XR' : {
        'SSH-Type' : 'cisco_xr',
        'Telnet-Type' : 'cisco_xr_telnet',
        'Type' : ['cisco_xr', 'cisco_xr_telnet'],
        'Collect' : [
            'show run',
            'admin show run'
        ],
        'Backup' : [
            'copy running-config config-backup-' + REPORT_TIME + '.txt',
            'admin running-config run admin-config-backup-' + REPORT_TIME + '.txt',
            'dir',
            'admin dir'
        ]
    },
    'IOS-XR-64' : {
        'SSH-Type' : 'cisco_xr',
        'Telnet-Type' : 'cisco_xr_telnet',
        'Type' : ['cisco_xr', 'cisco_xr_telnet'],
        'Collect' : [
            'show run',
            'admin show run'
        ],
        'Backup' : [
            'copy running-config config-backup-' + REPORT_TIME + '.txt',
            'admin running-config run admin-config-backup-' + REPORT_TIME + '.txt',
            'dir',
            'admin dir'
        ]
    }
}

## Functions
# read_yaml_file
# Reads YAML file from disk, returns dict of data
def read_yaml_file(filename):
    print('Reading YAML file "' + filename + '"')
    try:
        with open(filename, 'r') as yamlfile:
            yamldata = yaml.load(yamlfile, Loader=yaml.SafeLoader)
    except IOError as error:
        print('Unable to open file ' + filename + ' for reading, exiting.')
        print('')
        quit()
    return yamldata

# write_file
# Handles file writing, takes in filename and list of strings
def write_file(output_file, output_text):
    try:
        with open(output_file, 'w') as reportfile:
            #reportfile.write('\n'.join(output_text) + '\n')
            reportfile.writelines(output_text)
            print("    " + output_file + " written to disk")
    except IOError as error:
        print(' WARNING: Unable to open file ' + output_file + ' for writing')
        print('')

def process_node(nodename, nodeinfo):
    #print('Processing node: ' + nodename)
    # Check OS is present
    if not 'OS' in nodeinfo.keys():
        print('    Skipping - No OS Listed')
        return([False, 'No OS Listed'])
    
    # Check OS is recognized
    elif not nodeinfo['OS'] in PLATFORMS.keys():
        print('    Skipping - OS Not Recognized')
        return([False, 'OS Not Recognized'])
    
    # Check IP is present
    elif not 'Primary IP' in nodeinfo.keys():
        print('    Skipping - No IP Listed')
        return([False, 'No IP Listed'])
    elif nodeinfo['Primary IP'] == '-':
        print('    Skipping - No IP Listed')
        return([False, 'No IP Listed'])
    
    # Basic checks passed
    else:
        #node_output = node_collect(nodeinfo['Primary IP'], BACKUP_COMMANDS[nodeinfo['OS']]['Collect'], BACKUP_COMMANDS[nodeinfo['OS']]['Backup'])
        #node_output = node_collect(nodeinfo)
        node_output = node_collect2(nodeinfo)

        if node_output[0]:
            # Collection Success, write config to file
            write_file(OUTPUT_PATH + node + '.cfg', node_output[1])
        return node_output

def find_node_credentials(nodeinfo):
    if "Authentication" in nodeinfo.keys():
        if nodeinfo['Authentication'] in KNOWN_CREDENTIALS.keys():
            return KNOWN_CREDENTIALS[nodeinfo['Authentication']]
        else:
            if  '/' in nodeinfo['Authentication']:
                return nodeinfo['Authentication'].split("/")
            else:
                return KNOWN_CREDENTIALS['TACACS']
    else:
        return KNOWN_CREDENTIALS['TACACS']

def create_connection(host_ip, device_types, credentials_sets):
    types_tried = 0
    for type in device_types:
        types_tried += 1
        creds_tried = 0
        for credentials in credentials_sets:
            creds_tried += 1
            try: 
                print('    Trying type ' + type + ', credential set ' + str(creds_tried))
                connection = netmiko.ConnectHandler(device_type=type, host=host_ip, username=credentials[0], password=credentials[1])
                print("    Connected as " + type)
            except OSError as error:
                ## IP unreachable, no path to node
                print('    Failed to Connect - Node Unreachable')
                return [False, 'Node Unreachable']
            except netmiko.ssh_exception.NetMikoAuthenticationException as error:
                if creds_tried >= len(credentials_sets):
                    print('    Failed to Connect - Authentication Error')
                    return [False, 'Authentication Error']
                else:
                    # Continue to next set of credentials
                    print('    Credentials unsuccessful')
                    continue
            except netmiko.ssh_exception.NetMikoTimeoutException as error:
                if types_tried >= len(device_types):
                    print('    Failed to Connect - Connection Error')
                    return [False, 'Connection Failure']
                else:
                    # Continue to next type
                    print('    Type ' + type + ' unsuccessful')
                    break
            return [True, connection]

def node_collect2(nodeinfo):
    results = {}
    credentials_sets = [find_node_credentials(nodeinfo), KNOWN_CREDENTIALS['FALLBACK']]

    connect_success, connection = create_connection(nodeinfo['Primary IP'], PLATFORMS[nodeinfo['OS']]['Type'], credentials_sets)

    if connect_success:
        # Connection successful, begin collection
        collect_output = ""
        for command in PLATFORMS[nodeinfo['OS']]['Collect']:
            collect_output += connection.send_command(command, strip_command=False) + '\n\n'
        
        backup_output = ""
        for command in PLATFORMS[nodeinfo['OS']]['Backup']:
            output = connection.send_command_timing(command, strip_prompt=False, strip_command=False)
            if 'Destination file' in output:
                output += connection.send_command_timing('', strip_prompt=False, strip_command=False)
            if 'Do you want to over write? [confirm]' in output:
                output += connection.send_command_timing('', strip_prompt=False, strip_command=False)
            if 'Do you want to overwrite? [no]' in output:
                output += connection.send_command_timing('yes', strip_prompt=False, strip_command=False)
            if 'Do you want to overwrite (y/n)?[n]' in output:
                output += connection.send_command_timing('y', strip_prompt=False, strip_command=False)
            backup_output += output

        connection.disconnect()
        return [True, collect_output, backup_output]

    else:
        # Connection not successful, return error code
        return [False, connection]


def node_collect(nodeinfo):
    results = {}
    username, password = find_node_credentials(nodeinfo)
    
    try:
        connection = netmiko.ConnectHandler(device_type=PLATFORMS[nodeinfo['OS']]['SSH-Type'], host=nodeinfo['Primary IP'], username=username, password=password)
        print("    Connected via SSH")
    except OSError as error:
        ## IP unreachable, no path to node
        print('    Failed to Connect - Node Unreachable')
        return [False, "Node Unreachable"]
    except netmiko.ssh_exception.NetMikoAuthenticationException as error:
        ## Auth error, try fallback credentials
        try:
            fallback_user, fallback_pass = KNOWN_CREDENTIALS['FALLBACK']
            connection = netmiko.ConnectHandler(device_type=PLATFORMS[nodeinfo['OS']]['SSH-Type'], host=nodeinfo['Primary IP'], username=fallback_user, password=fallback_pass)
            print("    Connected via SSH")
        except netmiko.ssh_exception.NetMikoAuthenticationException as error2:
            print('    Failed to Connect - Authentication Error')
            return [False, "Authentication Error"]
    except netmiko.ssh_exception.NetMikoTimeoutException as error:
        ## SSH Error/Timeout, try Telnet
        try:
            connection = netmiko.ConnectHandler(device_type=PLATFORMS[nodeinfo['OS']]['Telnet-Type'], host=nodeinfo['Primary IP'], username=username, password=password)
            print("    Connected via Telnet")
        except OSError as error:
            ## IP unreachable, no path to node
            print('    Failed to Connect - Node Unreachable')
            return [False, "Node Unreachable"]
        except netmiko.ssh_exception.NetMikoAuthenticationException as error:
            ## Auth error, try fallback credentials
            try:
                fallback_user, fallback_pass = KNOWN_CREDENTIALS['FALLBACK']
                connection = netmiko.ConnectHandler(device_type=PLATFORMS[nodeinfo['OS']]['Telnet-Type'], host=nodeinfo['Primary IP'], username=fallback_user, password=fallback_pass)
                print("    Connected via Telnet")
            except netmiko.ssh_exception.NetMikoAuthenticationException as error2:
                print('    Failed to Connect - Authentication Error')
                return [False, "Authentication Error"]
        except netmiko.ssh_exception.NetMikoTimeoutException as error:
            ## Telnet error
            print('    Failed to Connect - Unreachable on SSH and Telnet')
            return [False, "SSH and Telnet Failure"]
    
    collect_output = ""
    for command in PLATFORMS[nodeinfo['OS']]['Collect']:
        collect_output += connection.send_command(command, strip_command=False) + '\n\n'
    
    backup_output = ""
    for command in PLATFORMS[nodeinfo['OS']]['Backup']:
        output = connection.send_command_timing(command, strip_prompt=False, strip_command=False)
        if 'Destination file' in output:
            output += connection.send_command_timing('', strip_prompt=False, strip_command=False)
        if 'Do you want to over write? [confirm]' in output:
            output += connection.send_command_timing('', strip_prompt=False, strip_command=False)
        if 'Do you want to overwrite? [no]' in output:
            output += connection.send_command_timing('yes', strip_prompt=False, strip_command=False)
        if 'Do you want to overwrite (y/n)?[n]' in output:
            output += connection.send_command_timing('y', strip_prompt=False, strip_command=False)
        backup_output += output

    connection.disconnect()
    return [True, collect_output, backup_output]


## Main

full_data = read_yaml_file(YAML_FILE_NAME)
try:
    os.mkdir(OUTPUT_PATH)
    print("Creating output path " + OUTPUT_PATH)
except FileExistsError as error:
    print("Path " + OUTPUT_PATH + " already exists")

# skipped groups = { 'Group Name' : Count of nodes in group}
skipped_groups = {}
success_nodes = {}
failed_nodes = {}

for group in full_data.keys():
    if group in GROUPS_TO_BACKUP:
        success_nodes[group] = {}
        failed_nodes[group] = {}
        nodes_in_group = len(full_data[group].keys())
        print('Beginning collection for ' + group + ', ' + str(nodes_in_group) + ' nodes total')
        nodecounter = 0
        for node in sorted(full_data[group].keys()):
            nodecounter += 1
            print('  Proccessing node ' + str(nodecounter) + ': ' + node)
            # results = [ True|False, Collection|ErrorString ]
            results = process_node(node, full_data[group][node])
            if results[0]:
                success_nodes[group][node] = results[2]
            else:
                failed_nodes[group][node] = results[1]

    # Skipped groups
    elif group != 'Generated':
        for node in full_data[group].keys():
            if group in skipped_groups.keys():
                skipped_groups[group] += 1
            else:
                skipped_groups[group] = 1

#dump_configs(success_nodes)

## Display Skipped Group Stats
if len(skipped_groups.keys()) > 0:
    print('\nCollection of the following groups was skipped:')
    for group in sorted(skipped_groups.keys()):
        print('  ' + group + ' (' + str(skipped_groups[group]) + ' nodes)')

## Display Failed Node Stats
print('\nCollection failed on the following nodes:')
for group in failed_nodes.keys():
    print('  ' + group)
    if len(failed_nodes[group].keys()) > 0:
        for node in failed_nodes[group].keys():
            print('    ' + node + ' - ' + failed_nodes[group][node])
    else:
        print('    None')

print('\n\n')

## Interaction after script completes, type quit() to exit
print('Script complete, Type quit() to exit')
import code
code.interact(local=locals())
