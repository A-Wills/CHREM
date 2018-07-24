# ====================================================================
# Cross_reference.pm
# Author: Lukas Swan
# Date: July 2009
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# cross_ref_readin: a subroutine that reads in information from a tagged file and stores it in a hash reference
# key_XML_readin: a subroutine that reads in XML information with specific ForceArray information
# ====================================================================

# Declare the package name of this perl module
package Cross_reference;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use XML::Simple;	# to parse the XML databases
use General;

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(cross_ref_readin key_XML_readin);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();


# ====================================================================
# cross_ref_readin
# This routines reads in cross referencing file that are tagged with 
# *header and *data information. It stores the information as hash references
# using the first column after the tag as the key. It then returns this 
# reference to the calling script.
# ====================================================================

sub cross_ref_readin {
	# shift the passed file path
	my $file = shift;
	# show the user that we are working on this file. Note that the system call is used due to timing which can lead to a print statment not showing up until the readin is complete
	system ("printf \"Reading $file\"");

	# Open and read the crosslisting, note that the file handle below is a variable so that it simply goes out of scope
	open (my $FILE, '<', $file) or die ("can't open datafile: $file");

	my $cross_ref;	# create an crosslisting hash reference

	while (<$FILE>) {
		$_ = rm_EOL_and_trim($_);
		
		if ($_ =~ s/^\*header,\w+,//) {	# header row has *header tag, so remove this portion, and the key (first header value) leaving the CSV information
			$cross_ref->{'header'} = [CSVsplit($_)];	# split the header into an array
		}
			
		elsif ($_ =~ s/^\*data,//) {	# data lines will begin with the *data tag, so remove this portion, leaving the CSV information
			@_ = CSVsplit($_);	# split the data onto the @_ array
			my $key = shift;	# shift off the first element and use it as the key to the hash
			
			# create a hash slice that uses the header and data array
			# although this is a complex structure it simply creates a hash with an array of keys and array of values
			# @{$hash_ref}{@keys} = @values
			@{$cross_ref->{'data'}->{$key}}{@{$cross_ref->{'header'}}} = @_;
		};
	};
	
	# notify the user we are complete and start a new line
	print " - Complete\n";
	
	# Return the hash reference that includes all of the header and data
	return ($cross_ref);
};


# ====================================================================
# key_XML_readin
# This subroutine recieves the path to an XML file and a reference to 
# an array of labels that should be forced into an array. It then prints
# some user info and reads in all of the XML info with attention paid to
# the ForceArray
# ====================================================================

sub key_XML_readin {
	# shift the passed file path
	my $file = shift;
	# shift the reference to the array that holds the ForceArray labels
	my $ForceArray = shift;
	
	# show the user that we are working on this file. Note that the system call is used due to timing which can lead to a print statment not showing up until the readin is complete
	system ("printf \"Reading $file\"");
	
	my $cross_ref = XMLin($file, ForceArray => $ForceArray);	# readin the xml information with the appropriate force array (note that ForceArray requires an array reference which is provided by the shift above. If this later become longhand array style then you have to provide a unnamed referece i.e. ForceArray => [@array])

	# notify the user we are complete and start a new line
	print " - Complete\n";
	
	# Return the hash reference that includes all of the header and data
	return ($cross_ref);
};


# Final return value of one to indicate that the perl module is successful
1;
