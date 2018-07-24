#!/usr/bin/perl
# 
#====================================================================
# Sim_Control_clus.pl
# Author:    Sara Nikoofard
# Date:      Dec 2011
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name] 
# Use start and end cores to evenly divide the houses between two machines (e.g. QC2 would be [16/9/16])
#
# DESCRIPTION:
# This script divides the desired house simulations up to match the CPU cores 
# and then intiates the simulations. The script reads the directories based on 
# the house type (SD or DR) and # region (AT, QC, OT, PR, BC). Which types and 
# regions are generated is specified at the beginning of the script to allow for 
# partial generation. Note that the beginning of a house folder name may be specified
# to limit the simulation to only matching houses
# 
# The script adds the list of houses to an array and then divides the array by the
# total number of CPU cores used for simulation. It then writes text files with 
# the paths for each house that the simulator will follow and then simulate.
# 
# The script then calls another simulating script using the nohup command to account
# for chdir() and background simulation requirements as detailed below. This script 
# quickly ends, leaving the appropriate simulating scripts running.


#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

#use CSV;		#CSV-2 (for CSV split and join, this works best)
#use Array::Compare;	#Array-Compare-1.15
#use Switch;
#use threads;		#threads-1.71 (to multithread the program)
#use File::Path;	#File-Path-2.04 (to create directory trees)
#use File::Copy;	#(to copy the input.xml file)
use Data::Dumper;

# CHREM modules
use lib ('./modules');
use General;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name;
my @houses_desired; # declare an array to store the house names or part of to look
my $old_set_name;
# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Hse_Gen_(.+)_Issues.txt/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 3) {die "A minimum Three arguments are required: house_types regions set_name [house names]\nPossible set_names are: @possible_set_names_print\n";};
	
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV), shift (@ARGV));

	# Verify the provided set_name
	if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
		$old_set_name = $set_name;
		$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
	}
	else { # An inappropriate set_name was provided so die and leave a message
		die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
	};
	
	# Provide support to only simulate some houses
	@houses_desired = @ARGV;
	# In case no houses were provided, match everything
	if (@houses_desired == 0) {@houses_desired = '.'};
	
};

#--------------------------------------------------------------------
# Identify the house folders for simulation
#--------------------------------------------------------------------
my @folders;	#declare an array to store the path to each hse which will be simulated

foreach my $hse_type (&array_order(values %{$hse_types})) {		#each house type
	foreach my $region (&array_order(values %{$regions})) {		#each region
		push (my @dirs, <../$hse_type$set_name/$region/*>);	#read all hse directories and store them in the array
# 		print Dumper @dirs;
		CHECK_FOLDER: foreach my $dir (@dirs) {
			# cycle through the desired house names to see if this house matches. If so continue the house build
			foreach my $desired (@houses_desired) {
				# it matches, so set the flag
				if ($dir =~ /\/$desired/) {
					push (@folders, $dir);
					next CHECK_FOLDER;
				};
			};
		};
	};
};

# print Dumper @folders;

#--------------------------------------------------------------------
# Delete old simulation summary files
#--------------------------------------------------------------------
foreach my $file (<../summary_files/*>) { # Loop over the files
	my $check = 'Sim' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
};

#--------------------------------------------------------------------
# Generate and print lists of directory paths for each core to simulate
#--------------------------------------------------------------------
SIMULATION_LIST: {
	my $num = $#folders;
	my $file = '../summary_files/Sim' . $set_name . '_House-List.csv';
	open (HSE_LIST, '>', $file) or die ("can't open $file");	#open the file to print the list for the core
	for (my $element = 0; $element<=$num; $element++) {
		if (defined($folders[$element])) {
			print HSE_LIST "$folders[$element]\n";	#print the hse path to the list
		};
	}
	close HSE_LIST;	
};

#-----------------------------------------------------------------------
# Generate the bash file for simulation
#-----------------------------------------------------------------------
FILE_GENERTAION: {
	my $num = $#folders+1;
	# open the simulation file taht will be qiven in qsub
	my $out = '../scripts/batch_sim.sh';
	open (my $FILEOUT, '>', $out) or die ("can't open $out");
	print $FILEOUT "# Use this shell \n";
	print $FILEOUT "#\$ -S /bin/bash \n";
	print $FILEOUT "# Run from current directory \n";
	print $FILEOUT "#\$ -cwd \n";
	print $FILEOUT "# Name that appears in qstat \n";
	print $FILEOUT "#\$ -N $old_set_name \n";
	print $FILEOUT "# Memory allocated \n";
	print $FILEOUT "#\$ -l h_vmem=2G \n";
	print $FILEOUT "# Run time for each simulation \n";
	print $FILEOUT "#\$ -l h_rt=00:45:00 \n";
	print $FILEOUT "# mail when job ends \n";
	print $FILEOUT "#\$ -m e \n";
	print $FILEOUT "#\$ -M s.nikoofard\@dal.ca \n";
	print $FILEOUT "# Run $num times with SGE_TASK_ID going \n";
	print $FILEOUT "# From 1 to $num, stepping by 1 \n";
	print $FILEOUT "#\$ -t 1:$num:1 \n";
	print $FILEOUT "./Core_Sim_clus.pl \$SGE_TASK_ID $set_name \n";
	print $FILEOUT "rm -f $old_set_name.*";
	close $FILEOUT;
	chmod 0755, $out;
};
