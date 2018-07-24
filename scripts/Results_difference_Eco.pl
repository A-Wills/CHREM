#!/usr/bin/perl
# 
#====================================================================
# Results_difference_Eco.pl
# Author:    Sara Nikoofard
# Date:      June 2011
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl difference_set_name orig_set_name upgraded_set_name
#
# DESCRIPTION:
# This script determines results differences between two runs, including GHG emisssions for electricity based on monthly margin EIF


#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

# use CSV; #CSV-2 (for CSV split and join, this works best)
#use Array::Compare; #Array-Compare-1.15
#use Switch;
use XML::Simple; # to parse the XML results files
use XML::Dumper;
# use threads; #threads-1.71 (to multithread the program)
#use File::Path; #File-Path-2.04 (to create directory trees)
#use File::Copy; #(to copy files)
use Data::Dumper; # For debugging
use Storable  qw(dclone); # To create copies of arrays so that grep can do find/replace without affecting the original data
use Hash::Merge qw(merge); # To merge the results data

# CHREM modules
use lib ('./modules');
use General; # Access to general CHREM items (input and ordering)
use Results; # Subroutines for results accumulations
use Upgrade;

# Set Data Dumper to report in an ordered fashion
$Data::Dumper::Sortkeys = \&order;

# # Set merge to add and append
# Hash::Merge::specify_behavior(
# 	{
# 		'SCALAR' => {
# 			'SCALAR' => sub {$_[0] + $_[1]},
# 			'ARRAY'  => sub {[$_[0], @{$_[1]}]},
# 			'HASH'   => sub {$_[1]->{$_[0]} = undef},
# 		},
# 		'ARRAY' => {
# 			'SCALAR' => sub {[@{$_[0]}, $_[1]]},
# 			'ARRAY'  => sub {[@{$_[0]}, @{$_[1]}]},
# 			'HASH'   => sub {[@{$_[0]}, $_[1]]},
# 		},
# 		'HASH' => {
# 			'SCALAR' => sub {$_[0]->{$_[1]} = undef},
# 			'ARRAY'  => sub {[@{$_[1]}, $_[0]]},
# 			'HASH'   => sub {Hash::Merge::_merge_hashes($_[0], $_[1])},
# 		},
# 	}, 
# 	'Merge where scalars are added, and items are (pre)|(ap)pended to arrays', 
# );


#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $difference_set_name; # Initialize a variable to store the difference results set name
my $orig_set_name; # Initialize a variable to store the orig set name
my $upgraded_set_name; # Initialize a variable to store the upgraded set name

# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Results_(.+)_All.xml/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

my $list_of_upgrade;
my $upgrade_type;
my $upgrade_num_name;
my $penetration;
my $payback;	#payback period in year
my $interest;	#money interest year in percent (0-100)
my $escalation_mode;	#fuel ecalation mode (low, medium, high)
my $win_type;
#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV != 3) {die "Three arguments are required: difference_set_name orig_set_name\nPossible set_names are: @possible_set_names_print\n";};
	
	($difference_set_name, $orig_set_name, $upgraded_set_name) = @ARGV; # Shift the names
	# Check that the collated_set_name does not exist in the summary_ files as a simulated set. NOTE that this will replace a previous collation summary though
	if (defined($possible_set_names->{$difference_set_name})) {
		die "The collated set_name \"$difference_set_name\" is not unique\nPlease choose a string different than the following: @possible_set_names_print\n";
	}
	$difference_set_name = '_' . $difference_set_name; # Add and underscore to the start to support subsequent code
	
	# Cycle over these sets and verify they exist
	foreach my $set ($orig_set_name, $upgraded_set_name) {
		if (defined($possible_set_names->{$set})) { # Check to see if it is defined in the list
			$set =  '_' . $set; # Add and underscore to the start to support subsequent code
		}
		else { # An inappropriate set_name was provided so die and leave a message
			die "Set_name \"$set\" was not found\nPossible set_names are: @possible_set_names_print\n";
		};
	};
		
	# provide the upgrade list
	print "Please specify which upgrade have been applied:  \n";
	my $list_of_upgrades = {1, "Solar domestic hot water", 2, "Window area modification", 3, "Window type modification", 
			     4, "Fixed venetian blind", 5, "Fixed overhang", 6, "Phase change materials", 
			     7, "Controllabe venetian blind", 8, "Photovoltaics", 9, "BIPV/T"};
	foreach (sort keys(%{$list_of_upgrades})){
		 print "$_ : ", $list_of_upgrades->{$_}, "\t";
	}
	print "\n";
	$upgrade_type = <STDIN>;
	
	chomp ($upgrade_type);
	if ($upgrade_type !~ /^[1-9]?$/) {die "Plase provide a number between 1 and 9 \n";}
	$upgrade_num_name = &upgrade_name($upgrade_type);
	foreach my $up (values(%{$upgrade_num_name})) {
		if ($up =~ /WTM/) {
			print "Please provide window type\n";
			$win_type = <STDIN>;
			chomp ($win_type);
			unless ($win_type =~ /203|210|213|300|320|323|333/) {
				die "the window type is not in the list (203,210,213,300,320,323,333) \n";
			}
		}
	}
	# provide the penetration level
	print "Please specify the penetration level (it should be a number between 0-100) \n";
	$penetration= <STDIN>;
	chomp ($penetration);
	if ($penetration =~ /\D/ || $penetration < 0 || $penetration > 100 ) {die "The penetration level should be a number between 0-100 \n";}
	
	print "Please eneter the payback period, interest rate and fuel escalation mode(low, med or high): \n";
	$payback = <STDIN>;
	$interest = <STDIN>;
	$escalation_mode = <STDIN>;
	chomp($payback);
	chomp($interest);
	chomp($escalation_mode);
	$escalation_mode =~ tr/a-z/A-Z/;
	if ($payback<= 0) {die "the payeback period should be a positive number \n"};
	if ($interest<0 || $interest>100) {die "the rate should be between 0 and 100 \n"};
	if ($escalation_mode !~ /low|high|med/i) {die "the escalation mode can be low, high or med(medium) \n"};
};

#--------------------------------------------------------------------
# Difference
#--------------------------------------------------------------------
DIFFERENCE: {
	# Create a file for the xml results
	my $xml_dump;
	$xml_dump = new XML::Dumper;
	
	# Declare storage of the results
	my $results_all = {};
	
	# Readin the original set and store it at 'orig'
	my $filename = '../summary_files/Results' . $orig_set_name . '_All.xml';
	$results_all->{'orig'} = $xml_dump->xml2pl($filename);
	print "Finished reading in $orig_set_name\n";
	# Readin the upgraded set and store it at 'upgraded'
	$filename = '../summary_files/Results' . $upgraded_set_name . '_All.xml';
	$results_all->{'upgraded'} = $xml_dump->xml2pl($filename);
	print "Finished reading in $upgraded_set_name\n";

	# Read in the GHG multipliers file
	my $ghg_file;
	# Check for existance as this script could be called from two different directories
	if (-e '../../../keys/GHG_key.xml') {$ghg_file = '../../../keys/GHG_key.xml'}
	elsif (-e '../keys/GHG_key.xml') {$ghg_file = '../keys/GHG_key.xml'}
	# Read in the file
	my $GHG = XMLin($ghg_file);

	# Remove the 'en_src' field from the GHG information as that is all we need
	my $en_srcs = $GHG->{'en_src'};

	# Cycle over the UPGRADED file and compare the differences with original file
	foreach my $region (keys(%{$results_all->{'upgraded'}->{'house_names'}})) { # By region
		foreach my $province (keys(%{$results_all->{'upgraded'}->{'house_names'}->{$region}})) { # By province
			foreach my $hse_type (keys(%{$results_all->{'upgraded'}->{'house_names'}->{$region}->{$province}})) { # By house type
				foreach my $house (@{$results_all->{'upgraded'}->{'house_names'}->{$region}->{$province}->{$hse_type}}) { # Cycle over each listed house
					# Check to see that the upgraded house has an original house counterpart - if not note it
					if (defined($results_all->{'orig'}->{'house_results'}->{$house})) {
						# Create a list of fields to compare - draw from both the original house and the upgraded house (e.g. if fuel switching occurred the change in original fuel (not zero) will not be accounted for if we only cycled over the upgraded house)
						my $fields = {}; # Create a hash to store fields
						@{$fields}{keys(%{$results_all->{'upgraded'}->{'house_results'}->{$house}})} = undef; # Store all fields from the upgraded house
						@{$fields}{keys(%{$results_all->{'orig'}->{'house_results'}->{$house}})} = undef; # Store fields of the orig house. Any new fields will be added and identical ones will be replaced. This way there are no duplicates.
						
						# Cycle over the results for this house and do the comparison
						foreach my $field (keys(%{$fields})) {
							# For energy and quantity, just calculate the annual difference
							if ($field =~ /(energy|quantity)\/integrated$/) {
								# Determine the values of the upgaded and orig - if none exists then set to zero.
								my ($orig, $upgraded) = (0, 0);
								if (defined($results_all->{'orig'}->{'house_results'}->{$house}->{$field})) {$orig = $results_all->{'orig'}->{'house_results'}->{$house}->{$field};};
								if (defined($results_all->{'upgraded'}->{'house_results'}->{$house}->{$field})) {$upgraded = $results_all->{'upgraded'}->{'house_results'}->{$house}->{$field};};
								# Subtract the original from the upgraded to get the difference (negative means lowered consumption or emissions)
								$results_all->{'difference'}->{'house_results'}->{$house}->{$field} = $upgraded - $orig;
								# Store the parameter units and set the indicator. Again we need to pull from where the value actually exists so check if defined in orig or upgraded house
								if (defined($results_all->{'upgraded'}->{'parameter'}->{$field})) {
									$results_all->{'difference'}->{'parameter'}->{$field} = $results_all->{'upgraded'}->{'parameter'}->{$field};
								}
								else {
									$results_all->{'difference'}->{'parameter'}->{$field} = $results_all->{'orig'}->{'parameter'}->{$field};
								};
							};
							# For electricity calculate the period differences (this includes monthly and annual)
							if ($field =~ /electricity\/quantity\/integrated$/) {
							
								my $periods = {}; # Create a hash to store periods
								@{$periods}{keys(%{$results_all->{'upgraded'}->{'house_results_electricity'}->{$house}->{$field}})} = undef; # Store all periods from the upgraded house
								@{$periods}{keys(%{$results_all->{'orig'}->{'house_results_electricity'}->{$house}->{$field}})} = undef; # Store periods of the orig house. Any new fields will be added and identical ones will be replaced. This way there are no duplicates.
								foreach my $period (keys(%{$periods})) {
									my ($orig, $upgraded) = (0, 0);
									if (defined($results_all->{'orig'}->{'house_results_electricity'}->{$house}->{$field}->{$period})) {$orig = $results_all->{'orig'}->{'house_results_electricity'}->{$house}->{$field}->{$period};};
									if (defined($results_all->{'upgraded'}->{'house_results_electricity'}->{$house}->{$field}->{$period})) {$upgraded = $results_all->{'upgraded'}->{'house_results_electricity'}->{$house}->{$field}->{$period};};
									
									$results_all->{'difference'}->{'house_results_electricity'}->{$house}->{$field}->{$period} = $upgraded - $orig;
								};
							};
						};
					
					# Store the sim_period and push the name of the house onto the list for the difference group
						$results_all->{'difference'}->{'house_results'}->{$house}->{'sim_period'} = dclone($results_all->{'upgraded'}->{'house_results'}->{$house}->{'sim_period'});
						push(@{$results_all->{'difference'}->{'house_names'}->{$region}->{$province}->{$hse_type}}, $house);
					}
					# If No original house was available then note this occurance
					else {
						push(@{$results_all->{'difference'}->{'house_names_bad'}->{$region}->{$province}->{$hse_type}}, $house);
					};
				};
			};
		};
	};
	print "Completed the difference calculations on energy and quantity\n";
	&GHG_conversion_difference($results_all);

	print "Completed the GHG calculations\n";

	&Economic_analysis($results_all, $payback, $interest, $escalation_mode);

	print "Completed the Price calculations \n";

	# Call the remaining results printout and pass the results_all
	&print_results_out_difference_ECO ($results_all, $difference_set_name, $upgrade_num_name, $win_type, $penetration,  $payback, $interest, $escalation_mode);

	

# 	print Dumper $results_all;
};

