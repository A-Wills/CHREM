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
package General;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;
use List::Util ('shuffle');

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(order array_order rm_EOL_and_trim hse_types_and_regions_and_set_name header_line one_data_line one_data_line_keyed largest smallest check_range set_issue print_issues distribution_array die_msg replace insert capitalize_first_letter capitalize_first_letter_each_word);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# array_order
# This subroutine simply front/back ends the order subroutine with arrays
# i.e. array in and array out, no references required
#
# ====================================================================

sub array_order {
	# Run the order subroutine by providing the @_ array and then derefence the returned array reference into an array and return this to the calling program
	return (@{&order([@_])});
};

# ====================================================================
# order
# This subroutine orders and returns an array reference based on either
# an array reference input or a hash reference input
# It also has the option for a preference array reference input which
# may be used to provide preferred ordering on the basis of matching
# the beginning of the string and discard array reference input which
# will discard any items that meet the criteria. Note that a preference
# array reference must be provided if a discard array reference is to be 
# provided. However, the preference array may be empty. Note that the 
# discard comes after preference so that a blank '' may be used to discard
# all remaining items.

# For example:
# order([1 2 20 10]) will return [1 2 10 20] (note: numeric based []<=>)
# order([test 1 2 20 10]) will return [1 10 2 20 test] (note: alphanumeric based [cmp])
# order({'one' => 1, 'two' => 2}) will return [one two]
# order({'one' => 1, 'two' => 2}, [t]) will return [two one]
#
# A NOTE: Data::Dumper requires a subroutine reference to this, but that makes it 
# difficult to provide a preference list.
# The solutions is as follows:
#
# local $Data::Dumper::Sortkeys = sub {&order(shift, $preference_array_reference)};
# print Dumper $data;
#
# If there is no preference for Data:Dumper then it simplifies to:
# local $Data::Dumper::Sortkeys = \&order;
# print Dumper $data;
#
# ====================================================================

sub order {
	# The first passed element is a reference of some type (hash or array)
	my $data = shift;
	# Declare a preference array ref
	my $prefer = [];
	# If there is a another passed element, shift the array reference of preference
	if (@_) {$prefer = shift};
	# Declare a discard array ref
	my $discard = [];
	# If there is a another passed element, shift the array reference of preference
	if (@_) {$discard = shift};
	
	
	# Declare an array to store the data list that we want sort
	my @array;
	
	# If the data element is an array or hash, develop array by that type
	if (ref $data eq 'ARRAY') {@array = @{$data};}
	elsif (ref $data eq 'HASH') {@array = keys %{$data};}
	else {
		print "Bad reference data type passed to order - must be either ARRAY or HASH ref - see below information\n";
		print "Data is:\n";
		print Dumper $data;
		print "Prefer is:\n";
		print Dumper $prefer;
		print "Discard is:\n";
		print Dumper $discard;
		return(); # Return to the program so that it hopefully flags and error. If we die here instead we don't know what calling feature was the issue.
	};
	
	# Assume the @array is full of numeric values
	my $data_type = 'NUMERIC';
	
	# Check all of the array elements to see if they are numeric.
	CHECK_TYPE: foreach my $element (@array) {
		# Check to see if numeric is whole number (XX), whole w/ decimal (XX.), decimal w/o zero (.XX) or floating point (XX.X)
		unless ($element =~ /^\d+$|^\d+\.|\.\d+$|^\d+\.\d+$/) {
			# it is not numeric, so set to alpha and jump out
			$data_type = 'ALPHA';
			last CHECK_TYPE;
		};
	};
	
	# Sort the array according to the appropriate type
	if ($data_type eq 'NUMERIC') {@array = sort {$a <=> $b} @array;}
	elsif ($data_type eq 'ALPHA') {@array = sort {$a cmp $b} @array;};

	# Declare an ordered array;
	my @ordered;
	
	# Cycle over the preferred array and transfer elements of the @array to @ordered if they match. Note that this method makes only allows an element to match once and also protects it from the discard below.
	foreach my $pref (@{$prefer}) { # Cycle over the preferred items in order
		my @remaining; # Declare a remaining array
		while (@array) { # Continue over the array until it is exhausted
			my $item = shift (@array); # Shift the first item off the array
			if ($item =~ /^$pref/) {push(@ordered, $item);} # If it matches the preference then store it in the ordered array
			else {push(@remaining, $item);}; # If it does not match then put it in the remaining array
		};
		@array = @remaining; # Set the array equal to remaining so it may be used again, although it has had the preferred matching elements removed
	};

	# Cycle over the discard  but only remove elements from @array, protecting the ordered elements
	foreach my $element (@{$discard}) {
		@array = grep(!/^$element/, @array); # The exclamation sign says store all elements that do not match (so discards do not get stored).
	};
	
	# Add on the remaining @array to the ordered array for returning
	push(@ordered, @array);

	# Return the ordered array reference
	return ([@ordered]);
};




# ====================================================================
# rm_EOL_and_trim
# This subroutine removes all end of line characters (DOS, UNIX, MAC) 
# and trims leading/trailing whitespace
# ====================================================================

sub rm_EOL_and_trim {

	foreach my $line (@_) {
	
		# chomp the end of line characters off (dos, unix, or mac)
		$line =~ s/\r\n$|\n$|\r$//g;
		
		# remove leading and trailing whitespace
		$line =~ s/^\s+|\s+$//g;
		
		# remove common excess delimiters at the end of the line
		$line =~ s/,+$|\t+$|;+$//g;
	
	};
	
	# return the string(s)
	# Check to see if there is only one element, if so return a scalar
	if (@_ == 1) {
		return (shift);
	}
	# Otherwise it is a multielement array, so return an array
	else {
		return (@_);
	};
};


# ====================================================================
# hse_types_and_regions_and_set_name
# This subroutine recieves the user specified house type and region and set name. It interprets the appropriate House Types
# (e.g. 1 => 1-SD) and Regions (e.g. 2 => 2-QC) and outputs these back to
# the calling script. 
# It will also issue warnings if the input is malformed.
# ====================================================================

sub hse_types_and_regions_and_set_name {
	my @variables;
	my $user_input;
	if (@_ == 2) {
		@variables = ('House_Type', 'Region');
		@{$user_input}{@variables} = @_;
	}
	elsif (@_ == 3) {
		@variables = ('House_Type', 'Region', 'set_name');
		@{$user_input}{@variables} = @_;
# 		$user_input->{'set_name'} = '_' . $user_input->{'set_name'};
	}
	else {die "ERROR hse_types_and_regions_and_set_name subroutine requires two or three user inputs to be passed\n";};

	# common house type and region names, note that they are specified using the ordered array from above
	my $define_names->{$variables[0]} = {1 => '1-SD', 2 => '2-DR'};	# house type names
	$define_names->{$variables[0] . 'other'} = {3 => '3-CB', 4 => '4-EX'};	# other house type names for use with test or calibration
	$define_names->{$variables[1]} = {1, '1-AT', 2, '2-QC', 3, '3-OT', 4, '4-PR', 5, '5-BC'};	# region names
	$define_names->{$variables[1] . 'other'} = {6 => '6-CB', 7 => '7-EX'};	# other region names for use with test or calibration


	# declare a storage hash ref of the utilized house types and regions based on user input
	my $utilized;

	# cycle through the two variable types (house types and regions)
	foreach my $variable (@variables) {
		if ($variable eq 'set_name') {
			$utilized->{$variable} = $user_input->{$variable};
		}
	
		# Check to see if the user wants all the names for that variable
		elsif ($user_input->{$variable} eq '0') {
			$utilized->{$variable} = $define_names->{$variable};	# set the utilized equal to the entire definition hash for this variable
		}
		
		# the user should have specified the exact types and regions they want, seperated by a forward slash
		else {
			my @values = split (/\//, $user_input->{$variable});	# split the input based on a forward slash

			# cycle through the resulting elements
			foreach my $value (@values) {
				# verify that the requested house type or region exists and then set it on the utilized array for this variable
				if (defined ($define_names->{$variable}->{$value})) {	# check that region exists
					$utilized->{$variable}->{$value} = $define_names->{$variable}->{$value}; # it does so add it to the utilized
				}
				
				# There are other names for test and calibration - check these
				elsif (defined ($define_names->{$variable . 'other'}->{$value})) {	# check that region exists in the 'other' version
					$utilized->{$variable}->{$value} = $define_names->{$variable . 'other'}->{$value}; # it does so add it to the utilized
				}
				
				# the user input does not match the definitions, so organize the definitions and return an error message to the user
				else {
					my @keys = sort {$a cmp $b} keys (%{$define_names->{$variable}});	# sort for following error printout
					die "$variable argument must be one or more of the following numeric values seperated by a \"/\": 0 @keys\n";	# error printout
				};
			};
		};
	};
	
	# Return the ordered hash slice so that the house type hash is first, followed by the region hash
	return (@{$utilized}{@variables});
};


# ====================================================================
# header_line
# This subroutine is similar to a one_data_line, but
# instead only reads in the header.

# The header is stored as an ordered array at the location header (i.e. 
# $CSDDRD->{'header'}->[header array is here]

# This subroutine returns either header or
# returns a 0 for False so that the calling while loop terminates.
# ====================================================================

sub header_line {
	# shift the passed file path
	my $FILE = shift;

	my $new_data;	# create an crosslisting hash reference

	# Cycle through the File until suitable data is encountered
	while (<$FILE>) {

		$_ = rm_EOL_and_trim($_);
		
		# Check to see if header has not yet been encountered. This will fill out $new_data once
		if ($_ =~ s/^\*header,//) {	# header row has *header tag, so remove this portion, leaving ALL remaining CSV information
			$new_data->{'header'} = [CSVsplit($_)];	# split the header into an array
			# We have successfully identified the header, so return this to the calling program
			return ($new_data);
		}
	
	# No header was found on that iteration, so continue to read through the file to find data, until the end of the file is encountered
	};
	

	# The end of the file was reached, so return a 0 (false) so that the calling routine moves onward
	return (0);
};




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

sub one_data_line {
	# shift the passed file path
	my $FILE = shift;
	# shift the existing data which may include the array of header info at $existing_data->{'header'}
	my $existing_data = shift;

	my $new_data;	# create an crosslisting hash reference

	if (defined ($existing_data->{'header'})) {
		$new_data->{'header'} = $existing_data->{'header'};
	}

	# Cycle through the File until suitable data is encountered
	while (<$FILE>) {

		$_ = rm_EOL_and_trim($_);
		
		# Check to see if header has not yet been encountered. This will fill out $new_data once and in subsequent calls to this subroutine with the same file the header will be set above.
		if ($_ =~ s/^\*header,//) {	# header row has *header tag, so remove this portion, leaving ALL remaining CSV information
			$new_data->{'header'} = [CSVsplit($_)];	# split the header into an array
		}
		
		# Check for the existance of the data tag, and if so store the data and return to the calling program.
		elsif ($_ =~ s/^\*data,//) {	# data lines will begin with the *data tag, so remove this portion, leaving the CSV information
			
			# create a hash slice that uses the header and data
			# although this is a complex structure it simply creates a hash with an array of keys and array of values
			# @{$hash_ref}{@keys} = @values
			@{$new_data}{@{$new_data->{'header'}}} = CSVsplit($_);

			# We have successfully identified a line of data, so return this to the calling program, complete with the header information to be passed back to this routine
			return ($new_data);
		}
		
	
	# No data was found on that iteration, so continue to read through the file to find data, until the end of the file is encountered
	};
	
	
	# The end of the file was reached, so return a 0 (false) so that the calling routine moves onward
	return (0);
};



# ====================================================================
# one_data_line_keyed
#

sub one_data_line_keyed {
	# shift the passed file path
	my $FILE = shift;
	# shift the existing data which may include the array of header info at $existing_data->{'header'}
	my $existing_data = shift;

	my $new_data;	# create an crosslisting hash reference

	if (defined ($existing_data->{'header'})) {
		$new_data->{'header'} = $existing_data->{'header'};
	}

	# Cycle through the File until suitable data is encountered
	while (<$FILE>) {

		$_ = rm_EOL_and_trim($_);
		
		# Check to see if header has not yet been encountered. This will fill out $new_data once and in subsequent calls to this subroutine with the same file the header will be set above.
		if ($_ =~ s/^\*(header),//) {	# header row has *header tag, so remove this portion, leaving ALL remaining CSV information
			$new_data->{$1} = [CSVsplit($_)];	# split the header into an array
			push(@{$new_data->{'order'}},$1);
		}
		
		# Check for the existance of the data tag, and if so store the data and return to the calling program.
		elsif ($_ =~ s/^\*(\w+),//) {	# data lines will begin with the *data tag, so remove this portion, leaving the CSV information
			my $tag = $1;
			if ($tag =~ /unit|min|max|var|data/) {
				# create a hash slice that uses the header and data
				# although this is a complex structure it simply creates a hash with an array of keys and array of values
				# @{$hash_ref}{@keys} = @values
				@{$new_data->{$tag}}{@{$new_data->{'header'}}} = CSVsplit($_);
				
				if ($tag =~ /data/) {
					# We have successfully identified a line of data, so return this to the calling program, complete with the header information to be passed back to this routine
					return ($new_data);
				}
				else {
					push(@{$new_data->{'order'}},$tag);
				};
			}
			else {
				$new_data->{$tag} = [CSVsplit($_)];	# split the into an array
				push(@{$new_data->{'order'}},$tag);
			};
		}
		
		else {return (0)};
		
# 		print Dumper $new_data;
	
	# No data was found on that iteration, so continue to read through the file to find data, until the end of the file is encountered
	};
	
	
	# The end of the file was reached, so return a 0 (false) so that the calling routine moves onward
	return (0);
};

# ====================================================================
# largest and smallest
# The following two subroutines simply examine the passed list and return
# either the largest or smallest value in that list
# ====================================================================

sub largest {	# subroutine to find the largest value of the provided list
	my $value = shift;	# set equal to the first value
	foreach my $test_value (@_) {
		if ($test_value > $value) {
			$value = $test_value;
		};
	};
	return ($value);
};

sub smallest {	# subroutine to find the smallest value of the provided list
	my $value = shift;	# set equal to the first value
	foreach my $test_value (@_) {
		if ($test_value < $value) {
			$value = $test_value;
		};
	};
	return ($value);
};


# ====================================================================
# check_range
# This subroutine checks a value against a min/max range and sets the
# value to either if required. It will note this in the $issues hash ref
# ====================================================================

sub check_range {
	my $format = shift;
	my $value = sprintf($format, shift);	# key to check for values
	my $min = sprintf($format, shift);
	my $max = sprintf($format, shift);
	my $area = shift;
	my $coordinates = shift;
	my $issues = shift;
	
	# check the minimum and add it to the hash ref if so
	if ($value < $min) {
		if ($area =~ /^Door (\w+) (\d)$/) {
			$issues = set_issue("%s", $issues, 'Door', "$1 less than minimum $min, setting to the minimum value (Door_# house_value house_name)", "$2 $value", $coordinates);
		}
		elsif ($area =~ /^CONSTRUCTION layer conductivity$/) {
			$issues = set_issue("%s", $issues, $area, "Less than maximum value of layer conductivity (specified min_allowable house_name)", "$value $min", $coordinates);
		}
		else {
			$issues = set_issue($format, $issues, $area, "Less than minimum $min, setting to the minimum value", $value, $coordinates);
		};
	
		return ($min, $issues);
	}
	# check the max and add it to the hash ref if so
	elsif ($value > $max) {
		if ($area =~ /^WINDOWS Available Area/) {
			$issues = set_issue("%s", $issues, $area, 'Greater than available, setting to the available value (window_area available_area house_name)', "$value $max", $coordinates);
		}
		elsif ($area =~ /^Door (\w+) (\d)$/) {
			$issues = set_issue("%s", $issues, 'Door', "$1 greater than maximum $max, setting to the maximum value (Door_# house_value house_name)", "$2 $value", $coordinates);
		}
		elsif ($area =~ /^Foundation floor area size is N\/A to main floor area$/) {
			$issues = set_issue("%s", $issues, 'Foundation Floor Area', "Foundation Floor Area greater than Main_1 Floor, setting to the Main_1 value (foundation_value main_1_value house_name)", "$value $max", $coordinates);
		}
		elsif ($area =~ /^BASESIMP height above grade$/) {
			$issues = set_issue("%s", $issues, $area, "Greater than maximum value of wall height minus 0.65 m (specified max_allowable house_name)", "$value $max", $coordinates);
		}

		else {
			$issues = set_issue($format, $issues, $area, "Greater than maximum $max, setting to the maximum value", $value, $coordinates);
		};
		
		return ($max, $issues);
	};
	return ($value, $issues);
};


# ====================================================================
# set_issue
# This subroutine simply puts the issue information into the issues variable
# It is simply to save a little line space in the script
# ====================================================================

sub set_issue {
	my $format = shift;
	my $issues = shift;
	my $issue = shift;
	my $problem = shift;
	my $value = sprintf($format, shift);
	my $coordinates = shift;
	
	#set_issue($issues, $issue_area, $problem, $value, $coordinates);
	
	$issues->{$issue}->{$problem}->{$coordinates->{'hse_type'}}->{$coordinates->{'region'}}->{$coordinates->{'file_name'}} = $value;
	
	return ($issues);
};


# ====================================================================
# print_issues
# This subroutine prints out the issues encountered by the script during
# execution. The format is set below which is easy to look at in a text
# editor. In the future additional output files may be set to output in 
# different formats (e.g. csv, xml)
# ====================================================================

sub print_issues {

	my $file = shift;
	my $issues = shift;
	
	print "Printing the ISSUES to $file";
	
	open (my $FILE, '>', $file) or die ("can't open datafile: $file");
	print $FILE "THIS FILE HOLDS THE HSE_GEN ISSUES - the total number of instances is at the bottom of this file"; 

	# The following $instances will count the number of times an error is encountered for reporting purposes.
	my $instances->{'total'} = 0;

	foreach my $issue (sort keys (%{$issues})) {	# cycle through the issues
		$instances->{'issue'} = 0; # this sums up the number of instances of the issue (all problems) for each type and region
		# The ISSUE refers to a field: e.g. HDD or PostalCode
		print $FILE "\n\nISSUE - $issue\n";
		
		foreach my $problem (sort keys (%{$issues->{$issue}})) {	# cycle thorugh problems
			$instances->{'problem'} = 0;	# this sums up the number of instances of the problem for each type and region
			# The PROBLEM is where the problem lies for the ISSUE: e.g. min or max or malformed PostalCode
			print $FILE "\n\tPROBLEM - $problem\n";
			
			# go through the house types and region
			foreach my $hse_type (sort keys (%{$issues->{$issue}->{$problem}})) {
				foreach my $region (sort keys (%{$issues->{$issue}->{$problem}->{$hse_type}})) {
					
					# count the instances for this type/region
					my $type_region_instances = keys (%{$issues->{$issue}->{$problem}->{$hse_type}->{$region}});
					# keep track of the total
					foreach my $type ('total', 'issue', 'problem') {
						$instances->{$type} = $instances->{$type} + $type_region_instances;
					};

					print $FILE "\t\tHouse Type: $hse_type; Region $region; instances $type_region_instances\n";
					
					print $FILE "\t\t";
					my $counter = 1;	# set the counter, we will use this so we can put multiple houses on a line withour running over
					# print $FILE each instance with information to a new line so it may be examined
					foreach my $instance (sort keys (%{$issues->{$issue}->{$problem}->{$hse_type}->{$region}})) {	# cycle through each house with this problem
					
						$instances->{'unique'}->{$instance} = 1;

						# if enough have been printed, then simply go to next line and reset counter
						if ($counter >= 4) {
							print $FILE "\n\t\t\t$issues->{$issue}->{$problem}->{$hse_type}->{$region}->{$instance} $instance";
							$counter = 1;
						}
						# there is still room to print so add a tab and then the value/house
						else {
							print $FILE "    $issues->{$issue}->{$problem}->{$hse_type}->{$region}->{$instance} $instance";
						};
						$counter++;	# increment counter

					};
					print $FILE "\n";
					
				};
			};
			# final count for that problem
			print $FILE "\tInstances of Problem $problem: $instances->{'problem'}\n";
		};
		print $FILE "\nInstances of Issue $issue: $instances->{'issue'}\n";
	};
	print $FILE "\nTotal instances ALL: $instances->{'total'}\n";
	
	my $unique_keys = keys (%{$instances->{'unique'}});
	print $FILE "Total instances UNIQUE HOUSES: $unique_keys\n";
	
	print " - Complete\n";
	return (1);
};


# ====================================================================
# distribution_array
# This subroutine develops a shuffled array of values based on a distribution
# defined at $hash = {value1 => distribution_ratio2, value1 => distribution_ratio2...}
# where the number of array elements desired is provided.
# The array is returned from the subroutine.
# For example: 
# Passed: $hash = {'RED' => 0.25, 'BLUE' => 0.75}; $count = 4
# Return: ['BLUE', 'BLUE', 'RED', 'BLUE']
# ====================================================================

sub distribution_array {

	my $distribution = shift(); # hash reference containing {header1 => dist_data1, header2 => dist_data2...}
	my $count = shift(); # the number of elements desired (typically number of houses)

	my @data; # the array to store the values that will be returned
	
	# go through each element of the header, remember this is the value to be provided to the house file
# 	foreach my $element (0..$#{$NN_xml->{'combined'}->{$key}->{'header'}}) {
	foreach my $key (keys (%{$distribution})) {
		
		# determine the size that the array should be with the particular header value (multiply the distribution by the house count)
		# NOTE I am using sprintf to cast the resultant float as an integer. Float is still used as this will perform rounding (0.5 = 1 and 0.49 = 0). If I had cast as an integer it simply truncates the decimal places (i.e. always rounding down)
		my $index_size = sprintf ("%.f", $distribution->{$key} * $count);
		
		# only fill out the array if the size is greater than zero (this eliminates pushing the value 1 time when no instances are present)
		if ($index_size > 0) {
			# use the index size to fill out the array with the appropriate header value. Note that we start with 1 because 0 to value is actually value + 1 instances
			# go through the array spacing and set the each spaced array element equal to the header value. This will generate a large array with ordered values corresponding to the distribution and the header. NOTE each element value will be used to represent the data for one house of the variable
				
			
			foreach my $index (1..$index_size) {
				# push the header value onto the data array. NOTE: we will check for rounding errors (length) and shuffle the array later
				push (@data, $key);
			};
			
			
		};
	};

	
	# SHUFFLE the array to get randomness b/c we do not know this information for a particular house.
	@data = shuffle (@data);
	
	# CHECK for rounding errors that will cause the array to be 1 or more elements shorter or longer than the number of houses.
	# e.g. three equal distributions results in 10 houses * [0.33 0.33 0.33] results in [3 3 3] which is only 9 elements!
	# if this is true: the push or pop on the array. NOTE: I am using the first array element and this is legitimate because we previously shuffled, so it is random.
	while (@data < $count) {	# to few elements
		push (@data, $data[0]);
		# in case we do this more than once, I am shuffling it again so that the first element is again random.
		@data = shuffle (@data);
	};
	while (@data > $count) {	# to many elements
		shift (@data);
	};
	
	return (@data);
};



sub die_msg {	# subroutine to die and give a message
	my $msg = shift;	# the error message to print
	my $value = shift; # the error value
	my $coordinates = shift; # the CSDDRD to report the house type, region, house name

	my $message = "MODEL ERROR - $msg; Value = $value;";
	foreach my $key ('hse_type', 'region', 'file_name') {
		$message = $message . " $key $coordinates->{$key}"
	};
	die "$message\n";
	
};


sub replace {	# subroutine to perform a simple element replace (house file to read/write, keyword to identify row, rows below keyword to replace, replacement text)
	my $hse_file = shift (@_);	# the house file to read/write
	my $find = shift (@_);	# the word to identify
	my $location = shift (@_);	# where to identify the word: 1=start of line, 2=anywhere within the line, 3=end of line
	my $beyond = shift (@_);	# rows below the identified word to operate on
	my $format = shift (@_);	# format of the replacement text for the operated element
	CHECK_LINES: foreach my $line (0..$#{$hse_file}) {	# pass through the array holding each line of the house file
		if ((($location == 1) && ($hse_file->[$line] =~ /^$find/)) || (($location == 2) && ($hse_file->[$line] =~ /$find/)) || (($location == 3) && ($hse_file->[$line] =~ /$find$/))) {	# search for the identification word at the appropriate position in the line
			$hse_file->[$line+$beyond] = sprintf ($format, @_);	# replace the element that is $beyond that where the identification word was found
			last CHECK_LINES;	# If matched, then jump out to save time and additional matching
		};
	};
	
	return;
};

sub insert {	# subroutine to perform a simple element insert after (specified) the identified element (house file to read/write, keyword to identify row, number of elements after to do insert, replacement text)
	my $hse_file = shift (@_);	# the house file to read/write
	my $find = shift (@_);	# the word to identify
	my $location = shift (@_);	# 1=start of line, 2=anywhere within the line, 3=end of line
	my $beyond = shift (@_);	# rows below the identified word to remove from and insert too
	my $remove = shift (@_);	# rows to remove
	my $format = shift (@_);	# format of the replacement text for the operated element
	CHECK_LINES: foreach my $line (0..$#{$hse_file}) {	# pass through the array holding each line of the house file
		if ((($location == 1) && ($hse_file->[$line] =~ /^$find/)) || (($location == 2) && ($hse_file->[$line] =~ /$find/)) || (($location == 3) && ($hse_file->[$line] =~ /$find$/))) {	# search for the identification word at the appropriate position in the line

# 				print "$find\n";
			splice (@{$hse_file}, $line + $beyond, $remove, sprintf ($format, @_));	# replace the element that is $beyond that where the identification word was found
			last CHECK_LINES;	# If matched, then jump out to save time and additional matching
		};
	};
	return;
};

#--------------------------------------------------------------------
# A simple subroutine to captitalize the first letter of a string
#--------------------------------------------------------------------
sub capitalize_first_letter {
	my $string = shift; # The string

	$string =~ /^(.)/; # Determine the first letter

	my $character = uc($1); # Captilize this letter

	$string =~ s/^(.)/$character/; # Replace the letter with the capitalized one

	return ($string); # Return the string
};

#--------------------------------------------------------------------
# A simple subroutine to captitalize the first letter of a string
#--------------------------------------------------------------------
sub capitalize_first_letter_each_word {
	my $string = shift; # The string
	my @words = split(/ */, $string); # The words

	foreach my $word (@words) {
		$word =~ /^(.)/; # Determine the first letter

		my $character = uc($1); # Captilize this letter

		$word =~ s/^(.)/$character/; # Replace the letter with the capitalized one
	}
	
	$string = join(' ', @words);

	return ($string); # Return the string
};

# Final return value of one to indicate that the perl module is successful
1;
