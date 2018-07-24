# ====================================================================
# General.pm
# Author: Lukas Swan
# Date: July 2009
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# rm_EOL_and_trim: a subroutine that removes all end of line characters (DOS, UNIX, MAC) and trims leading/trailing whitespace
# hse_types_and_regions_and_set_name: a subroutine that reads in user input and stores returns the house type and region and set name information
# header_line: a subroutine that reads a file and returns the header as an array within a hash reference 'header'
# one_data_line: a subroutine that reads a file and returns a line of data in the form of a hash ref with header field keys
# one_data_line_keyed: similar but stores everything at a hash key (e.g. $data->{'data'} = ...
# largest and smallest: simple subroutine to determine and return the largest or smallest value of a passed list
# check_range: checks value against min/max and corrects if require with a notice
# set_issue: simply pushes the issue into the issues hash reference in a formatted method
# print_issues: subroutine prints out the issues encountered by the script during execution
# distribution_array: returns an array of values distributed in accordance with a hash to a defined number of elements
# die_msg: reports a message and dies
# replace: reads through an array and replaces a matching line with new information
# insert: reads through an array and inserts a matching line with new information
# ====================================================================

# Declare the package name of this perl module
package Statistics;

# Declare packages used by this perl module
use strict;
use General;
use Data::Dumper;
use List::Util ('shuffle');
use CSV;	# CSV-2 (for CSV split and join, this works best)

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(one_data_line_res);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# one_data_line
# This subroutine is similar to a complete tagged file readin, but
# instead only reads in one data line at a time. This is to be used
# with very large files that require processing one line at a time.
# The CSDDRD is such a file.

# Both the filehandle and existing data hash reference are passed to 
# the subroutine. The existing data hash is examined to see if header 
# information is present and if so this is used. This is because this
# subroutine will forget the header information as soon as it returns.

# The file read is similar to an entire read, but stores all items, and
# does not use the second element as an identifier, because there is only
# one data hash.

# NOTE:Because this is intended for the CSDDRD and it is nice to keep the
# name short, all of the data is stored at the base hash reference (i.e.
# at $CSDDRD->{HERE}, not at $CSDDRD->{'data'}->{HERE}). Therefore, the 
# header is stored as an ordered array at the location header (i.e. 
# $CSDDRD->{'header'}->[header array is here]

# This subroutine returns either data (to be used in a while loop) or
# returns a 0 for False so that the calling while loop terminates.
# ====================================================================

sub one_data_line_res {
	# shift the passed file path
	my $FILE = shift;
	# shift the existing data which may include the array of header info at $existing_data->{'header'}
	my $existing_data = shift;

	my $new_data;	# create an crosslisting hash reference

	if (defined ($existing_data->{'field'})) {
		$new_data->{'field'} = $existing_data->{'field'};
	}

	# Cycle through the File until suitable data is encountered
	while (<$FILE>) {

		$_ = rm_EOL_and_trim($_);
		
		# Check to see if header has not yet been encountered. This will fill out $new_data once and in subsequent calls to this subroutine with the same file the header will be set above.
		if ($_ =~ s/^\*field,//) {	# header row has *header tag, so remove this portion, leaving ALL remaining CSV information
			$new_data->{'field'} = [CSVsplit($_)];	# split the header into an array
		}
		
		# Check for the existance of the data tag, and if so store the data and return to the calling program.
		elsif ($_ =~ s/^\*data,//) {	# data lines will begin with the *data tag, so remove this portion, leaving the CSV information
			
			# create a hash slice that uses the header and data
			# although this is a complex structure it simply creates a hash with an array of keys and array of values
			# @{$hash_ref}{@keys} = @values
			@{$new_data}{@{$new_data->{'field'}}} = CSVsplit($_);

			# We have successfully identified a line of data, so return this to the calling program, complete with the header information to be passed back to this routine
			return ($new_data);
		}
		
	
	# No data was found on that iteration, so continue to read through the file to find data, until the end of the file is encountered
	};
	
	
	# The end of the file was reached, so return a 0 (false) so that the calling routine moves onward
	return (0);
};

# Final return value of one to indicate that the perl module is successful
1;
