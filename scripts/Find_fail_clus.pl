#!/usr/bin/perl
# 
#====================================================================
# Find_fail_clus.pl
# Author:    Sara Nikoofard
# Date:      Jan 2012
# Copyright: Dalhousie University
#
# DESCRIPTION:
# This script is called after simulation finished for all houses to find
# the files that are not ran properly.
#
# it gets the input and output file names without .csv
#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;
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
# Declare the global variables
#--------------------------------------------------------------------
my $set_name;
my @houses_desired; # declare an array to store the house names or part of to look
my $file_in;
my $file_out;
#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 2) {die "A minimum of two argument is required input_file output_file [house names]";};
	$file_in = shift(@ARGV);
	$file_out = shift(@ARGV);
	# Provide support to only simulate some houses
	@houses_desired = @ARGV;
	# In case no houses were provided, match everything
	if (@houses_desired == 0) {@houses_desired = '.'};
	
};

#--------------------------------------------------------------------
# Delete the existing out put file
#--------------------------------------------------------------------

foreach my $file (<../summary_files/*>) { # Loop over the files
	my $check = $file_out;
	if ($file =~ /$check/) {unlink $file;};
};

#--------------------------------------------------------------------
# Identify the house folders that failed in simulation
#--------------------------------------------------------------------
my $file_in1= '../summary_files/'.$file_in;
my $ext = '.csv';
my $file_out1 = '../summary_files/'.$file_out;
my $FILE_INPUT;
open ($FILE_INPUT, '<', $file_in1.$ext) or die ("can't open $file_in1$ext! \n"); # open the input file to read
my $FILE_OUTPUT;
open ($FILE_OUTPUT, '>', $file_out1.$ext) or die ("can't open $file_out1$ext! \n"); # open the output file to write

while (<$FILE_INPUT>) {
	$_ = rm_EOL_and_trim($_); # Clean up the folder name
	$_ =~ /^\.\.\/\S+\/\S+\/(\w{10})$/;
	my $house_name = $1;  
	my $file_core = grep (/core/, <$_/*>);
	chdir ($_);
	
	if ((!-e ($house_name.'.temperature')) || (-e $house_name.'.res')) {
		my $bps_size = 0;
		$bps_size = -s "$house_name.bps";
		if ($bps_size > 0) {
			print $FILE_OUTPUT "$_ \n";
		}
	}
	if ($file_core) {
		system ("rm core.*");
	}
	chdir ("../../../scripts");
}

close ($FILE_INPUT);
close ($FILE_OUTPUT);