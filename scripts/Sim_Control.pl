#!/usr/bin/perl
# 
#====================================================================
# Sim_Control.pl
# Author:    Lukas Swan
# Date:      Aug 2008
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name] [cores/start_core/end_core]
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
my $cores;	# store the input core info
my @houses_desired; # declare an array to store the house names or part of to look

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Hse_Gen_(.+)_Issues.txt/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 4) {die "A minimum Four arguments are required: house_types regions set_name core_information [house names]\nPossible set_names are: @possible_set_names_print\n";};
	
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV), shift (@ARGV));

	# Verify the provided set_name
	if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
		$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
	}
	else { # An inappropriate set_name was provided so die and leave a message
		die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
	};

	# Check the cores arguement which should be three numeric values seperated by a forward-slash
	unless (shift(@ARGV) =~ /^([1-9]?[0-9])\/([1-9]?[0-9])\/([1-9]?[0-9])$/) {
		die ("CORE argument requires three Positive numeric values seperated by a \"/\": #_of_cores/low_core_#/high_core_#\n");
	};
	
	# set the core information
	# 'num' is total number of cores (if only using a single QC (quad-core) then 8, if using two QCs then 16
	# 'low' is starting core, if using two QCs then the first QC has a 1 and the second QC has a 9
	# 'high' is ending core, value is 8 or 16 depending on machine
	@{$cores}{'num', 'low', 'high'} = ($1, $2, $3);
	
	# check the core infomration for validity
	unless (
		$cores->{'num'} >= 1 &&
		($cores->{'high'} - $cores->{'low'}) >= 0 &&
		($cores->{'high'} - $cores->{'low'}) <= $cores->{'num'} &&
		$cores->{'low'} >= 1 &&
		$cores->{'high'} <= $cores->{'num'}
		) {
		die ("CORE argument numeric values are inappropriate (e.g. high_core > #_of_cores)\n");
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
				if (($dir =~ /\/$desired/) && ($dir !~ m/BCD$/)) {
					push (@folders, $dir);
					next CHECK_FOLDER;
				};
			};
		};
	};
};

# print Dumper @folders;

#--------------------------------------------------------------------
# Determine how many houses go to each core for core usage balancing
#--------------------------------------------------------------------
my $interval = int(@folders/$cores->{'num'});	#round up to the nearest integer


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
	foreach my $core (1..$cores->{'num'}) {
		my $low_element = ($core - 1) * $interval;	#hse to start this particular core at
		my $high_element = $core * $interval - 1;	#hse to end this particular core at
		if ($core == $cores->{'num'}) { $high_element = $#folders};	#if the final core then adjust to end of array to account for rounding process
		my $file = '../summary_files/Sim' . $set_name . '_House-List_Core-' . $core . '.csv';
		open (HSE_LIST, '>', $file) or die ("can't open $file");	#open the file to print the list for the core
		foreach my $element ($low_element..$high_element) {
			if (defined($folders[$element])) {
				print HSE_LIST "$folders[$element]\n";	#print the hse path to the list
			};
		}
		close HSE_LIST;		#close the particular core list
	};
};



#--------------------------------------------------------------------
# Call the simulations.
#--------------------------------------------------------------------
SIMULATION: {
	# This is done using the nohup command for two reasons:
	# 1) chdir() cannot be used with multi-threading as they all have the same 
	# current working directory. "bps" must be run in the directory to eliminate issues
	# with the res file looking in the wrong director and the xml files being generated 
	# in the top level directory
	# 2) nohup allows for the shutdown of the remote terminal and the continuation of the
	# simulation. This is very important as the simulation may take a long time. It also 
	# records all the screen output of the simulations. Note - as the simulations have 
	# been released as their own, to kill them requires that each (# of cores) perl script 
	# (Sim_Core_V1.pl) is killed and then either let the bps finish that house or kill it 
	# as well
	#--------------------------------------------------------------------

	foreach my $core ($cores->{'low'}..$cores->{'high'}) {	#simulate the appropriate list (i.e. QC2 goes from 9 to 16)
		my $file = '../summary_files/Sim' . $set_name . '_Core-Output_Core-' . $core . '.txt';
		system ("nohup ./Core_Sim.pl $core $set_name > $file &");	#call nohup of simulation program script and pass the argument $core so the program knows which set to simulate
	} 
	print "THE SIMULATION OUTPUTS FOR EACH CORE ARE LOCATED IN ../summary_files/\n";
};
