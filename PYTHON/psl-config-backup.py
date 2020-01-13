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
##  Updated:  12/20/2019

## Requires YAML file to import node list! See example_node_file.yaml

from datetime import datetime
from yaml import Loader as Loader, Dumper as Dumper
import os
import paramiko
import telnetlib
import time
import yaml

## Constants
#YAML_FILE_NAME = 'psl-nodes-test.yaml'
YAML_FILE_NAME = 'psl-nodes.yaml'
REPORT_TIME = datetime.now().strftime("%Y-%m-%d")
#GROUPS_TO_BACKUP = ['Lab Infrastructure']
GROUPS_TO_BACKUP = ['CBB Nodes', 'Special Nets Nodes']
OUTPUT_PATH = 'PSL-Config-Backups-' + REPORT_TIME

USERNAME = 'de'
PASSWORD = 'cisco123'
FALLBACK_USERNAME = 'cisco'
FALLBACK_PASSWORD = 'cisco'

BACKUP_COMMANDS = {
    'IOS' : {
        'Collect' : [
            'show run'
        ],
        'Backup' : [
            'term len 0\n'
            'copy run start\n\n',
            'copy run config-backup-' + REPORT_TIME + '.txt\n\n\n',
            'dir\n'
        ]
    },
    'NXOS' : {
        'Collect' : [
            'show run'
        ],
        'Backup' : [
            'term len 0\n'
            'copy run start\n\n',
            'copy run config-backup-' + REPORT_TIME + '.txt\n\n\n',
            'dir\n'
        ]
    },
    'IOS-XR' : {
        'Collect' : [
            'show run',
            'admin show run'
        ],
        'Backup' : [
            'term len 0\n'
            'copy run config-backup-' + REPORT_TIME + '.txt\n\n\n',
            'admin copy run admin-config-backup-' + REPORT_TIME + '.txt\n\n\n',
            'dir\n'
        ]
    },
    'IOS-XR-64' : {
        'Collect' : [
            'show run'
        ],
        'Backup' : [
            'term len 0\n'
            'copy run config-backup-' + REPORT_TIME + '.txt\n\n\n',
            'dir\n'
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
            reportfile.write('\n'.join(output_text) + '\n')
            #reportfile.writelines(output_text)
            print("  " + output_file + " written to disk")
    except IOError as error:
        print(' Unable to open file ' + output_file + ' for writing, exiting.')
        print('')
        quit()

def process_node(nodename, nodeinfo):
    #print('Processing node: ' + nodename)
    # Check OS is present
    if not 'OS' in nodeinfo.keys():
        return([False, 'No OS Listed'])
    
    # Check OS is recognized
    elif not nodeinfo['OS'] in BACKUP_COMMANDS.keys():
        return([False, 'OS Not Recognized'])
    
    # Check IP is present
    elif not 'Primary IP' in nodeinfo.keys():
        return([False, 'No IP Listed'])
    
    # Basic checks passed
    else:
        node_output = node_collect(nodeinfo['Primary IP'], BACKUP_COMMANDS[nodeinfo['OS']]['Collect'], BACKUP_COMMANDS[nodeinfo['OS']]['Backup'])
        return node_output

def node_collect(node_ip, collect_list, backup_list):
    results = {}

    ## Try SSH connection first
    ssh_test_results = try_ssh(node_ip)
    #print(ssh_test_results)
    if ssh_test_results == True:
        #print("  Connecting via SSH")
        #print("  Collecting:")
        for command in collect_list:
            results[command] = ssh_collect(node_ip, command)
        results['Backup'] = ssh_backup(node_ip, backup_list)
        #print(results)
        return [True, results]
    elif ssh_test_results == "connect_error":
        telnet_result = try_telnet(node_ip)
        #print(telnet_result)
        if telnet_result == True:
            #print("  Connecting via Telnet")
            #print("  Collecting:")
            for command in collect_list:
                # Pause between iterations to avoid session rate-limit affects
                time.sleep(1)
                results[command] = telnet_collect(node_ip, command)
            for command in backup_list:
                time.sleep(1)
                results[command] = telnet_collect(node_ip, command)
            return [True, results]
        elif telnet_result == "auth_error":
            #print("  Error connecting to node, authentication errors")
            return [False, ssh_test_results]
        elif telnet_result == "connect_error":
            #print("  Error connecting to node, ssh and telnet unreachable")
            return [False, ssh_test_results]
        else:
            #print("  Error connecting to node, other errors")
            return [False, ssh_test_results]
    elif ssh_test_results == "auth_error":
        #print("  Error connecting to node, authentication errors")
        return [False, ssh_test_results]
    else:
        #print("  Error connecting to node, other errors")
        return [False, ssh_test_results]
            
def try_ssh(node_ip):
    test_ssh_socket = paramiko.SSHClient()
    test_ssh_socket.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        test_ssh_socket.connect(node_ip, username=USERNAME, password=PASSWORD)
    #except paramiko.ssh_exception.NoValidConnectionsError as connect_error:
        #return "connect_error"
    except OSError as connect_error:
        return "connect_error"
    except paramiko.ssh_exception.SSHException as connect_error:
        return "connect_error"
    except paramiko.ssh_exception.AuthenticationException as auth_error:
        try:
            test_ssh_socket.connect(node_ip, username=FALLBACK_USERNAME, password=FALLBACK_PASSWORD)
        except paramiko.ssh_exception.AuthenticationException:
            return "auth_error"
    test_ssh_socket.close()
    #time.sleep(1)
    return True

def ssh_collect(node_ip, command):
    ssh_socket = paramiko.SSHClient()
    ssh_socket.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh_socket.connect(node_ip, username=USERNAME, password=PASSWORD)
    #except paramiko.ssh_exception.NoValidConnectionsError as connect_error:
    #    return connect_error
    except OSError as connect_error:
        return "connect_error"
    except paramiko.ssh_exception.SSHException as connect_error:
        return "connect_error"
    except paramiko.ssh_exception.AuthenticationException as auth_error:
        try:
            ssh_socket.connect(node_ip, username=FALLBACK_USERNAME, password=FALLBACK_PASSWORD)
        except paramiko.ssh_exception.AuthenticationException:
            return 'auth_error'
    print("    " + command)
    stdin, stdout, stderr = ssh_socket.exec_command(command)
    capture = stdout.readlines()
    # Trim off leading and trailing emtpy lines and trailing "\r\n" in each line
    #trimmed_capture = capture[2:-1]
    #stripped_capture = list(map(str.rstrip("\r\n"), capture[2:-1]))
    stripped_capture = [line.rstrip("\r\n") for line in capture[2:-1]]
    return stripped_capture

def ssh_backup(node_ip, commands):
    ssh_socket = paramiko.SSHClient()
    ssh_socket.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh_socket.connect(node_ip, username=USERNAME, password=PASSWORD)
    except OSError as connect_error:
        return "connect_error"
    except paramiko.ssh_exception.SSHException as connect_error:
        return "connect_error"
    except paramiko.ssh_exception.AuthenticationException as auth_error:
        try:
            ssh_socket.connect(node_ip, username=FALLBACK_USERNAME, password=FALLBACK_PASSWORD)
        except paramiko.ssh_exception.AuthenticationException:
            return 'auth_error'
    
    channel = ssh_socket.invoke_shell()
    captures = []
    for line in commands:
        print("    " + line.rstrip("\r\n"))
        channel.send(line)
        time.sleep(2)
        response = channel.recv(9999)
        #print(response)
        captures.append(response.decode('ascii'))
        
    #stdin, stdout, stderr = ssh_socket.exec_command(command)
    #capture = stdout.readlines()
    ## Trim off leading and trailing emtpy lines and trailing "\r\n" in each line
    ##trimmed_capture = capture[2:-1]
    ##stripped_capture = list(map(str.rstrip("\r\n"), capture[2:-1]))
    #stripped_capture = [line.rstrip("\r\n") for line in capture[2:-1]]
    #return stripped_capture
    return captures

def try_telnet(node_ip):
    return telnet_collect(node_ip, "testonly")

def telnet_collect(node_ip, command):
    try:
        tnet = telnetlib.Telnet(node_ip)
    except OSError as connect_error:
        return "connect_error"

    # Attempt standard credentials
    tnet.read_until(b"name: ")
    tnet.write(USERNAME.encode('ascii') + b"\n")
    tnet.read_until(b"assword: ")
    tnet.write(PASSWORD.encode('ascii') + b"\n")

    # Check if logged in
    loginresult = tnet.expect([b"#",b"name: "])

    # Login success
    if loginresult[0] == 0:
        # If test connection stop here, else continue w/ body
        if command == "testonly":
            tnet.close()
            return True
    # Authentication failure, try fallback credentials
    elif loginresult[0] == 1:
        tnet.write(USERNAME.encode('ascii') + b"\n")
        tnet.read_until(b"assword: ")
        tnet.write(PASSWORD.encode('ascii') + b"\n")

        secondresult = tnet.expect([b"#",b"name: "])
        # Login success with fallback credentials
        if secondresult[0] == 0:
            # If test connection stop here, else continue w/ body
            if command == "testonly":
                tnet.close()
                return True
        # Authentication failure with fallback credentials
        elif secondresult[0] == 1:
            tnet.close()
            return "auth_error"
        # Unhandled parsing error or other error
        else:
            tnet.close()
            return "script_parse_error"
    # Unhandled parsing error or other error
    else:
        tnet.close()
        return "script_parse_error"
    print("    " + command.rstrip("\r\n"))
    tnet.write(b"terminal length 0\n")
    tnet.write(command.encode('ascii') + b"\n")
    tnet.write(b"exit\n")
    capture = tnet.read_all().decode('ascii').splitlines()
    ## remove leading "term len 0"/command and trailing "exit" (and whitespace)
    trimmed_capture = capture[5:-2]
    return trimmed_capture
        
def dump_configs(collections):
    print('Saving configs to disk')
    os.mkdir(OUTPUT_PATH)
    for group in collections.keys():
        for node in collections[group].keys():
            if 'admin show run' in collections[group][node].keys():
                write_file(OUTPUT_PATH + '/' + node + '.admin.cfg', collections[group][node]['admin show run'])
            if 'show run' in collections[group][node].keys():
                write_file(OUTPUT_PATH + '/' + node + '.cfg', collections[group][node]['show run'])
            else:
                print(node + ' marked as success but nothing to write!!')



## Main

full_data = read_yaml_file(YAML_FILE_NAME)

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
        for node in full_data[group].keys():
            nodecounter += 1
            print('  Proccessing node ' + str(nodecounter) + ': ' + node)
            # results = [ True|False, Collection|ErrorString ]
            results = process_node(node, full_data[group][node])
            if results[0]:
                success_nodes[group][node] = results[1]
            else:
                failed_nodes[group][node] = results[1]
            # nodeinfo = full_data[group][node]
            # #line = group + ' - ' + node 
            # if 'OS' in nodeinfo.keys():
            #     #line += ' - ' + nodeinfo['OS']
            #     if nodeinfo['OS'] in BACKUP_COMMANDS.keys():
            #         pass
            #     else:
            #         #print(group + ' - ' + node + ' -- OS "' + nodeinfo['OS'] + '" not recognized')
            #         failed_nodes[group][node] = 'OS "' + nodeinfo['OS'] + '" not recognized'
            # else:
            #     #print(group + ' - ' + node + ' -- No OS Listed')
            #     failed_nodes[group][node] = 'No OS Listed'
            # #print(line)

    # Skipped groups
    elif group != 'Generated':
        for node in full_data[group].keys():
            if group in skipped_groups.keys():
                skipped_groups[group] += 1
            else:
                skipped_groups[group] = 1

dump_configs(success_nodes)

print('\nCollection failed on the following nodes:')
for group in failed_nodes.keys():
    for node in failed_nodes[group].keys():
        print('  ' + node + ' - ' + failed_nodes[group][node])

#print("Fail:")
#print(failed_nodes)
#print("Success:")
#print(success_nodes.keys())

#print(success_nodes['Special Nets Nodes'])
#print('\nSkipped Groups:')
#for group in skipped_groups.keys():
#    print('  ' + group + ' (' + str(skipped_groups[group]) + ' nodes)')


#test1 = process_node('CE166-C1921', full_data['CBB Nodes']['CE166-C1921'])
#test1 = process_node('CR18-A9K', full_data['CBB Nodes']['CR18-A9K'])
#print(test1)

print('\n\n\n')

#import code
#code.interact(local=locals())gtamilse@yeti-psl:/home/jafroehl/scripts$ 
