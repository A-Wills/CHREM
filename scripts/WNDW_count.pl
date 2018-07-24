#!/usr/bin/perl
# 
#====================================================================
# WNDW_count.pl
# Author:    Sara Nikoofard
# Date:      Dec 2011
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name] 
#
# DESCRIPTION:
# This script returns the window area, number of window and houses modeled for each set name.

#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

use CSV;		#CSV-2 (for CSV split and join, this works best)
#use Array::Compare;	#Array-Compare-1.15
use Switch;
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

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Hse_Gen_(.+)_Issues.txt/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

my %provinces = ("NF", "NEWFOUNDLAND", "NS", "NOVA SCOTIA" , "PE", "PRINCE EDWARD ISLAND", "NB", "NEW BRUNSWICK", "QC", "QUEBEC", "OT", "ONTARIO", "MB", "MANITOBA", "SK", "SASKATCHEWAN", "AB", "ALBERTA" , "BC", "BRITISH COLUMBIA");

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 3) {die "A minimum Four arguments are required: house_types regions set_name \nPossible set_names are: @possible_set_names_print\n";};
	
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV), shift (@ARGV));

	# Verify the provided set_name
	if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
		$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
	}
	else { # An inappropriate set_name was provided so die and leave a message
		die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
	};
	
};

#--------------------------------------------------------------------
# Identify the house folders for counting the windows
#--------------------------------------------------------------------
my $count_houses;
my $count_windows;
my @sides = qw (front back right left);
foreach my $hse_type (&array_order(values %{$hse_types})) {		#each house type
	foreach my $region (&array_order(values %{$regions})) {		#each region
		push (my @dirs, <../$hse_type$set_name/$region/*>);	#read all hse directories and store them in the array
# 		print Dumper @dirs;
		RECORD:foreach my $dir (@dirs) {
			my $file = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region;
			my $ext = '.csv';
			my $CSDDRD_FILE;
			open ($CSDDRD_FILE, '<', $file . $ext) or die ("Can't open datafile: $file$ext");	# open readable file
			my $CSDDRD;
			$dir =~ s/..\/.+\/.+\/(\w{10})/$1/;
			while ($CSDDRD = &one_data_line($CSDDRD_FILE, $CSDDRD)) {
				if ($CSDDRD->{'file_name'} =~ /^$dir/){
					switch ($CSDDRD->{'HOT2XP_PROVINCE_NAME'}) {
						case ("NOVA SCOTIA") {
							$count_houses->{$hse_type}->{'NS'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'NS'}->{'area'} = $count_windows->{$hse_type}->{'NS'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'NS'}->{'number'} = $count_windows->{$hse_type}->{'NS'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("NEWFOUNDLAND") {
							$count_houses->{$hse_type}->{'NF'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'NF'}->{'area'} = $count_windows->{$hse_type}->{'NF'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'NF'}->{'number'} = $count_windows->{$hse_type}->{'NF'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("PRINCE EDWARD ISLAND") {
							$count_houses->{$hse_type}->{'PE'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'PE'}->{'area'} = $count_windows->{$hse_type}->{'PE'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'PE'}->{'number'} = $count_windows->{$hse_type}->{'PE'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("NEW BRUNSWICK") {
							$count_houses->{$hse_type}->{'NB'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'NB'}->{'area'} = $count_windows->{$hse_type}->{'NB'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'NB'}->{'number'} = $count_windows->{$hse_type}->{'NB'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("QUEBEC") {
							$count_houses->{$hse_type}->{'QC'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'QC'}->{'area'} = $count_windows->{$hse_type}->{'QC'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'QC'}->{'number'} = $count_windows->{$hse_type}->{'QC'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("ONTARIO") {
							$count_houses->{$hse_type}->{'OT'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'OT'}->{'area'} = $count_windows->{$hse_type}->{'OT'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'OT'}->{'number'} = $count_windows->{$hse_type}->{'OT'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("MANITOBA") {
							$count_houses->{$hse_type}->{'MB'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'MB'}->{'area'} = $count_windows->{$hse_type}->{'MB'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'MB'}->{'number'} = $count_windows->{$hse_type}->{'MB'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("SASKATCHEWAN") {
							$count_houses->{$hse_type}->{'SK'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'SK'}->{'area'} = $count_windows->{$hse_type}->{'SK'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'SK'}->{'number'} = $count_windows->{$hse_type}->{'SK'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("ALBERTA") {
							$count_houses->{$hse_type}->{'AB'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'AB'}->{'area'} = $count_windows->{$hse_type}->{'AB'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'AB'}->{'number'} = $count_windows->{$hse_type}->{'AB'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
						case ("BRITISH COLUMBIA") {
							$count_houses->{$hse_type}->{'BC'}++;
							foreach my $sid (@sides){
								$count_windows->{$hse_type}->{'BC'}->{'area'} = $count_windows->{$hse_type}->{'BC'}->{'area'} + $CSDDRD->{'wndw_area_'.$sid};
								$count_windows->{$hse_type}->{'BC'}->{'number'} = $count_windows->{$hse_type}->{'BC'}->{'number'} + $CSDDRD->{'wndw_count_'.$sid};
							}
						}
					}
					next RECORD;
				}
				
			}
			close ($CSDDRD_FILE);
		};

			
	};
};

my $file = '../summary_files/Count_WNDW_set'.$set_name;
my $ext = '.csv';
open (my $COUNT, '>', $file.$ext);
my @header = ('*header', 'hse_type', 'province', 'houses_modeled', 'Num_WNDW', 'AREA_WNDW ');
print $COUNT CSVjoin (@header) . "\n";

foreach my $hse_type (&array_order(values %{$hse_types})) {
	if (defined ($hse_type)){
		foreach my $prov (keys (%provinces)){
			if (defined ($count_houses->{$hse_type}->{$prov})) {
				my @line = ('*data', $hse_type, $provinces{$prov},$count_houses->{$hse_type}->{$prov},$count_windows->{$hse_type}->{$prov}->{'number'}, $count_windows->{$hse_type}->{$prov}->{'area'});
				print $COUNT CSVjoin (@line) . "\n";
			}
		}
	}
}
close ($COUNT);
# print Dumper $count_houses;
# print Dumper $count_windows;
