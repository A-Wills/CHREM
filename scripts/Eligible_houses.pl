#!/usr/bin/perl
# 
#====================================================================
# Eligible_houses.pl
# Author:    Sara Nikoofard
# Date:      June 2011
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"] [upgrade number seperated by "/"; 0 means all] 
#
# DESCRIPTION:
# This script simply select eligible houses for different upgrades and 
# put it in a file to be used in Hse_Gen.pl
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

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my @hse_types;					# declare an array to store the desired house types
my %hse_names = (1, "1-SD", 2, "2-DR");		# declare a hash with the house type names

my @regions;									#Regions to generate
my %region_names = (1, "1-AT", 2, "2-QC", 3, "3-OT", 4, "4-PR", 5, "5-BC");

my @upgrades;
my %upgrade_names = (1, "SDHW", 2, "WAM", 3, "WTM", 4, "FVB", 5, "FOH", 6, "PCM", 7, "CVB", 8, "PV", 9, "BIPVT");

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if ($#ARGV != 2) {die "Three arguments are required: house_types regions upgrade\n";};
	
	if ($ARGV[0] eq "0") {@hse_types = (1, 2);}	# check if both house types are desired
	else {
		@hse_types = split (/\//,$ARGV[0]);	# House types to generate
		foreach my $type (@hse_types) {
			unless (defined ($hse_names{$type})) {
				my @keys = sort {$a cmp $b} keys (%hse_names);
				die "House type argument must be one or more of the following numeric values seperated by a \"/\": 0 @keys\n";
			};
		};
	};
	
	if ($ARGV[1] eq "0") {@regions = (1, 2, 3, 4, 5);}
	else {
		@regions = split (/\//,$ARGV[1]);	# House regions to generate
		foreach my $region (@regions) {
			unless (defined ($region_names{$region})) {
				my @keys = sort {$a cmp $b} keys (%region_names);
				die "Region argument must be one or more of the following numeric values seperated by a \"/\": 0 @keys\n";
			};
		};
	};
	if ($ARGV[2] eq "0") {@upgrades = (1, 2, 3, 4, 5, 6, 7, 8, 9);}
	else {
		@upgrades = split (/\//, $ARGV[2]);	# upgrade types to generate
		foreach my $up (@upgrades) {
			unless (defined ($upgrade_names{$up})) {
				my @keys = sort {$a cmp $b} keys (%upgrade_names);
				die "Upgrade argument must be one or more of the following numeric values seperated by a \"/\": 0 @keys\n";
			}
		}
	}
};

#--------------------------------------------------------------------
# Main program
#--------------------------------------------------------------------
my $FILEIN;
my $count;
my $COUNT;
open ($COUNT, '>', '../Eligible_houses/Count.csv');
my @header = ('*header', 'hse_type', 'region', 'upgrade', 'eligible', 'total');
print $COUNT CSVjoin (@header) . "\n";
foreach my $hse_type (@hse_types) {
	foreach my $region (@regions) {
		my $file = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_names{$hse_type} . '_subset_' . $region_names{$region};
		my $ext = '.csv';
		foreach my $up (@upgrades) {
			unless ($upgrade_names{$up} =~ /^WTM/){ 
				open ($FILEIN, '<', $file . $ext) or die ("Can't open datafile: $file$ext");	# open readable file
			}
			my @line;
			if ($upgrade_names{$up} !~ /^WTM/) {
				@line = ('*data', $hse_names{$hse_type}, $region_names{$region}, $upgrade_names{$up});
			}
			my $new_data;	# create an crosslisting hash reference
			switch ($up) {
				case (1) { # eligible houses for SDHW
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_SDHW = 0;
					my @houses_SDHW;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						my $width;
						my @zones = qw (bsmt crawl main_1 main_2 main_3);
						my $last_zone;
						my $w_d_ratio = 1;
						# calculation width of all zones
						if (defined($new_data->{'exterior_width'} && $new_data->{'exterior_depth'})){
							if ($new_data->{'exterior_dimension_indicator'} == 0) {
								$w_d_ratio = sprintf ("%.2f", $new_data->{'exterior_width'}/ $new_data->{'exterior_depth'});
								if ($w_d_ratio < 0.66) {
									$w_d_ratio = sprintf ("%.2f",0.66);
								}
								elsif ($w_d_ratio > 1.5) {
									$w_d_ratio = sprintf ("%.2f",1.5);
								}
							}
							
							my $depth = sprintf("%6.2f", ($new_data->{'main_floor_area_1'} / $w_d_ratio) ** 0.5);
							foreach my $zone (@zones) {
								if ($zone =~ /^bsmt$|^crawl$/) {
									# Because bsmt walls are thicker, the bsmt or crawl floor area is typically a little less than the main_1 level. However, it is really not appropriate to expose main_1 floor area for this small difference.
									# Thus, if the difference between the main_1 and foundation floor area is less than 10% of them main_1 floor area, resize the foundation area to be equal to the main_1 floor area
									if ($new_data->{'main_floor_area_1'} - $new_data->{$zone . '_floor_area'} < 0.1 * $new_data->{'main_floor_area_1'}) {
										$new_data->{$zone . '_floor_area'} = $new_data->{'main_floor_area_1'};
									}
									$width->{$zone} = $new_data->{$zone . '_floor_area'} / $depth;	# determine width of zone based upon main_1 depth
								}
								elsif ($zone =~ /^main_(\d)$/) {
									# determine x from floor area and y
									$width->{$zone} = $new_data->{"main_floor_area_$1"} / $depth;	# determine width of zone based upon main_1 depth
									if ($width->{$zone} > 0) {
										$last_zone = $zone;
									}
								}
								
								
							};
							
							# examine the existance of attic and if the DR house is middle row attachment
							if ($new_data->{'ceiling_flat_type'} == 2 && $new_data->{'attachment_type'} == 1) {
								# next criteria is existance of the DHW
								unless ($new_data->{'DHW_energy_src'} == 9){ # if we have DHW 
									unless ((($new_data->{'DHW_energy_src'} == 1) && ($new_data->{'DHW_equip_src'} == 5)) || (($new_data->{'DHW_energy_src'} == 2) && ($new_data->{'DHW_equip_src'} == 4)) || (($new_data->{'DHW_energy_src'} == 3) && ($new_data->{'DHW_equip_src'} == 3)) || (($new_data->{'DHW_energy_src'} == 4) && ($new_data->{'DHW_equip_src'} == 4))) { # if there is tank for the DHW
										# the ridgeline is parallel to the longer side 
										# if the front orientation of the house is south, south-east or south-west to have a ridgeline running west-east the width which is always front of the house should be more than depth
										if ($new_data->{'front_orientation'} == 3 || $new_data->{'front_orientation'} == 7) {
											if (($width->{'main_1'} < $depth) && ($w_d_ratio != 1)) {
												$houses_SDHW[$count_SDHW] = $new_data->{'file_name'};
												$count_SDHW++;
												print $FILEOUT "$_ \n";
											}
										}
									
										else {
											if ($width->{'main_1'} > $depth) {
												$houses_SDHW[$count_SDHW] = $new_data->{'file_name'};
												$count_SDHW++;
												print $FILEOUT "$_ \n";
											}
										}
									}
								}
							}
							elsif ($new_data->{'attachment_type'} == 4 && $new_data->{'ceiling_flat_type'} == 2) { # in this case the x is always front so the ridgeline never go east -west in case of east and west orientation
								unless ($new_data->{'front_orientation'} == 3 || $new_data->{'front_orientation'} == 7) {
									unless ($new_data->{'DHW_energy_src'} == 9){ # if we have DHW 
										unless ((($new_data->{'DHW_energy_src'} == 1) && ($new_data->{'DHW_equip_src'} == 5)) || (($new_data->{'DHW_energy_src'} == 2) && ($new_data->{'DHW_equip_src'} == 4)) || (($new_data->{'DHW_energy_src'} == 3) && ($new_data->{'DHW_equip_src'} == 3)) || (($new_data->{'DHW_energy_src'} == 4) && ($new_data->{'DHW_equip_src'} == 4))) { # if there is tank for the DHW
											$houses_SDHW[$count_SDHW] = $new_data->{'file_name'};
											$count_SDHW++;
											print $FILEOUT "$_ \n";
										}
									}
								}
							}
							elsif ($new_data->{'ceiling_flat_type'} == 3) {
								if ($new_data->{'attachment_type'} == 2 || $new_data->{'attachment_type'} == 3) { # DR - left/right end house type
									if (($width->{$last_zone} * 2 / 3) >= 4 && ($new_data->{'DHW_equip_type'} != 9)){
										unless ((($new_data->{'DHW_energy_src'} == 1) && ($new_data->{'DHW_equip_src'} == 5)) || (($new_data->{'DHW_energy_src'} == 2) && ($new_data->{'DHW_equip_src'} == 4)) || (($new_data->{'DHW_energy_src'} == 3) && ($new_data->{'DHW_equip_src'} == 3)) || (($new_data->{'DHW_energy_src'} == 4) && ($new_data->{'DHW_equip_src'} == 4))) { # if there is tank for the DHW
											$houses_SDHW[$count_SDHW] = $new_data->{'file_name'};
											$count_SDHW++;
											print $FILEOUT "$_ \n";
										}
									}
								}
							}
						}
					
					}
# 					print "$count_SDHW \n";
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_SDHW;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line) . "\n";
# 					print " the count for house $hse_names{$hse_type} and region $region_names{$region} is $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} \n";
				}
				case (2) { # eligible houses for WAM 
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_WAM = 0;
					my @houses_WAM;
					my $count_total = 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						my $width;
						my $height;
						my $total_area;
						my @zones = qw (bsmt crawl main_1 main_2 main_3);
						my @sides = qw (front back right left);
						# calculation of area for all surfaces
						if (defined($new_data->{'exterior_width'} && $new_data->{'exterior_depth'})){
							my $w_d_ratio = sprintf ("%.2f", $new_data->{'exterior_width'}/ $new_data->{'exterior_depth'});
							my $depth = sprintf("%6.2f", ($new_data->{'main_floor_area_1'} / $w_d_ratio) ** 0.5);
							foreach my $zone (@zones) {
								foreach my $surface (@sides) {
									$total_area->{'total'}->{$surface} = 0;
								}
							}
							foreach my $zone (@zones) {
								if ($zone =~ /^bsmt$|^crawl$/) {
									# Because bsmt walls are thicker, the bsmt or crawl floor area is typically a little less than the main_1 level. However, it is really not appropriate to expose main_1 floor area for this small difference.
									# Thus, if the difference between the main_1 and foundation floor area is less than 10% of them main_1 floor area, resize the foundation area to be equal to the main_1 floor area
									if ($new_data->{'main_floor_area_1'} - $new_data->{$zone . '_floor_area'} < 0.1 * $new_data->{'main_floor_area_1'}) {
										$new_data->{$zone . '_floor_area'} = $new_data->{'main_floor_area_1'};
									}
									$width->{$zone} = $new_data->{$zone . '_floor_area'} / $depth;	# determine width of zone based upon main_1 depth
									$height->{$zone} = $new_data->{$zone . '_wall_height'};
									$total_area-> {$zone} = &total_surface_area ($width->{$zone}, $depth, $height->{$zone});
								}
								elsif ($zone =~ /^main_(\d)$/) {
									# determine x from floor area and y
									$width->{$zone} = $new_data->{"main_floor_area_$1"} / $depth;	# determine width of zone based upon main_1 depth
									$height->{$zone} = $new_data->{"main_wall_height_$1"};	# determine height of zone
									$total_area->{$zone} = &total_surface_area ($width->{$zone}, $depth, $height->{$zone});
								}

								foreach my $surface (@sides){
									$total_area->{'total'}->{$surface} = $total_area-> {$zone}->{$surface} + $total_area->{'total'}->{$surface};
# 									print "$total_area->{'total'}->{$surface} \n";
								}
							};
						}
						# presence of window on the south, south-west and south-east side
						my $win_wall_ratio = 0.3;
						switch ($new_data->{'wndw_z_front_direction'}){
							case(1) {
								if ($new_data->{'wndw_count_front'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_front'} / $total_area->{'total'}->{'front'}) < $win_wall_ratio) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(2) {
								if ($new_data->{'wndw_count_front'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_front'} / $total_area->{'total'}->{'front'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(3) {
								if ($new_data->{'wndw_count_left'} > 0 ) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_left'} / $total_area->{'total'}->{'left'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(4) {
								if ($new_data->{'wndw_count_back'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_back'} / $total_area->{'total'}->{'back'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(5) {
								if ($new_data->{'wndw_count_back'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_back'} / $total_area->{'total'}->{'back'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(6) {
								if ($new_data->{'wndw_count_back'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_back'} / $total_area->{'total'}->{'back'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(7) {
								if ($new_data->{'wndw_count_right'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_right'} / $total_area->{'total'}->{'right'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							case(8) {
								if ($new_data->{'wndw_count_front'} > 0) {
									# check the window area/wall area ratio (it should be less than 30%)
									if (($new_data->{'wndw_area_front'} / $total_area->{'total'}->{'front'}) < $win_wall_ratio ) {
										$houses_WAM[$count_WAM] = $new_data->{'file_name'};
										$count_WAM++;
										print $FILEOUT "$_ \n";
									}
								}
							} 
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_WAM;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
# 					print "$count_WAM \n";
				}
				case (3) { # eligible houses for WTM
					# Based on the parametric study 6 types of WTM selected to be studied. the criteria for each one is different so There will be 6 different files for each house tyep and region
					# window types are (203, 210, 213, 300, 320, 323)
					my %win_types = (203, 2010, 210, 2100, 213, 2110, 300, 3000, 320, 3200, 323, 3210, 333, 3310);
					foreach my $win_type (keys (%win_types)) {
						@line = ('*data', $hse_names{$hse_type}, $region_names{$region}, $upgrade_names{$up}.$win_types{$win_type});
						my $file = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_names{$hse_type} . '_subset_' . $region_names{$region};
						my $ext = '.csv';
						open ($FILEIN, '<', $file . $ext) or die ("Can't open datafile: $file$ext");	# open readable file
						open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}. $win_types{$win_type}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
						my $count_WTM = 0;
						my @houses_WTM;
						my $count_total= 0;
						RECORD: while (<$FILEIN>){
							($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
							if ($_ =~ /^\*data,/) { $count_total++;}
							if (defined ($new_data->{'wndw_favourite_code'}) ){
								$new_data->{'wndw_favourite_code'}=~ /(\d{3})\d{3}/;
								my $wndw_code = $1;
									
								# for the win_type = 203 all single glazed and double clear glass air filled will be upgraded
								if ($win_type =~ /203/){
									if ($wndw_code=~ /^([1-2]?[0]?[0-2])$/) {
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								}
								
								# for win_type = 210 all single glazed and double clear glass will be upgraded
								elsif ($win_type =~ /210/){
									if ($wndw_code=~ /^([1-2]?[0]?[0-3])$/) {
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								}  

								# for win_type = 213 all single glazed and double clear glass and type 210 will be upgraded
								elsif ($win_type =~ /213/){
									if (($wndw_code=~ /^([1-2]?[0]?[0-3])$/) || ($wndw_code=~ /210/)){
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								} 

								# for win_type = 300 all single glazed and double clear glass and type 210 will be upgraded
								elsif ($win_type =~ /300/){
									if (($wndw_code=~ /^([1-2]?[0]?[0-3])$/) || ($wndw_code=~ /^([2]?[1-2]?[0|4])$/) || ($wndw_code=~ /^([2]?[3]?[0|1|4])$/) ||($wndw_code=~ /^([2]?[4]?[0|3|4])$/) || ($wndw_code=~ /^([3]?[0|3]?[1])$/)){
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								} 
									
								# for win_type = 320 all single glazed and double clear glass and type 210 will be upgraded
								elsif ($win_type =~ /320/){
									unless (($wndw_code =~ /^([3]?[3]?[0|3|4])$/) || ($wndw_code =~ /323|320/)){
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								} 

								# for win_type = 323 all single glazed and double clear glass and type 210 will be upgraded
								elsif ($win_type =~ /323/){
									unless (($wndw_code =~ /323|333/)){
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								} 
								# for win_type = 333 all single glazed and double clear glass and type 210 will be upgraded
								elsif ($win_type =~ /333/){
									unless (($wndw_code =~ /333/)){
										$houses_WTM[$count_WTM] = $new_data->{'file_name'};
										$count_WTM++;
										print $FILEOUT "$_ \n";
										next RECORD;
									}
								} 
							}
						}
						close $FILEIN;
						close $FILEOUT;
						$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}.$win_types{$win_type}} = $count_WTM;
						$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
						push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}.$win_types{$win_type}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
						print $COUNT CSVjoin (@line)."\n";
# 						print "$count_WTM \n";
					}
						  
					
				}
				
				case (4) { # eligible houses for FVB 
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_FVB = 0;
					my @houses_FVB;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						# examine the existance of cooling system
						if (defined ($new_data->{'cooling_equip_type'}) && $new_data->{'cooling_equip_type'} != 4) {
							# presence of window on the west, south-west, east and south-east side
							switch ($new_data->{'wndw_count_front'}){
								case(1) {
									if ($new_data->{'wndw_count_right'} > 0 || $new_data->{'wndw_count_left'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(2) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_left'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(3) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_back'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(4) {
									if ($new_data->{'wndw_count_left'} > 0 || $new_data->{'wndw_count_back'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(5) {
									if ($new_data->{'wndw_count_right'} > 0 || $new_data->{'wndw_count_left'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(6) {
									if ($new_data->{'wndw_count_right'} > 0 || $new_data->{'wndw_count_back'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(7) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_back'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(8) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_right'} >0) {
										$houses_FVB[$count_FVB] = $new_data->{'file_name'};
										$count_FVB++;
										print $FILEOUT "$_ \n";
									}
								}
							} 
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_FVB;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
				}
				case (5) { # eligible houses for FOH
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_FOH = 0;
					my @houses_FOH;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						# examine the existance of cooling system
						if (defined ($new_data->{'cooling_equip_type'} ) && $new_data->{'cooling_equip_type'} != 4) {
							# presence of window on the south, south-west and south-east side
							switch ($new_data->{'wndw_count_front'}){
								case(1) {
									if ($new_data->{'wndw_count_front'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(2) {
									if ($new_data->{'wndw_count_front'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(3) {
									if ($new_data->{'wndw_count_left'} > 0 ) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(4) {
									if ($new_data->{'wndw_count_back'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(5) {
									if ($new_data->{'wndw_count_back'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(6) {
									if ($new_data->{'wndw_count_back'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(7) {
									if ($new_data->{'wndw_count_right'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
								case(8) {
									if ($new_data->{'wndw_count_front'} > 0) {
										$houses_FOH[$count_FOH] = $new_data->{'file_name'};
										$count_FOH++;
										print $FILEOUT "$_ \n";
									}
								}
							}
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_FOH;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
				}
				case (6) { # eligible houses for PCM 
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_PCM = 0;
					my @houses_PCM;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						# presence of window on the south, south-west and south-east side
						switch ($new_data->{'wndw_count_front'}){
							case(1) {
								if ($new_data->{'wndw_count_front'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(2) {
								if ($new_data->{'wndw_count_front'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(3) {
								if ($new_data->{'wndw_count_left'} > 0 ) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(4) {
								if ($new_data->{'wndw_count_back'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(5) {
								if ($new_data->{'wndw_count_back'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(6) {
								if ($new_data->{'wndw_count_back'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(7) {
								if ($new_data->{'wndw_count_right'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}
							case(8) {
								if ($new_data->{'wndw_count_front'} > 0) {
									$houses_PCM[$count_PCM] = $new_data->{'file_name'};
									$count_PCM++;
									print $FILEOUT "$_ \n";
								}
							}  
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_PCM;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
				}
				case (7) { # eligible houses for CVB
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_CVB = 0;
					my @houses_CVB;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						# examine the existance of cooling system
						if (defined ($new_data->{'cooling_equip_type'} ) && $new_data->{'cooling_equip_type'} != 4) {
							# presence of window on the west, south, south-west, east and south-east side
							switch ($new_data->{'wndw_count_front'}){
								case(1) {
									if ($new_data->{'wndw_count_right'} > 0 || $new_data->{'wndw_count_left'} > 0 || $new_data->{'wndw_count_front'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(2) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_left'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(3) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_back'} > 0 || $new_data->{'wndw_count_left'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(4) {
									if ($new_data->{'wndw_count_left'} > 0 || $new_data->{'wndw_count_back'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(5) {
									if ($new_data->{'wndw_count_right'} > 0 || $new_data->{'wndw_count_left'} > 0 || $new_data->{'wndw_count_back'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(6) {
									if ($new_data->{'wndw_count_right'} > 0 || $new_data->{'wndw_count_back'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(7) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_back'} > 0 || $new_data->{'wndw_count_right'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
								case(8) {
									if ($new_data->{'wndw_count_front'} > 0 || $new_data->{'wndw_count_right'} > 0) {
										$houses_CVB[$count_CVB] = $new_data->{'file_name'};
										$count_CVB++;
										print $FILEOUT "$_ \n";
									}
								}
							} 
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_CVB;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
				}
				case (8) { # eligible houses for PV 
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_PV = 0;
					my @houses_PV;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						my $width;
						my @zones = qw (bsmt crawl main_1 main_2 main_3);
						my $last_zone;
						my $w_d_ratio = 1;
					
						# calculation width of all zones
						if (defined($new_data->{'exterior_width'} && $new_data->{'exterior_depth'})){
							
							if ($new_data->{'exterior_dimension_indicator'} == 0) {
								$w_d_ratio = sprintf ("%.2f", $new_data->{'exterior_width'}/ $new_data->{'exterior_depth'});
								if ($w_d_ratio < 0.66) {
									$w_d_ratio = sprintf ("%.2f",0.66);
								}
								elsif ($w_d_ratio > 1.5) {
									$w_d_ratio = sprintf ("%.2f",1.5);
								}
							}
							my $depth = sprintf("%6.2f", ($new_data->{'main_floor_area_1'} / $w_d_ratio) ** 0.5);
							
							foreach my $zone (@zones) {
								if ($zone =~ /^bsmt$|^crawl$/) {
									# Because bsmt walls are thicker, the bsmt or crawl floor area is typically a little less than the main_1 level. However, it is really not appropriate to expose main_1 floor area for this small difference.
									# Thus, if the difference between the main_1 and foundation floor area is less than 10% of them main_1 floor area, resize the foundation area to be equal to the main_1 floor area
									if ($new_data->{'main_floor_area_1'} - $new_data->{$zone . '_floor_area'} < 0.1 * $new_data->{'main_floor_area_1'}) {
										$new_data->{$zone . '_floor_area'} = $new_data->{'main_floor_area_1'};
									}
									$width->{$zone} = $new_data->{$zone . '_floor_area'} / $depth;	# determine width of zone based upon main_1 depth
								}
								elsif ($zone =~ /^main_(\d)$/) {
									# determine x from floor area and y
									$width->{$zone} = $new_data->{"main_floor_area_$1"} / $depth;	# determine width of zone based upon main_1 depth
									if ($width->{$zone} > 0) {
										$last_zone = $zone;
									}
								}
							}	
							# examine the existance of attic 
							
							if ($new_data->{'ceiling_flat_type'} == 2 && $new_data->{'attachment_type'} == 1) {
								  # if the front orientation of the house is south, south-east or south-west to have a ridgeline running west-east the width which is always front of the house should be more than depth
								if ($new_data->{'front_orientation'} == 3 ||  $new_data->{'front_orientation'} == 7) {
									
									if (($width->{'main_1'} < $depth) && ($w_d_ratio != 1)) {
										$houses_PV[$count_PV] = $new_data->{'file_name'};
										$count_PV++;
										print $FILEOUT "$_ \n";
									}
								}
								else {
									if ($width->{'main_1'} > $depth) {
										 $houses_PV[$count_PV] = $new_data->{'file_name'};
										  $count_PV++;
										  print $FILEOUT "$_ \n";
									}
								}
							}
							
							elsif  ($new_data->{'attachment_type'} == 4 && $new_data->{'ceiling_flat_type'} == 2) {
								unless ($new_data->{'front_orientation'} == 3 || $new_data->{'front_orientation'} == 7) {
									$houses_PV[$count_PV] = $new_data->{'file_name'};
									$count_PV++;
									print $FILEOUT "$_ \n";
								}
							}
							elsif ($new_data->{'ceiling_flat_type'} == 3) {
								if ($new_data->{'attachment_type'} == 2 || $new_data->{'attachment_type'} == 3) { # DR - left/right end house type
									if (($width->{$last_zone} * 2 / 3) >= 4){
										$houses_PV[$count_PV] = $new_data->{'file_name'};
										$count_PV++;
										print $FILEOUT "$_ \n";
									}
								}
							}
							
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_PV;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
				}
				case (9) {  # eligible houses for BIPV/T
					open (my $FILEOUT, '>', '../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv') or die ('../Eligible_houses/Eligible_Houses_Upgarde_'.$upgrade_names{$up}.'_'.$hse_names{$hse_type}.'_subset_'.$region_names{$region}.'.csv'); 	# open writable file
					my $count_BIPVT = 0;
					my @houses_BIPVT;
					my $count_total= 0;
					while (<$FILEIN>){
						($new_data, $_) = &data_read_up ($_, $new_data, $FILEOUT);
						if ($_ =~ /^\*data,/) { $count_total++;}
						my $width;
						my @zones = qw (bsmt crawl main_1 main_2 main_3);
						my $last_zone;
						# calculation width of all zones
						if (defined($new_data->{'exterior_width'} && $new_data->{'exterior_depth'})){
							my $w_d_ratio = sprintf ("%.2f", $new_data->{'exterior_width'}/ $new_data->{'exterior_depth'});
							my $depth = sprintf("%6.2f", ($new_data->{'main_floor_area_1'} / $w_d_ratio) ** 0.5);
							foreach my $zone (@zones) {
								if ($zone =~ /^bsmt$|^crawl$/) {
									# Because bsmt walls are thicker, the bsmt or crawl floor area is typically a little less than the main_1 level. However, it is really not appropriate to expose main_1 floor area for this small difference.
									# Thus, if the difference between the main_1 and foundation floor area is less than 10% of them main_1 floor area, resize the foundation area to be equal to the main_1 floor area
									if ($new_data->{'main_floor_area_1'} - $new_data->{$zone . '_floor_area'} < 0.1 * $new_data->{'main_floor_area_1'}) {
										$new_data->{$zone . '_floor_area'} = $new_data->{'main_floor_area_1'};
									}
									$width->{$zone} = $new_data->{$zone . '_floor_area'} / $depth;	# determine width of zone based upon main_1 depth
								}
								elsif ($zone =~ /^main_(\d)$/) {
									# determine x from floor area and y
									$width->{$zone} = $new_data->{"main_floor_area_$1"} / $depth;	# determine width of zone based upon main_1 depth
									if ($width->{$zone} > 0) {
										$last_zone = $zone;
									}
								}	
								
							};
							
								
							# examine the existance of attic and if the DR house is middle row attachment
							if ($new_data->{'ceiling_flat_type'} == 2 || $new_data->{'attachment_type'} == 4) {
# 								# next criteria is existance of DHW
								unless ($new_data->{'DHW_equip_type'} == 9){
# 									if the front orientation of the house is south, south-east or south-west to have a ridgeline running west-east the width which is always front of the house should be more than depth
									if ($new_data->{'front_orientation'} == 3 || $new_data->{'front_orientation'} == 7) {
										if ($width->{$last_zone} < $depth) {
											$houses_BIPVT[$count_BIPVT] = $new_data->{'file_name'};
											$count_BIPVT++;
											print $FILEOUT "$_ \n";
										}
									}
									else {
										if ($width->{$last_zone} > $depth) {
											$houses_BIPVT[$count_BIPVT] = $new_data->{'file_name'};
											$count_BIPVT++;
											print $FILEOUT "$_ \n";
										}
									}
								}
							}
							elsif ($new_data->{'ceiling_flat_type'} == 3) {
								if ($new_data->{'attachment_type'} == 2 || $new_data->{'attachment_type'} == 3) { # DR - left/right end house type
									if (($width->{$last_zone} * 2 / 3) >= 4 && ($new_data->{'DHW_equip_type'} != 9)){
										$houses_BIPVT[$count_BIPVT] = $new_data->{'file_name'};
										$count_BIPVT++;
										print $FILEOUT "$_ \n";
									}
								}
							}
						}
					}
					close $FILEOUT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}} = $count_BIPVT;
					$count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'} = $count_total;
					push (@line, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{$upgrade_names{$up}}, $count->{$hse_names{$hse_type}}->{$region_names{$region}}->{'total'});
					print $COUNT CSVjoin (@line)."\n";
				}
				unless ($upgrade_names{$up} =~ /^WTM/){ 
					close $FILEIN;
				}
			}
		};
	};
};
close $COUNT;

# 
# ====================================================================
# Subroutines:
# data_read_up
# This subroutine is similar to one_data_line subroutine in General.pm.
# It just doesn't remove *header and *data tag.
# ====================================================================

sub data_read_up {
	my $line = shift;
	# shift the existing data which may include the array of header info at $existing_data->{'header'}
	my $old_data = shift;
	my $file = shift;

	my $present_data;	# create an crosslisting hash reference

	$line = &rm_EOL_and_trim($line);
	if (defined ($old_data->{'header'})) {
		$present_data->{'header'} = $old_data->{'header'};
	}
		
	# Check to see if header has not yet been encountered. This will fill out $new_data once and in subsequent calls to this subroutine with the same file the header will be set above.
	if ($line =~ /^\*header,/) {	
		$present_data->{'header'} = [CSVsplit($line)];  # split the header into an array
		print $file "$line \n";
	}
		
	# Check for the existance of the data tag, and if so store the data and return to the calling program.
	elsif ($line =~ /^\*data,/) {	
		# create a hash slice that uses the header and data
		# although this is a complex structure it simply creates a hash with an array of keys and array of values
		# @{$hash_ref}{@keys} = @values
		@{$present_data}{@{$present_data->{'header'}}} = CSVsplit($line);
	}
	# We have successfully identified a line of data, so return this to the calling program, complete with the header information to be passed back to this routine
	return ($present_data, $line);

};


# ====================================================================
# total_surface_area
# This subroutine calculate area of each side.
# ====================================================================

sub total_surface_area {
	my $x = shift;
	my $y = shift;
	my $z = shift;
	my $area;

	my @sides = qw (front back right left);

	foreach my $surface (@sides) {
		$area->{$surface} = 0;
		if ($surface =~ /^front$|^back$/){
			$area->{$surface} = $x * $z + $area->{$surface};
		}
		else {
			$area->{$surface} = $y * $z + $area->{$surface};
		}
	}
	return ($area);
};
