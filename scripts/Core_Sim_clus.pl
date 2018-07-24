#!/usr/bin/perl
# 
#====================================================================
# Core_Sim_clus.pl
# Author:    Sara Nikoofard
# Date:      Dec 2011
# Copyright: Dalhousie University
#
# DESCRIPTION:
# This script is called from the simulation control script (Sim_Control_xx.pl).
# It reads the supplied core number arguement and opens the appropriate file 
# that lists the house directories to be simulated by that core.
# 
# The script determined the house name, changes directories to the appropriate 
# folder (to get RES and XML files right) and then simulates using bps and the 
# automation arguements.

#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

use local::lib;
use CSV;		#CSV-2 (for CSV split and join, this works best)
#use Array::Compare;	#Array-Compare-1.15
#use Switch;
#use threads;		#threads-1.71 (to multithread the program)
#use File::Path;	#File-Path-2.04 (to create directory trees)
use Cwd;		#(to determine current working directory)
use Data::Dumper;
use XML::Simple;	# to parse the XML
# use Storable  qw(dclone);

use lib ('./modules');
use General;
use XML_reporting;

$Data::Dumper::Sortkeys = \&order;

#--------------------------------------------------------------------
# Read the input arguments to determine which set of houses to simulate
#--------------------------------------------------------------------
my ($file_num, $set_name) = @ARGV; #store input folder arguments
$file_num = $file_num -1;

#--------------------------------------------------------------------
# Declare time and simulation count variables and open the appropriate file with the hse directories to be simulated
#--------------------------------------------------------------------
my $start_time= localtime(); # Note the start time of the file generation
my $simulations = 0; # Set a variable to count the simulations

my @folders; # Storage for the folders to be simulated

# Open and Read the Houses that will be simulated
{	
	
	my $file =  '../summary_files/Sim' . $set_name . '_House-List.csv';
	my $file_name = '../summary_files/'.$set_name.'.csv';
	if (-e $file) {
		open (my $FILE, "<", "$file"); # Open a readable file
		@folders = <$FILE>; # Slurp in the entire file (each line is an element in the array)
		close ($FILE);
	}
	elsif (-e $file_name) {
		open (my $FILE, "<", "$file_name"); # Open a readable file
		@folders = <$FILE>; # Slurp in the entire file (each line is an element in the array)
		close ($FILE);
	}
	else { die ("can't open $file or $file_name! \n");}
}

#--------------------------------------------------------------------
# Perform a simulation of each house in the directory list
#--------------------------------------------------------------------
SIMULATION: {

	# Begin a file to store the simulation status information
	my $file = '../summary_files/Sim' . $set_name . '_Sim-Status';
	my $ext = '.txt'; # Extention
	my $FILE;
	if ($file_num == 0) {
		open ($FILE, ">", "$file$ext") or die ("can't open $file$ext\n"); # Open a writeable file
# 	
	# Print some status information at the top of the file
		print $FILE CSVjoin('*mdl_start_time', time) . "\n"; # Model start time
		print $FILE CSVjoin('*header', qw(folder ish_status bps_status sim_status sim_numbers sim_end_time)) . "\n"; # Header for the data fields
	}
	elsif ($file_num > 0) {
		open ($FILE, ">>", "$file$ext") or die ("can't open $file$ext\n"); # Open a writeable file
		
	}	
	# Declarations to hold house information
# 	my @good_houses; # Array to hold the directories of the good houses
# 	my @bad_houses; # Array to hold the directories of the bad houses
# 	my $house_count = 0; # Index of houses so we know how far along we are
	my $folder;
	$folder = $folders[$file_num];
	print $FILE "*data,"; # Start storage of the simulation status for this house
	
	# Folder information
	$folder = rm_EOL_and_trim($folder); # Clean up the folder name
	print $FILE "$folder,"; # Write the folder name to the status
	chdir($folder); # Change to the appropriate directory for simulation. Sim has to be in directory for xml output

	# House name and CFG file to determine ish zones
	my ($hse_type, $region, $house_name) = ($folder =~ /^\.\.\/(.{4}).+\/(.+)\/(.+)(\/$|$)/); # Determine the house name which is the last 10 digits (note that a check is done for an extra slash) 		
	my $coordinates = {'hse_type' => $hse_type, 'region' => $region, 'file_name' => $house_name};
	
	# Prior to simulation, delete any existing files
	foreach my $ext qw(ish bps energy_balance temperature summary secondary dictionary xml xml.orig cfg.h3k csv mfr elr res shd shda) {
		unlink "./$house_name.$ext"; # Unlink (delete) the previous file
	};
	my $filename; # Initialize an extention name

	# Cycle over the CFG file and store information
	my $cfg = $house_name .'.cfg';
	open (my $CFG, '<', $cfg) or die ("\n\nERROR: can't open $cfg\n"); # Open the cfg file to check for isi
	my @cfg = &rm_EOL_and_trim(<$CFG>);
	close $CFG; # We are done with the CFG file

	# BEGIN SHADING ANALYSIS EFFORTS
	# Cycle over the CFG file using the grep command and look for *isi tags - when one is found, store the zone name
	my @isi_zones = grep (s/^\*isi \.\/.+\.(bsmt|main_\d|PV)\.shd$/$1/, @cfg);
	print $FILE "ish "; # Denote that ish is about to begin

	$filename = $house_name .'.ish';
	# Cycle over the isi zones and do the ish shading analysis on that zone
	foreach my $isi_zone (@isi_zones) {
		system ("ish -mode text -file $cfg -zone $isi_zone -act update_silent >> $filename");	# call the ish shading and insolation analyzer with variables to automate the analysis. Note that ">>" is used so as to append each zone in the log file
	};

	# BEGIN THE BPS SIMULATION
	print $FILE "- Complete,bps "; # Denote that ish is complete and that bps is about to begin
	$filename = $house_name .'.bps';
	system ("bps -mode text -file $cfg -p sim_presets silent >> $filename");	#call the bps simulator with arguements to automate it
		

		
	# Check the bps file for any errors
	open (my $BPS, '<', $filename) or die ("\n\nERROR: can't open $filename\n");	# Open the bps file to check for errors

	my $warnings = {}; # Storage for the warnings
	my $previous = ''; # Recall the previous line so we know if we are in the timestepping or not
	
	my $sim_period = {};
		
	# Cycle over the bps file lines
	foreach my $line (&rm_EOL_and_trim(<$BPS>)) {
		
		# Check to see if there are any startup file scan warnings
		if ($line =~ /^No\. of warnings\s+:\s+(\d+)$/) { # Remember how many there are
			foreach my $warning (1..$1) { # Cycle over the number of warnings and store in an array - this is to be functional with the method below for other warning types
				push(@{$warnings->{'Startup_Scan'}}, 1);
			};
		}
			
		elsif ($line =~ /^period: \w{3}-(\d{2})-(\w{3}).{9}\w{3}-(\d{2})-(\w{3}).{6}$/) {
			@{$sim_period->{'begin'}}{qw(month day)} = ($2, $1);
			@{$sim_period->{'end'}}{qw(month day)} = ($4, $3);
		}
			
		# Check to see if we are in the timestep area. If we are then the only allowable line types are those that start with a percentage complete. Everything else is an error. Also check for WARNING, ERROR, etc. in lines.
		elsif ($previous =~ /^Simulation has now commenced|^\d+ %\s+complete/ && $line !~ /^\d+ %\s+complete|^Simulation cpu runtime/ || $line =~ /WARNING|ERROR|FAILURE/i) {
			my $warning = $line; # A new copy for use below
			$warning =~ s/^(.{7}).+$/$1/; # Only store the first 7 digits to keep the warning short and to cover repeats
			push(@{$warnings->{$warning}}, $line); # Push the complete line into the storage at the warning point based on the 7 digits. This is so MZELWE warning will only have 1 key, but will show up the number of times it was warned and perhaps later we could use it to look up what the values were.
		}
		# Otherwise just store the line
		else {$previous = $line};
	};
# 		print Dumper $sim_period;

	close $BPS; # We are done with the CFG file
# 		
	# If there are no warnings, then say complete
	if (keys %{$warnings} == 0) {
		print $FILE "- Complete,"; # Denote that bps is complete
	}
	# If there are warning, then cycle over them, and print 
	else {
		print $FILE "- Warnings";
		foreach my $key (@{&order($warnings)}) { # Cycle over the warnings
			print $FILE ":'$key'=" . @{$warnings->{$key}}; # Print out the start of the warning and the number of times it was encountered
		};
		print $FILE ",";
	}; # Denote that bps has errors

	# Rename the XML reporting files with the house name. If this is true then it may be treated as a proxy for a successful simulation
	if (rename ("out.dictionary", "$house_name.dictionary")) { # If this is true then the simulation was successful (for the most part this is true)
		
		# Cycle over other common XML reporting files and rename these
		foreach my $ext ('csv', 'summary', 'xml') {
			rename ("out.$ext", "$house_name.$ext");
		};

		# Examine the cfg file and create a key of zone numbers to zone names
		my @zones = grep (s/^\*geo \.\/.+\.(\w+)\.geo$/$1/, @cfg); # Find all *.geo files and filter the zone name from it
		my $zone_name_num; # Intialize a storage of zone name value at zone number key
		foreach my $element (0..$#zones) { # Cycle over the array of zones by element number so it can be used
			$zone_name_num->{$zones[$element]} = $element + 1; # key is zone name, value = index + 1
		};
			
		my @province = grep (s/^\#PROVINCE (.+)$/$1/, @cfg);
	# 		print Dumper $zone_name_num;
			
		# Sort the xml log file, overwrite it with sorted data for later use.
		# If this fails then something is wrong.
		if (&organize_xml_log($house_name, $sim_period, $zone_name_num, $province[0], $coordinates)) {
		# 		my $summary = &summary($file);

			&zone_energy_balance($house_name, $coordinates);
				
			&zone_temperatures($house_name, $coordinates);
				
# 				&GHG_conversion($house_name, $coordinates);
				
			&secondary_consumption($house_name, $coordinates);
				
			print $FILE "OK,"; # Denote that the simulation is OK
# 				push (@good_houses, $folder); # Store the folder as a good house
			print $FILE $file_num+1 . ','; # Denote which house this was and of how many
		}
			
		# If it failed then add it to the bad versions.
		else {
			print $FILE "BAD,"; # Denote that the simulation was BAD
# 				push (@bad_houses, $folder); # Store the folder as a bad house
			print $FILE $file_num+1 . ','; # Denote how many houses have been bad up to this point
		};
			
	}
		
	# The simulation was not successful
	else {
		print $FILE "BAD,"; # Denote that the simulation was BAD
# 		push (@bad_houses, $folder); # Store the folder as a bad house
		print $FILE $file_num+1 . ','; # Denote how many houses have been bad up to this point
	};

	# Print the simulation time for this house (seconds since 1970)
	print $FILE time . "\n";

	# Cycle over results files and unlink them
	foreach my $ext (qw(mfr elr res)) {
		unlink "./$house_name.$ext";
	}

		
	if ($file_num == $#folders){
		# Print some status information at the top of the file
		print $FILE CSVjoin('*mdl_end_time', time) . "\n";
	}
# 	close ($FILE);
		chdir ("../../../scripts"); # Return to the original working directory
};

#--------------------------------------------------------------------
# Do a final print of the times and simulations (discover using "tail" command on ../summary_files/sim_output_core_X.txt)
#--------------------------------------------------------------------
# my $end_time= localtime();
# print "\n\nstart time $start_time; end time $end_time; $simulations simulations\n";
