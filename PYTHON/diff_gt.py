#!/usr/bin/python

#import difflib
import sys
from difflib import Differ

file1 = open('diff_file1.txt', 'r')
file2 = open('diff_file2.txt', 'r')
FO = open('diff_result.txt', 'w')

#list1 = file1.readlines()
#list2 = file2.readlines()

#diffinst = difflib.Differ()
#difflist = list(diffinst.compare(file1.readlines(), file2.readlines()))

#for line in difflist:
#	print line

differ = Differ()
for line in differ.compare(file1.readlines(), file2.readlines()):
	print line


