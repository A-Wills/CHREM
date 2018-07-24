#!/usr/bin/perl
# 
#====================================================================
# Results_diviation.pl
# Author:    Sara Nikoofard
# Date:      may 2012
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl mean_deviation_name difference_set_name penetration_rate num_iteration  
#
# DESCRIPTION:
# This script reads the output file of Results_difference_ECO.pl script. 
# Then for specified penetraion rate and iteration number determins 
# mean and standard deviation for each results field
#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;

use XML::Simple; # to parse the XML results files
use XML::Dumper;
use Data::Dumper; # For debugging
use Storable  qw(dclone); # To create copies of arrays so that grep can do find/replace without affecting the original data
use Hash::Merge qw(merge); # To merge the results data
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Switch;
# CHREM modules
use lib ('./modules');
use General; # Access to general CHREM items (input and ordering)
use Results; # Subroutines for results accumulations
use Upgrade;

# Set Data Dumper to report in an ordered fashion
$Data::Dumper::Sortkeys = \&order;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $mean_deviation_name;
my $penet_rate;
my $num_iteration;
my $difference_set_name;
# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+Results_(.+)_Houses.csv/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
my @possible_set_names_print = @{&order($possible_set_names)}; # Order the names so we can print them out if an inappropriate value was supplied

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV != 4) {die "Four arguments are required: mean_diviation_name  difference_set_name penetration_rate num_iteration\nPossible set_names are: @possible_set_names_print\n";};
 
	($mean_deviation_name, $difference_set_name, $penet_rate, $num_iteration) = @ARGV; # shift the names

	if (defined($possible_set_names->{$mean_deviation_name})) {
		die "The collated set_name \"$mean_deviation_name\" is not unique\nPlease choose a string different than the following: @possible_set_names_print\n";
	}
	
	$mean_deviation_name = '_' . $mean_deviation_name;
	
	if (defined($possible_set_names->{$difference_set_name})) {
		$difference_set_name = '_'. $difference_set_name;
	}
	else {
		die "Set_name \"$difference_set_name\" was not found\nPossible set_names are: @possible_set_names_print\n";
	}
	
	unless (($penet_rate >= 0) || ($penet_rate <= 100)) {
		die "Penetration rate should be between 0 and 100 \n";
	}
}

#--------------------------------------------------------------------
# Mean and Deviation Calculation
#--------------------------------------------------------------------
MEAN_DEV:{
	
	my $new_data;
	my $houses_name;
	my $count;
	my @hse_types = ('SD', 'DR');
	my @provinces = ('NF','NS','NB','PE','OT','QC','SK','AB','MB','BC');
	my %regions_prov = ('AT' => ['NF','NS','NB','PE'], 'QC' => ['QC'], 'OT' => ['OT'], 'BC' => ['BC'], 'PR' => ['SK','AB','MB']);
	my @parameters; # declare an array to hold the header parameters
	# Declare a variable to store the total results by province and house type
	my $result_tot;
	my $result_total;
	my $multiplier;
	my $data_eco;
	# read the difference file which contains all houses of an specified upgrade
	my $filename = '../summary_files/Results' . $difference_set_name . '_Houses.csv';
	my $filename_out = '../summary_files/Results' . $mean_deviation_name . '_Total.csv';
	my $FILEOUT;

	my $FILEIN;
	open ($FILEIN, '<', $filename) or die ("Can't open datafile: $filename");	# open readable file
	
	open ($FILEOUT, '>', $filename_out) or die ("Can't open datafile: $filename_out");	# open writable file
	
	while (<$FILEIN>){
	
		# print the headers
		unless ($_ =~ /^\*data,/) {
			if ($_ =~ /^\*units,/) {
				$_ =~ s/CAN\$/kCAN\$/g;
				$_ =~ s/GJ/TJ/g;
				$_ =~ s/kg/t/g;
				$_ =~ s/l/kl/g;
				$_ =~ s/kWh/MWh/g;
				$_ =~ s/m3/km3/g;
				$_ =~ s/tonne/kt/g;
				print $FILEOUT "$_";
			}
			elsif ($_ =~ /^\*field,/) {
				my @line = CSVsplit($_);
				@parameters = @line;
				foreach my $par (@line) {
					
					$par =~ s/CAN\$/kCAN\$/g;
					$par =~ s/GJ/TJ/g;
					$par =~ s/kg/t/g;
					$par =~ s/\(l\)/\(kl\)/g;
					$par =~ s/kWh/MWh/g;
					$par =~ s/m3/km3/g;
					$par =~ s/tonne/kt/g;
					
				}
				print $FILEOUT CSVjoin (@line) . "\n";
			}
			else {
				print $FILEOUT "$_";
			
			}	
		}
		
		($new_data) = &data_read_one_up ($_, $new_data);

		# put the house for each province and house type in a hash
		if ($_ =~ /^\*data,/) {
			push (@{$houses_name->{$new_data->{'hse_type'}}->{$new_data->{'province'}}},$new_data->{'house_name'}); #store all the house by hse_type and province
			$count->{$new_data->{'hse_type'}}->{$new_data->{'province'}}++;
			$multiplier->{$new_data->{'hse_type'}}->{$new_data->{'province'}} = $new_data->{'required_multiplier'};
			$data_eco->{'escalation_rate'} =  $new_data->{'escalation_rate'};
			$data_eco->{'interest_rate'} = $new_data->{'interest_rate'};
			$data_eco->{'payback_period'} = $new_data->{'payback_period'};
# 			print Dumper $houses_name;
		}
	}
	close ($FILEIN);
	
	
	my $count_pent;
# 	print Dumper $multiplier; 
	my @calc_parameters;
	foreach (@parameters) {
		unless ($_ =~ /\*field|house_name|region|province|hse_type|required_multiplier|escalation_rate|interest_rate|payback_period/) {
			push (@calc_parameters, $_);
		}
	}
# 	print "@calc_parameters \n";
	
	# for each iteration select number of houses regarding penetration rate randomly and strore the total result for each province
	for (my $iter = 1; $iter <= $num_iteration; $iter++) {
		foreach my $hse (@hse_types) {
			foreach my $prov (@provinces) {
				
				#determine the number of houses for each province and house type for the penetrtaion rate
				if ( defined ($count->{$hse}->{$prov})){
					$count_pent->{$hse}->{$prov} =  sprintf ("%.0f", $count->{$hse}->{$prov} * $penet_rate/100);
# 					print "$count_pent->{$hse}->{$prov} \n";
				}
				else { next;}
				
				my @houses_selected_pent = ();
				#select the house randomly
				my @numbers = (1 .. $count->{$hse}->{$prov});
				my @random_sample = &rand_sample($count_pent->{$hse}->{$prov},@numbers);
				
				for (my $k = 0; $k < $count_pent->{$hse}->{$prov}; $k++) {
					
					$houses_selected_pent[$k] = $houses_name->{$hse}->{$prov}[$random_sample[$k]-1];
					
				}
# 				print "$hse $prov $iter @houses_selected_pent \n";
				my $seen;
				foreach my $var (@parameters) {
					$seen->{$var} = 1;
				}
				open ($FILEIN, '<', $filename) or die ("Can't open datafile: $filename");	# open readable file
				while (<$FILEIN>) {
					 ($new_data) = &data_read_one_up ($_, $new_data);
					 foreach my $house (@houses_selected_pent) {
					
						if (($_ =~ /^\*data,/) && ($new_data->{'house_name'} =~ /^$house$/)) {
							  
							foreach my $var (@calc_parameters) {

								if ((defined($new_data->{$var})) && ($new_data->{$var} =~ /\d|.?\d/)) {
										if ($seen->{$var} == 1) {
											$result_tot->{$hse}->{$prov}->{$var}[$iter-1] = 0 ;
											$seen->{$var}++;
										}
										$result_tot->{$hse}->{$prov}->{$var}[$iter-1] = $result_tot->{$hse}->{$prov}->{$var}[$iter-1] + $new_data->{$var} * $multiplier->{$hse}->{$prov};
										
								}
									
							
							}
						}
				
					}
						
# 					
				}
				close ($FILEIN);
				foreach my $var (@calc_parameters) {
					
					if ($iter == 1) {
						$result_total->{$hse}->{$prov}->{'sum'}->{$var} = 0;
					}
					if (defined ($result_tot->{$hse}->{$prov}->{$var}[$iter-1])) {
						$result_total->{$hse}->{$prov}->{'sum'}->{$var} = $result_tot->{$hse}->{$prov}->{$var}[$iter-1] + $result_total->{$hse}->{$prov}->{'sum'}->{$var};
					}
					
				}
				
			}
		}
		print "iteration $iter is done! \n";		
					
	}
	
	
	# this section calculate the mean, variance and standard diviation for results of each province and house_type
	foreach my $hse (@hse_types) {
		foreach my $prov (@provinces) {
			foreach my $var (@calc_parameters) {
				if ( defined ($count->{$hse}->{$prov})){
					
					$result_total->{$hse}->{$prov}->{'mean'}->{$var} = $result_total->{$hse}->{$prov}->{'sum'}->{$var} / $num_iteration/1000;
						for (my $iter = 1; $iter <= $num_iteration; $iter++) {
							if ($iter == 1 ) {
								$result_total->{$hse}->{$prov}->{'variance'}->{$var} = 0;
							}
							if (defined ($result_tot->{$hse}->{$prov}->{$var}[$iter-1])) {
								$result_total->{$hse}->{$prov}->{'variance'}->{$var} = ($result_tot->{$hse}->{$prov}->{$var}[$iter-1]/1000 - $result_total->{$hse}->{$prov}->{'mean'}->{$var}) ** 2 + $result_total->{$hse}->{$prov}->{'variance'}->{$var};
							}
						}
					$result_total->{$hse}->{$prov}->{'variance'}->{$var} = $result_total->{$hse}->{$prov}->{'variance'}->{$var} / $num_iteration;
					$result_total->{$hse}->{$prov}->{'std_deviation'}->{$var} = $result_total->{$hse}->{$prov}->{'variance'}->{$var} ** 0.5;
					
				}
			}
		}
	}
	
# 	print Dumper $result_total;
	my @regions = keys (%regions_prov);
	my @mean = ('mean', 'standard_deviation');
	
		foreach my $reg (@regions) {
			foreach my $prov (@{$regions_prov{$reg}}) { 
				foreach my $hse (@hse_types) {
					foreach my $m_std (@mean) {
						if ( defined ($count->{$hse}->{$prov})){
							if ($m_std eq 'mean') {
								print $FILEOUT CSVjoin ('*data', 'CHREM', $reg, $prov, $hse, $data_eco->{'payback_period'}, $data_eco->{'interest_rate'}, $data_eco->{'escalation_rate'}, $multiplier->{$hse}->{$prov}, @{$result_total->{$hse}->{$prov}->{'mean'}}{@calc_parameters},$m_std)."\n";
							}
							else {
								print $FILEOUT CSVjoin ('*data', 'CHREM', $reg, $prov, $hse, $data_eco->{'payback_period'}, $data_eco->{'interest_rate'}, $data_eco->{'escalation_rate'}, $multiplier->{$hse}->{$prov},@{$result_total->{$hse}->{$prov}->{'std_deviation'}}{@calc_parameters} , $m_std)."\n";
							}
						}
					}
				}
			}
		}
	
				
}

