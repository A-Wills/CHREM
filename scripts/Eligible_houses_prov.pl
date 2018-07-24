#!/usr/bin/perl
# 
#====================================================================
# Eligible_houses_prov.pl
# Author:    Sara Nikoofard
# Date:      NOV 2011
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl 
#
# DESCRIPTION:
# This script simply count eligible houses for different upgrades and 
# different provice and house typr and put it in a file to be used in 
# Results_difference_Eco.pl
#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;
use CSV;		#CSV-2 (for CSV split and join, this works best)
use Switch;
use Data::Dumper;

use lib qw(./modules);
use General;
use Upgrade;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my @hse_types;					# declare an array to store the desired house types
my %hse_names = (1, "1-SD", 2, "2-DR");		# declare a hash with the house type names

my @regions;									#Regions to generate
my %region_names = (1, "1-AT", 2, "2-QC", 3, "3-OT", 4, "4-PR", 5, "5-BC");

my @upgrades;
my %upgrade_names = (1, "SDHW", 2, "WAM", 3, "WTM", 4, "FVB", 5, "FOH", 6, "PCM", 7, "CVB", 8, "PV", 9, "BIPVT");

my %provinces = ("NF", "NEWFOUNDLAND", "NS", "NOVA SCOTIA" , "PE", "PRINCE EDWARD ISLAND", "NB", "NEW BRUNSWICK", "QC", "QUEBEC", "OT", "ONTARIO", "MB", "MANITOBA", "SK", "SASKATCHEWAN", "AB", "ALBERTA" , "BC", "BRITISH COLUMBIA");
#--------------------------------------------------------------------
# Main program
#--------------------------------------------------------------------
my $FILEIN;
my $FILEUP;
my $count;
my $COUNT;
my $houses;


@hse_types = (1,2);
@regions = (1,2,3,4,5);
@upgrades = (1,2,3,4,5,6,7,8,9);

foreach my $hse_type (@hse_types) {
	foreach my $prov (keys (%provinces)){
		my $file = '../Eligible_houses/Count_Prov_'.$hse_names{$hse_type}.'_prov_'.$prov;
		my $ext = '.csv';
		open (my $COUNT, '>', $file.$ext);
		my @header = ('*header', 'hse_type', 'province', 'upgrade1', 'upgrade2', 'upgrade3', 'eligible', 'total');
		print $COUNT CSVjoin (@header) . "\n";
		close ($COUNT);
	}
}

foreach my $hse_type (@hse_types) {
	
	foreach my $region (@regions) {

		# first calculate the total houses in each province for each house type

		my $file = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_names{$hse_type} . '_subset_' . $region_names{$region};
		my $ext = '.csv';
		open ($FILEIN, '<', $file . $ext) or die ("Can't open datafile: $file$ext");	# open readable file

		my $new_data;
		while (<$FILEIN>){
			($new_data) = &data_read_one_up ($_, $new_data);
			if ($_ =~ /^\*data,/) {
				switch ($new_data->{'HOT2XP_PROVINCE_NAME'}) {
					case ("NOVA SCOTIA") {
						$count->{$hse_type}->{'NS'}++;
					}
					case ("NEWFOUNDLAND") {
						$count->{$hse_type}->{'NF'}++;
					}
					case ("PRINCE EDWARD ISLAND") {
						$count->{$hse_type}->{'PE'}++;
					}
					case ("NEW BRUNSWICK") {
						$count->{$hse_type}->{'NB'}++;
					}
					case ("QUEBEC") {
						$count->{$hse_type}->{'QC'}++;
					}
					case ("ONTARIO") {
						$count->{$hse_type}->{'OT'}++;
					}
					case ("MANITOBA") {
						$count->{$hse_type}->{'MB'}++;
					}
					case ("SASKATCHEWAN") {
						$count->{$hse_type}->{'SK'}++;
					}
					case ("ALBERTA") {
						$count->{$hse_type}->{'AB'}++;
					}
					case ("BRITISH COLUMBIA") {
						$count->{$hse_type}->{'BC'}++;
					}
				}
			}
		}
		close ($FILEIN);
	}
}

my %win_types = (203, 2010, 210, 2100, 213, 2110, 300, 3000, 320, 3200, 323, 3210, 333, 3310);
my @up_name;
foreach my $up (@upgrades) {
	unless ($upgrade_names{$up} =~ /WTM/) {
		push (@up_name,$upgrade_names{$up});
	}
	else {
		foreach my $win_type (keys (%win_types)) {
			push (@up_name, $upgrade_names{$up}.$win_types{$win_type});
		}
	}
}
# foreach (@up_name) {print "$_ \n";}
# die "end of the test \n";

my $count_up1;
foreach my $hse_type (@hse_types) {
	
	foreach my $region (@regions) {
		
		foreach my $up (@up_name) {
			my $file_up = '../Eligible_houses/Eligible_Houses_Upgarde_'.$up.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv';
			open ($FILEUP, '<', $file_up) or die ("Can't open datafile: $file_up");	# open readable file
			
			my $NS = 0;
			my $NF = 0;
			my $PE = 0;
			my $NB = 0;
			my $QC = 0;
			my $OT = 0;
			my $MB = 0;
			my $SK = 0;
			my $AB = 0;
			my $BC = 0;

			my $new_data;
			while (<$FILEUP>){
				($new_data) = &data_read_one_up ($_, $new_data);
				if (defined ($new_data->{'file_name'})){
					switch ($new_data->{'HOT2XP_PROVINCE_NAME'}) {
						case ("NOVA SCOTIA") {
							$count_up1->{$hse_type}->{'NS'}->{$up}++;
							$houses->{$hse_type}->{'NS'}->{$up}->[$NS] = $new_data->{'file_name'};
							$NS++;
						}
						case ("NEWFOUNDLAND") {
							$count_up1->{$hse_type}->{'NF'}->{$up}++;
							$houses->{$hse_type}->{'NF'}->{$up}->[$NF] = $new_data->{'file_name'};
							$NF++;
						}
						case ("PRINCE EDWARD ISLAND") {
							$count_up1->{$hse_type}->{'PE'}->{$up}++;
							$houses->{$hse_type}->{'PE'}->{$up}->[$PE] = $new_data->{'file_name'};
							$PE++;
						}
						case ("NEW BRUNSWICK") {
							$count_up1->{$hse_type}->{'NB'}->{$up}++;
							$houses->{$hse_type}->{'NB'}->{$up}->[$NB] = $new_data->{'file_name'};
							$NB++;
						}
						case ("QUEBEC") {
							$count_up1->{$hse_type}->{'QC'}->{$up}++;
							$houses->{$hse_type}->{'QC'}->{$up}->[$QC] = $new_data->{'file_name'};
							$QC++;
						}
						case ("ONTARIO") {
							$count_up1->{$hse_type}->{'OT'}->{$up}++;
							$houses->{$hse_type}->{'OT'}->{$up}->[$OT] = $new_data->{'file_name'};
							$OT++;
						}
						case ("MANITOBA") {
							$count_up1->{$hse_type}->{'MB'}->{$up}++;
							$houses->{$hse_type}->{'MB'}->{$up}->[$MB] = $new_data->{'file_name'};
							$MB++;
						}
						case ("SASKATCHEWAN") {
							$count_up1->{$hse_type}->{'SK'}->{$up}++;
							$houses->{$hse_type}->{'SK'}->{$up}->[$SK] = $new_data->{'file_name'};
							$SK++;
						}
						case ("ALBERTA") {
							$count_up1->{$hse_type}->{'AB'}->{$up}++;
							$houses->{$hse_type}->{'AB'}->{$up}->[$AB] = $new_data->{'file_name'};
							$AB++;
						}
						case ("BRITISH COLUMBIA") {
							$count_up1->{$hse_type}->{'BC'}->{$up}++;
							$houses->{$hse_type}->{'BC'}->{$up}->[$BC] = $new_data->{'file_name'};
							$BC++;
						}
					}
				}
			}
			close $FILEUP;
		}
	}
 }

foreach my $hse_type (@hse_types) {
	
	foreach my $prov (keys %provinces) {
		
		foreach my $up (@up_name) {

			unless (defined $count_up1->{$hse_type}->{$prov}->{$up}) {
				$count_up1->{$hse_type}->{$prov}->{$up} = 0;
			}
		}
	}
}
# find the same eligible home in case of two upgrades at the same time
my @short_prov = keys %provinces;

my $count_up2;
foreach my $hse_type (&array_order(@hse_types)) {
	
	foreach my $prov (&array_order(@short_prov)) {
		
		foreach my $up1 (&array_order(@up_name)) {

			LOOP: foreach my $up2 (&array_order(@up_name)) {
				if (($up1 eq $up2) || ($up1 gt $up2)) {next LOOP;}
# 				print "$prov \n";
				my @houses_selected;
				if (defined ($houses->{$hse_type}->{$prov}->{$up1}) && defined ($houses->{$hse_type}->{$prov}->{$up2}) ){

					my @array1 = @{$houses->{$hse_type}->{$prov}->{$up1}};
					my @array2 = @{$houses->{$hse_type}->{$prov}->{$up2}};
					my %houses_count;
					map $houses_count{$_}++ , @array1, @array2;
					@houses_selected = grep $houses_count{$_} == 2, @array1;
					$count_up2->{$hse_type}->{$prov}->{$up1.'_'.$up2} = $#houses_selected +1;
				}

			} #end LOOP
		}
	}
}

# find the same eligible home in case of three upgrades at the same time


my $count_up3;
foreach my $hse_type (&array_order(@hse_types)) {
	
	foreach my $prov (&array_order(@short_prov)) {
		
		UP1:foreach my $up1 (&array_order(@up_name)) {

			UP2:foreach my $up2 (&array_order(@up_name)) {
				if ($up1 eq $up2) {next UP2;}

				UP3:foreach my $up3 (&array_order(@up_name)) {
					
					 if (($up2 eq $up3) || ($up2 gt $up3)) {next UP3;}

					  my @houses_selected;
					  if (defined ($houses->{$hse_type}->{$prov}->{$up1}) && defined ($houses->{$hse_type}->{$prov}->{$up2}) && defined ($houses->{$hse_type}->{$prov}->{$up3}) ){

						my %houses_count;
						my @array1 = @{$houses->{$hse_type}->{$prov}->{$up1}};
						my @array2 = @{$houses->{$hse_type}->{$prov}->{$up2}};
						my @array3 = @{$houses->{$hse_type}->{$prov}->{$up3}};
						map $houses_count{$_}++ , @array1, @array2, @array3;
						@houses_selected = grep $houses_count{$_} == 3, @array1;
						$count_up3->{$hse_type}->{$prov}->{$up1.'_'.$up2.'_'.$up3} = $#houses_selected +1;
					}
				}

			} 
		}
	}
}

foreach my $hse_type (&array_order(@hse_types)) {
	
	foreach my $prov (&array_order(@short_prov)) {

		my $file = '../Eligible_houses/Count_Prov_'.$hse_names{$hse_type}.'_prov_'.$prov;
		my $ext = '.csv';
		open (my $COUNT, '>>', $file.$ext);
		
		UP1:foreach my $up1 (&array_order(@up_name)) {

			UP2:foreach my $up2 (&array_order(@up_name)) {

				UP3:foreach my $up3 (&array_order(@up_name)) {

					my @line = ('*data', $hse_names{$hse_type}, $provinces{$prov});
					if (($up1 eq $up2) && ($up2 eq $up3)) {
						unless (defined $count_up1->{$hse_type}->{$prov}->{$up1}) {
							$count_up1->{$hse_type}->{$prov}->{$up1} = 0;
						}
						push (@line, $up1, '0', '0', $count_up1->{$hse_type}->{$prov}->{$up1}, $count->{$hse_type}->{$prov});
						print $COUNT CSVjoin (@line) . "\n";
					}
					elsif (($up1 eq $up2) && ($up2 lt $up3)) { 
						unless (defined $count_up2->{$hse_type}->{$prov}->{$up2.'_'.$up3}) {
							$count_up2->{$hse_type}->{$prov}->{$up2.'_'.$up3} = 0;
						}
						push (@line, $up2, $up3, '0', $count_up2->{$hse_type}->{$prov}->{$up2.'_'.$up3}, $count->{$hse_type}->{$prov});
						print $COUNT CSVjoin (@line) . "\n";
					}
					elsif (($up1 eq $up2) && ($up2 gt $up3))  {next UP3;}
					elsif (($up1 lt $up2) && ($up2 gt $up3)) {next UP3;}
					elsif (($up1 lt $up2) && ($up2 eq $up3)) {next UP3;}
					elsif (($up1 lt $up2) && ($up2 lt $up3)) {
						unless (defined $count_up3->{$hse_type}->{$prov}->{$up1.'_'.$up2.'_'.$up3}) {
							$count_up3->{$hse_type}->{$prov}->{$up1.'_'.$up2.'_'.$up3} = 0;
						}
						push (@line, $up1, $up2, $up3, $count_up3->{$hse_type}->{$prov}->{$up1.'_'.$up2.'_'.$up3}, $count->{$hse_type}->{$prov});
						print $COUNT CSVjoin (@line) . "\n";
					}
					elsif ($up1 gt $up2) {next UP2;}
				}
			}
		}
		close ($COUNT);
	}
}


