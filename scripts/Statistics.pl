#!/usr/bin/perl
# 
#====================================================================
# Statistics.pl
# Author:    Adam Wills
# Date:      Jan 2015
# Copyright: Carleton University
#
#
# INPUT USE:
# filename.pl [house type, if 0 then set generated from City_Gen.pl] [region number] [set_name] 
#
# DESCRIPTION:
# This script aquires results


#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;


use CSV;	# CSV-2 (for CSV split and join, this works best)
use File::Path;	# File-Path-2.04 (to create directory trees)
use File::Copy;	# (to copy the input.xml file)
use XML::Simple;	# to parse the XML databases for esp-r and for Hse_Gen
use Data::Dumper;	# to dump info to the terminal for debugging purposes
use Switch;
use Storable  qw(dclone);
use Hash::Merge qw(merge);
use POSIX;

use lib qw(./modules);
use General;
use Cross_reference;
use Database;
use Results;
use Statistics;

$Data::Dumper::Sortkeys = \&order;

Hash::Merge::specify_behavior(
	{
		'SCALAR' => {
			'SCALAR' => sub {$_[0] + $_[1]},
			'ARRAY'  => sub {[$_[0], @{$_[1]}]},
			'HASH'   => sub {$_[1]->{$_[0]} = undef},
		},
		'ARRAY' => {
			'SCALAR' => sub {[@{$_[0]}, $_[1]]},
			'ARRAY'  => sub {[@{$_[0]}, @{$_[1]}]},
			'HASH'   => sub {[@{$_[0]}, $_[1]]},
		},
		'HASH' => {
			'SCALAR' => sub {$_[0]->{$_[1]} = undef},
			'ARRAY'  => sub {[@{$_[1]}, $_[0]]},
			'HASH'   => sub {Hash::Merge::_merge_hashes($_[0], $_[1])},
		},
	}, 
	'Merge where scalars are added, and items are (pre)|(ap)pended to arrays', 
);

# --------------------------------------------------------------------
# Declare the global variables
# --------------------------------------------------------------------

my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name;   # declare set name
my $SrcFile;	# declare source file for city gen
my @houses_desired; # declare an array to store the house names or part of to look
my @Headers = 'house_name'; # declare an array to store the output headers
my $IsRes = 0; # declare if there is a results file (determined by key entries)
my $StoreHse;  # declare variable to store house name

# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------

if (@ARGV <= 2) {die "At least three arguments are required: house_type region and set_name\n";};	# check for proper argument count

($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name(shift (@ARGV), shift (@ARGV), shift (@ARGV));
$set_name = '_' . $set_name;

# -----------------------------------------------
# Develop the statistics reference keys
# -----------------------------------------------
my $StatVars = &key_XML_readin('../keys/Stats_key.xml', [1]);

# -----------------------------------------------
# Open Statistics File for writing
# -----------------------------------------------
my $filename = "../summary_files/Statistics$set_name" . '_Houses.csv';
open (my $StatOut, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

# -----------------------------------------------
# Prep stats headers 
# -----------------------------------------------

while( my( $SrcFile, $value ) = each $StatVars->{'FileSrc'} ){
        while( my( $fields, $list ) = each $value->{'includeVal'} ){
            if ($SrcFile eq 'CSDDRD') {
                my $Name = $list->{'field'};
                push (@Headers, $Name);
            }
            elsif ($SrcFile eq 'ResFile') {
                my $Name = $list->{'field'};
                push (@Headers, $Name);
                $IsRes = 1;
            }
            else {die "Invalid source file entry in Stats_key.xml\n";};
        }
}       
print $StatOut CSVjoin(@Headers) . "\n";


# -----------------------------------------------
# Begin collecting data from external files
# -----------------------------------------------
foreach my $hse_type (values (%{$hse_types})) {
	foreach my $region (values (%{$regions})) {
        my $path = "../$hse_type$set_name/$region/";
        opendir( my $DIR, $path );
        while ( my $entry = readdir $DIR ) {
            next unless -d $path . '/' . $entry;
            next if $entry eq '.' or $entry eq '..';
            push (@houses_desired, $entry);
        }
        closedir $DIR;
        # print Dumper @houses_desired;

        # Open the data source files from the CSDDRD - path to the correct CSDDRD type and region file
        my $file = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region;
        my $ext = '.csv';
        my $CSDDRD_FILE;
        open ($CSDDRD_FILE, '<', $file . $ext) or die ("Can't open datafile: $file$ext");	# open readable file
        my $CSDDRD; # declare a hash reference to store the CSDDRD data. This will only store one house at a time and the header data
            
        RECORD: while ($CSDDRD = &one_data_line($CSDDRD_FILE, $CSDDRD)) {	# go through each line (house) of the file
                
                # flag to indicate to proceed with house build
                my $desired_house = 0;
                # cycle through the desired house names to see if this house matches. If so continue the house build
                foreach my $house_name (@houses_desired) {
                    # it matches, so set the flag
                    if ($CSDDRD->{'file_name'} =~ /^$house_name/) {
                    $desired_house = 1;
                    $StoreHse = $house_name;
                    };
                };
            
                # if the flag was not set, go to the next house record
                if ($desired_house == 0) {next RECORD};
                
                #print $StatOut CSVjoin($CSDDRD->{'file_name'}) . "\n";
                my @OutArray=("$StoreHse");
                
                # house file coordinates to print when an error is encountered
                my $coordinates = {'hse_type' => $hse_type, 'region' => $region, 'file_name' => $CSDDRD->{'file_name'}};
                
                # remove the trailing HDF from the house name and check for bad filename
                $CSDDRD->{'file_name'} =~ s/.HDF$// or  &die_msg ('RECORD: Bad record name (no *.HDF)', $CSDDRD->{'file_name'}, $coordinates);
                
                if ($IsRes == 0) { # There is no results file to read

                    while( my( $SrcFile, $value ) = each $StatVars->{'FileSrc'} ){
                            while( my( $fields, $list ) = each $value->{'includeVal'} ){
                                if ($SrcFile eq 'CSDDRD') {
                                    # Gather CSDDRD Data
                                    my $Name = $list->{'field'};
                                    my $Rec = $CSDDRD->{$Name};
                                    #print "$Name is $Rec\n";
                                    push (@OutArray, $Rec);
                                }
                                else {die "Invalid source file entry in Stats_key.xml\n";};
                            };
                    };

                    print $StatOut CSVjoin(@OutArray) . "\n";
                
                }
                elsif ($IsRes == 1) { # There is also a results file to read

                    my $RES_FILE;
                    my $RES; # declare a hash reference to store the Results data. This will only store one house at a time and the header data
                    my $file = '../summary_files/Results' . $set_name . '_Houses';
                    open ($RES_FILE, '<', $file . $ext) or die ("Can't open results file: $file$ext");	# open readable file

                    RESRECORD: while ($RES = &one_data_line_res($RES_FILE, $RES)) {	# go through each line (house) of the file
                        # flag to indicate to proceed with house build
                        my $desired_house2 = 0;
                        # it matches, so set the flag
                        if ($RES->{'house_name'} =~ /^$StoreHse/) {$desired_house2 = 1};
                        
                        # if the flag was not set, go to the next house record
                        if ($desired_house2 == 0) {next RESRECORD};
                        
                        while( my( $SrcFile, $value ) = each $StatVars->{'FileSrc'} ){
                                while( my( $fields, $list ) = each $value->{'includeVal'} ){
                                    if ($SrcFile eq 'CSDDRD') {
                                        # Gather CSDDRD Data
                                        my $Name = $list->{'field'};
                                        my $Rec = $CSDDRD->{$Name};
                                        #print "$Name is $Rec\n";
                                        push (@OutArray, $Rec);
                                    }
                                    elsif ($SrcFile eq 'ResFile') {
                                        # Gather Data from Results file
                                        my $Name = $list->{'field'};
                                        my $Rec = $RES->{$Name};
                                        push (@OutArray, $Rec);
                                    }
                                    else {die "Invalid source file entry in Stats_key.xml\n";};
                                };
                            };
                        }; # end of the while loop through the RES-> (end of RESRECORD)
                        close $RES_FILE;
                        print $StatOut CSVjoin(@OutArray) . "\n";
                    }; 
                    
                }; # end of the while loop through the CSDDRD-> (end of RECORD)
                close $CSDDRD_FILE; 
    };	
}
close $StatOut;
            
