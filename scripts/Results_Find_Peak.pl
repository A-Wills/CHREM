#!/usr/bin/perl
# 
#====================================================================
# Results2.pl
# Author:    Lukas Swan
# Date:      Apr 2010
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] set_name [cores/start_core/end_core]
# Use start and end cores to evenly divide the houses between two machines (e.g. QC2 would be [16/9/16]) [house names that are the only desired]
#
# DESCRIPTION:
# This script aquires results


#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

use CSV; #CSV-2 (for CSV split and join, this works best)
#use Array::Compare; #Array-Compare-1.15
#use Switch;
use XML::Simple; # to parse the XML results files
use XML::Dumper;
#use File::Path; #File-Path-2.04 (to create directory trees)
#use File::Copy; #(to copy files)
use Data::Dumper; # For debugging
use Storable  qw(dclone); # To create copies of arrays so that grep can do find/replace without affecting the original data
use Hash::Merge qw(merge); # To merge the results data

# CHREM modules
use lib ('./modules');
use General; # Access to general CHREM items (input and ordering)
use Results; # Subroutines for results accumulations
use XML_reporting; # Sorting functionality for the house xml results reporting

# Set Data Dumper to report in an ordered fashion
$Data::Dumper::Sortkeys = \&order;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $hse_types; # declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions; # declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name; # store the results set name
my $timestep; # simulations time step [min]
my @houses_desired; # declare an array to store the house names or part of to look
my @folders;	#declare an array to store the path to each hse which will be simulated

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Sim_(.+)_Sim-Status.+/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 4) {die "A minimum four arguments are required: house_types regions set_name timestep [house names]\nPossible set_names are: @possible_set_names_print\n";};
	
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift(@ARGV), shift(@ARGV), shift(@ARGV));

	# Verify the provided set_name
	if (defined($possible_set_names->{$set_name})) { # Check to see if it is defined in the list
		$set_name =  '_' . $set_name; # Add and underscore to the start to support subsequent code
	}
	else { # An inappropriate set_name was provided so die and leave a message
		die "Set_name \"$set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
	};
    
    $timestep = shift;

	# Provide support to only simulate some houses
	@houses_desired = @ARGV;
	# In case no houses were provided, match everything
	if (@houses_desired == 0) {@houses_desired = '.'};
	
	my $localtime = localtime(time);
	print "Set: $set_name; Start Time: $localtime\n";
};
#--------------------------------------------------------------------
# Declare outputs
#--------------------------------------------------------------------
my $nRecs=525600/$timestep;
my $StepDay = 1440/$timestep;
my @NetLoad = (0) x $nRecs;   # Array holding the net community electrical load [kW]
my @DailyPeak; # Array holding the daily community electrical peak [kW]
#--------------------------------------------------------------------
# Identify the house folders for results acquisition
#--------------------------------------------------------------------

foreach my $hse_type (&array_order(values %{$hse_types})) {		#each house type
	foreach my $region (&array_order(values %{$regions})) {		#each region
		push (my @dirs, <../$hse_type$set_name/$region/*>);	#read all hse directories and store them in the array
# 		print Dumper @dirs;
		CHECK_FOLDER: foreach my $dir (@dirs) {
			# cycle through the desired house names to see if this house matches. If so continue the house build
					push (@folders, $dir);
					next CHECK_FOLDER;
		};
	};
};

#--------------------------------------------------------------------
# Delete old summary files
#--------------------------------------------------------------------
foreach my $file (<../summary_files/*>) { # Loop over the files
	my $check = 'Community_Load' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
};

#--------------------------------------------------------------------
# Multithread to acquire the xml results faster, merge then print them out to csv files
#--------------------------------------------------------------------
# Cycle over each folder
FOLDER: foreach my $folder (@folders) {
    print "Processing $folder\n";

    my ($hse_type, $region, $hse_name) = ($folder =~ /^\.\.\/(\d-\w{2}).+\/(\d-\w{2})\/(.+)$/);
    my $file = $folder . "/out.csv";
    my @Tdata = ();

    # Examine the directory and see if a results file (house_name.xml) exists. If it does than we had a successful simulation. If it does not, go on to the next house.
	unless (grep(/out.xml$/, <$folder/*>)) {
		# Store the house name so we no it is bad - with a note
        print "Problem with $hse_name out.csv\n";
		next FOLDER;  # Jump to the next house if it does not return a true.
	};
    
    # Open the timestep file
    my $iPass=0;
    open(my $data, '<', $file) or die "Could not open '$file' $!\n";

    while (my $line = <$data>) {
        if ($iPass < 1) { # Skip the header
            $iPass++;
        } else {
            chomp $line;
            my @fields = split "," , $line;
            my $sum = ($fields[0]-$fields[1])/1000; # Negative=import, Positive=export [kW]
            $NetLoad[$iPass-1]=$NetLoad[$iPass-1]+$sum;
            $iPass++;
        };
    };

}; # END of FOLDER

#--------------------------------------------------------------------
# Find the peak
#--------------------------------------------------------------------
my $cDay=0; # Counter for timesteps in the day
my $cLoop=0;    # Loop counter
my $dayMAX=0; # Hold the peak load for the day
foreach my $period (@NetLoad) {
    if($cDay==$StepDay) { # First record of new day
        push(@DailyPeak, $dayMAX);
        $cDay=0;
        $dayMAX=0;
    };
    
    # Find the daily peak
    if($period<$dayMAX) {$dayMAX=$period};

    $cDay++; # New timestep
    $cLoop++;
    
    # If this is the last timestep, record peak
    if($cLoop>$#NetLoad) {push(@DailyPeak, $dayMAX)};
};

#--------------------------------------------------------------------
# Print out data
#--------------------------------------------------------------------

my $OUT = "../summary_files/Community_Load$set_name" . ".csv";
my @ResOut=("Export [kW],Daily Peaks [kW],\n");

my $iCount=0;
foreach my $m (@NetLoad) {
    
    if($iCount >= $#DailyPeak) {
        push(@ResOut, "$m\n");
    } else {
        push(@ResOut, "$m,$DailyPeak[$iCount]\n");
    };
    
    $iCount++;
};

open (my $FILE, '>', $OUT) or die ("\n\nERROR: can't open $OUT\n");
print $FILE @ResOut;
close($FILE);
	
my $localtime = localtime(time);
print "Set: $set_name; End Time: $localtime\n";
