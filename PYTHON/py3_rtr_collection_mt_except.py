#!/usr/bin/python3

from builtins import input
from getpass import getpass
from pprint import pprint
from netmiko import ConnectHandler
from time import time
import datetime
from multiprocessing.dummy import Pool as ThreadPool
from netmiko.ssh_exception import NetMikoTimeoutException
from paramiko.ssh_exception import SSHException
from netmiko.ssh_exception import AuthenticationException

#---- Create function to read Devices File called 'devices-file' -----#

def read_devices( devices_filename ):

   devices = {}

   with open( devices_filename ) as devices_file:

       for device_line in devices_file:

          device_info = device_line.strip().split(',')    #extract device info from line

          device = {'name': device_info[0],
                    'ipaddr': device_info[1],
                    'type': device_info[2]}     #create a dictionary of device objects

          devices[device['ipaddr']] = device   #store device in devices dictionary

   print('\n----- Devices List -------')
   pprint( devices )

   return devices

#==================================================================================================

def config_worker( device ):

   #----- Identify the Device Type -----
   if device['type'] == 'cisco_ios': device_type = 'cisco_ios'
   else:                             device_type = 'cisco_xr'

   print('\n----- Connecting to device {0}, device {1}'.format( device['name'], device['ipaddr'] ))

   #----- Connect to the Device 

   try:
        session = ConnectHandler( device_type=device_type, ip=device['ipaddr'], username=username, password=password )
        print(('Trying to connect to device ' + device['ipaddr']))
   except (AuthenticationException):
        print(('Authentication Failure: ' + device['ipaddr']))
   except (NetMikoTimeoutException):
        print(('Timeout to device: ' + device['ipaddr']))
   except (EOFError):
        print(('End of file while attempting device ' + device['ipaddr']))
   except Exception as unknown_error:
        print(('Some other error: ' + unknown_error))

   #------ Use Netmiko to send CLI command to both routers

   currentDT = datetime.datetime.now()

   config_filename = device['name']+ '-' + currentDT.strftime("%Y-%m-%d-%H-%M-%S") + '.txt'

   for cmd in cmds:
        #---- Use CLI command to get configuration data from device
        print('----- Getting Configuration from' + device['name'])
        config_data = session.send_command(cmd)
        print(config_data)

        #------ Write out config information to a file

        with open( config_filename, 'a') as config_out:
            config_out.write( config_data )

   session.disconnect()

   return

#==================================================================================================
# -----------    MAIN: Get Configuration --------------
#==================================================================================================

# Get router login username and password from the user

username = input('Enter your SSH username: ')
password = getpass()

# Read the devices-file list to create device dictionary

devices = read_devices( 'devices-file' )

#Read the shcmds.txt file to get list of show commands to collect

with open('shcmds.txt') as f:
    cmds = f.read().splitlines()


# Prompt user for number of Threads to create for Multithreading
num_threads_str = input( '\nNumber of threads (5): ' ) or '5'
num_threads = int( num_threads_str )

# Create list for passing to config_worker function
config_params_list = []
for ipaddr,device in list(devices.items()):
   config_params_list.append( ( device ) )

start_time = time()

# Creating threadpool and launching config_worker threads

print('Creating threadpool, launching get config threads\n')
threads = ThreadPool( num_threads )
results = threads.map( config_worker, config_params_list )

threads.close()
threads.join()

print('\n---- End get config sequential, elapsed time=', time()-start_time)
