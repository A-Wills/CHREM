# ====================================================================
# XML_reporting.pm
# Author: Lukas Swan
# Date: Mar 2010
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# 
# ====================================================================

# Declare the package name of this perl module
package XML_reporting;

# Declare packages used by this perl module
use strict;
# use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;
use XML::Simple;
use General;
use Storable  qw(dclone);
use File::Copy;	# (to copy the xml file)

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(organize_xml_log zone_energy_balance zone_temperatures secondary_consumption GHG_conversion site_balance);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# organize_xml_log
# This reorganizes the XML log file by month and period for a more
# suitable format for CHREM
# ====================================================================

sub organize_xml_log {
	my $house_name = shift; # House name
	my $sim_period = shift; # Simulation period hash reference
	my $zone_name_num = shift; # Zone names and numbers hash reference
	my $province = shift; # The province name
	my $coordinates = shift; # House coordinate information for error reporting


	
	my $file = $house_name . '.xml'; # Create a complete filename with extension

	# If the orig file exists then we have already made a copy on a previous run. If not, make a copy
	unless (-e "$file.orig") {copy($file, $file . '.orig');};
	
	# Unlink the xml file as this will be recreated at the end of this routine
	unlink "$file";

	# If the xml.orig file exists, then resort it
	if (-e "$file.orig") { 
		my $XML = XMLin($file . '.orig'); # Readin the XML data from the orig file
		my $parameters = $XML->{'parameter'}; # Create a reference to the XML parameters

		my @month_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec); # Short month names
		my ($month_num, $num_month, $month_days); # Declare some month information hash refs
		@{$month_num}{@month_names} = (1..12); # Key = month name, value = month number [1..12]
		$num_month = {reverse(%{$month_num})}; # Key = month number [1..12], value = month name
		@{$month_days}{@month_names} = qw(31 28 31 30 31 30 31 31 30 31 30 31); # Key = month name, value = days in month
		
		my $month_num_begin = $month_num->{$sim_period->{'begin'}->{'month'}};
		my $month_num_end = $month_num->{$sim_period->{'end'}->{'month'}};


		# Cycle over the parameters and reorder the summaries for ease of use
		foreach my $key (keys %{$parameters}) {
            if ($parameters =~ /Site_Bal/) { # Remove site balance terms
                delete $XML->{'parameter'}->{$parameters};
            } else {
                
                my ($unit) = ($parameters->{$key}->{'units'} =~ /\((.+)\)/); # Strip the units value of brackets and store it as 'normal' units
                $parameters->{$key}->{'units'} = {'normal' => $unit}; # Set units equal to this as the nominal unit type for non-integrated values
                
                # Cycle over the binned_data (by month and annual) and relocate the data up the tree
                foreach my $element (@{$parameters->{$key}->{'binned_data'}}) {
                    my $period; # Define a period variable
                    if ($element->{'type'} eq 'annual') { # If the type is annual
                        $period = 'P00_Period'; # Store the period name
                        delete $element->{'type'}; # Delete the redundant information
                        # Cycle over the begin and end and set the month and day equal to the simulation period
        # 				foreach my $begin_end (qw(begin end)) {
        # 					@{$element->{$begin_end}}{qw(month day)} = @{$sim_period->{$begin_end}}{qw(month day)}; # Hash slice
        # 				};
                    }
                    elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
                        my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
                        $period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
                        delete @{$element}{'type', 'index'}; # Delete the redundant information
                        # Cycle over the begin and end and set the month and determine the days
        # 				foreach my $begin_end (qw(begin end)) {
        # 					$element->{$begin_end}->{'month'} = $period; # Month will alway be equal to the period
        # 					if ($period eq $sim_period->{$begin_end}->{'month'}) {$element->{$begin_end}->{'day'} = $sim_period->{$begin_end}->{'day'};} # If the month is equal to the begin or end month then use the days specified for either the beginnig or end of simulation
        # 					else {$element->{$begin_end}->{'day'} = {'begin' => '01', 'end' => $month_days->{$period}}->{$begin_end};}; # Otherwise if it is a beginning then set to 1 and if it is an end set to the number of days in the month
        # 				};
                    }
                    else { # Report if the type is unknown
                        &die_msg("Bad XML reporting binned data type in $file: should be 'annual' or 'monthly'", $element->{'type'}, $coordinates);
                    };
                    # Save the information up the tree by cloning the remainder of the element to that period
                    $parameters->{$key}->{$period} = dclone($element);
                };
                # Delete the redundant information
                delete $parameters->{$key}->{'binned_data'};
                
                # Integrated data
                if (defined($parameters->{$key}->{'integrated_data'})) {
                    # Cycle over the integrated data
                    foreach my $element (@{$parameters->{$key}->{'integrated_data'}->{'bin'}}) {
                        my $period; # Define a period variable
                        if ($element->{'type'} eq 'annual') { # If the type is annual
                            $period = 'P00_Period'; # Store the period
                        }
                        elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
                            my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
                            $period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
                        }
                        else { # Report if the type is unknown
                            &die_msg("Bad XML reporting integrated data bin type in $file: should be 'annual' or 'monthly'", $element->{'type'}, $coordinates);
                        };
                        
                        # Check that the integrated value is not NAN
                        if ($element->{'content'} =~ /nan/i) {
                            return(0);
                        };
                        
                        # Save the information (integrated value) up the tree under a key of 'integrated'
                        $parameters->{$key}->{$period}->{'integrated'} = $element->{'content'};
                    };
    
                    # Also store the integrated units type
                    ($parameters->{$key}->{'units'}->{'integrated'}) = $parameters->{$key}->{'integrated_data'}->{'units'};
                    # Delete the redundant information
                    delete $parameters->{$key}->{'integrated_data'};
                };
            };
        };

		# Store the sim period and zone information
		$XML->{'sim_period'} = dclone($sim_period);
		$XML->{'zone_name_num'} = dclone($zone_name_num);
		$XML->{'province'} = $province;

#
		# The above has been replaced with this call to do the GHG Conversion. It will save time and is required because we regenerate the new XML file every time we run Results.pl
		&GHG_conversion($house_name, $coordinates, $XML);

		
		return(1);
	}
	
	else {return(0);};
};


# ====================================================================
# energy_balance
# This constructs an energy balance from the xml log reporting
# ====================================================================

sub zone_energy_balance {
	my $house_name = shift;
	my $coordinates = shift;
	
	my $file = $house_name . '.xml';
# 	print "In xml reporting at $file\n";
	my $XML = XMLin($file);
	
	# Remove the 'parameter' field
	my $parameters = $XML->{'parameter'};
# 	print Dumper $parameters;
	my $zone_num_name = {reverse(%{$XML->{'zone_name_num'}})};

	# Create an energy results hash reference to store accumulated data
	my $en_results;
	# The data will be sorted into a columnar printout, so store the width of the first column based on its header
	$en_results->{'columns'}->{'variable'} = length('Energy (kWh)');
	
	# Cycle over the entire summary hash and summarize the control volume energy results
	foreach my $key (keys %{$parameters}) {
		# Only summarize for energy balance based on zone information and a power type
		if ($key =~ /^CHREM\/zone_0(\d)\/Power\/(.+)$/) {
			my $zone_name = $zone_num_name->{$1}; # Store the zone name
			my $variable = $2; # Store the variable name
			
			# Check the length of the variable and if it is longer, set the column to that width
			if (length($variable) > $en_results->{'columns'}->{'variable'}) {
				$en_results->{'columns'}->{'variable'} = length($variable);
			};
			
			# Check to see if a column has been generated for this zone. If not then set it equal to the zone name length + 2 for spacing
			unless (defined($en_results->{'columns'}->{$zone_name})) {
				$en_results->{'columns'}->{$zone_name} = length($zone_name) + 2;
			};
			
			# Declare a type for sorting the results. Usually, a 1st law energy balance is DeltaE = Q - W.
			# Because the DeltaE is likely to be little, we will show in vertical columns Q, then DeltaE
			my $type;
# 			if ($variable =~ /^(SH|LH)/) {$type = 'storage';}
			if ($variable =~ /Opaq/) {$type = 'opaque';}
			elsif ($variable =~ /Tran/) {$type = 'transparent';}
			else {$type = 'air point'};

			# Store the resulting information. Convert from GJ to kWh and format so the sign is always shown
			if ($parameters->{$key}->{'units'}->{'integrated'} eq 'GJ') {
				$en_results->{$type}->{$variable}->{$zone_name} = sprintf("%+.0f", $parameters->{$key}->{'P00_Period'}->{'integrated'} * 277.78);
			}
			else {&die_msg("Bad integrated data units for energy balance: should be 'GJ'", $parameters->{$key}->{'units'}->{'integrated'}, $coordinates);};

			# NOTE: Because interior convection with reference to the node is opposite our control volume, it needs a sign reversal
# 				if ($variable =~ /^CV/) {
# 					$en_results->{$type}->{$variable}->{$zone_name} = sprintf("%+.0f", -$en_results->{$type}->{$variable}->{$zone_name});
# 				};

			# Compare the length of this value to the column size and modify if necessary
			if ((length($en_results->{$type}->{$variable}->{$zone_name}) + 2) > $en_results->{'columns'}->{$zone_name}) {
				$en_results->{'columns'}->{$zone_name} = length($en_results->{$type}->{$variable}->{$zone_name}) + 2;
			};
		};
	};
	
#	print Dumper $en_results;
	
	$file = $house_name . '.energy_balance';
	# Create a results file
	open (my $PERIOD, '>', $file);
	
	print $PERIOD "Simulation period: $XML->{'sim_period'}->{'begin'}->{'month'} $XML->{'sim_period'}->{'begin'}->{'day'} to $XML->{'sim_period'}->{'end'}->{'month'} $XML->{'sim_period'}->{'end'}->{'day'}\n\n";
	# Print the first column name of the header row, using the width specifified and a format involving a vertical bar afterwards
	printf $PERIOD ("%-$en_results->{'columns'}->{'variable'}s |", 'Energy (kWh)');
	
	# Select the printout orders
	my $print->{'zones'} = &order($en_results->{'columns'}, [qw(main bsmt crawl attic roof)], ['']); # Only print desired zones
# 	$print->{'type'} = [qw(opaque transparent), 'air point', qw(storage)]; # Print the following energy types
	$print->{'type'} = &order($en_results, [qw(opaque transparent), 'air point', qw(storage)], ['columns']);
	# The following three lines control the types of fluxes to be output
	$print->{'opaque'} = &order($en_results->{'opaque'}, [qw(CD CV SW LW SH LH)], ['']); # CD CV SW LW
	$print->{'transparent'} = &order($en_results->{'transparent'}, [qw(CD CV SW LW SH LH)], ['']); # CD CV SW LW
	$print->{'air point'} = &order($en_results->{'air point'}, [qw(CV AV GN SH LH)], []); #AV GN
# 	$print->{'storage'} = &order($en_results->{'storage'}, [qw(SH LH)], []); # SH LH

	# Print the zone names for each column using the width information and a double space afterwards
	foreach my $zone (@{$print->{'zones'}}) {
		printf $PERIOD ("%$en_results->{'columns'}->{$zone}s", $zone);
	};

	# Declare a sum so that we can print the summations and energy balance info
	my $sum;

	# Cycle over the desired energy types
	foreach my $type (@{$print->{'type'}}) {

		# This is not expected to be tripped until the fluxes have been determined
		# The following cycles back through the previous types (e.g. opaque, transparent, and air point) to sum them all up. It is expected that individually their sums will be non-zero, but together they will be close to zero and balance the upcoming storage values
		if ($type eq 'storage') {
			# Print header info
			print $PERIOD ("\n\n--" . 'SUMMATION OF PREVIOUS FLUXES' . "--\n");
			printf $PERIOD ("%-$en_results->{'columns'}->{'variable'}s |", '++SUM++');
			# Cycle over the zones
			foreach my $zone (@{$print->{'zones'}}) {
				my $sum2 = 0; # Create a second summation
				foreach my $type2 (keys(%{$sum->{$zone}})) { # Cycle over all the previously calculated types
					$sum2 = sprintf("%+.0f", $sum2 + $sum->{$zone}->{$type2}); # Add them together
				};
				# Finally print out the formatted total within the column
				printf $PERIOD ("%$en_results->{'columns'}->{$zone}s", $sum2);
			};
		};
		
		# Print a header line for indication of this flux type
		print $PERIOD ("\n\n--" . uc($type) . "--\n");
		
		# Cycle over each matching  variable
		foreach my $variable (@{$print->{$type}}) {
			# Print the variable information
			printf $PERIOD ("%-$en_results->{'columns'}->{'variable'}s |", $variable);
			# Cycle over the zones
			foreach my $zone (@{$print->{'zones'}}) {
				# Initialize the summation of this energy flux type
				unless (defined($sum->{$zone}->{$type})) {
					$sum->{$zone}->{$type} = 0;
				};
				# Print the  formatted value
				printf $PERIOD ("%$en_results->{'columns'}->{$zone}s", $en_results->{$type}->{$variable}->{$zone});
				# Add it to the summation
				$sum->{$zone}->{$type} = sprintf("%  +.0f", $sum->{$zone}->{$type} + $en_results->{$type}->{$variable}->{$zone});
			};
			print $PERIOD ("\n"); # Because we are columnar information we have multiple zones and when complete print an end of line
		};

		# Print the sum for this type of energy flux (e.g. opaque)
		printf $PERIOD ("%-$en_results->{'columns'}->{'variable'}s |", '++SUM++');
		# Cycle over the zones and print the sum
		foreach my $zone (@{$print->{'zones'}}) {
			printf $PERIOD ("%$en_results->{'columns'}->{$zone}s", $sum->{$zone}->{$type});
		};

		# This is not expected to be tripped until the fluxes have been determined
		# The following cycles back through the previous types (e.g. opaque, transparent, and air point) to sum them all up. It is expected that individually their sums will be non-zero, but together they will be close to zero and balance the upcoming storage values
		if ($type eq 'air point') {
			# Print header info
			print $PERIOD ("\n\n--" . 'SUMMATION OF PREVIOUS FLUXES' . "--\n");
			printf $PERIOD ("%-$en_results->{'columns'}->{'variable'}s |", '++SUM++');
			# Cycle over the zones
			foreach my $zone (@{$print->{'zones'}}) {
				my $sum2 = 0; # Create a second summation
				foreach my $type2 (keys(%{$sum->{$zone}})) { # Cycle over all the previously calculated types
					$sum2 = sprintf("%+.0f", $sum2 + $sum->{$zone}->{$type2}); # Add them together
				};
				# Finally print out the formatted total within the column
				printf $PERIOD ("%$en_results->{'columns'}->{$zone}s", $sum2);
			};
		};

	};
	# Close up the file
	close $PERIOD;
	
# 	print Dumper $parameters;
	return(1);
};


# ====================================================================
# zone_temperatures
# This writes out zone and ambient temperatures from the xml log reporting
# ====================================================================

sub zone_temperatures {
	my $house_name = shift;
	my $coordinates = shift;
	
	my $file = $house_name . '.xml';
# 	print "In xml reporting at $file\n";
	my $XML = XMLin($file);
	
	# Remove the 'parameter' field
	my $parameters = $XML->{'parameter'};
# 	print Dumper $parameters;
	my $zone_num_name = {reverse(%{$XML->{'zone_name_num'}})};

	# Create an energy results hash reference to store accumulated data
	my $temp_results;
	# The data will be sorted into a columnar printout, so store the width of the first column based on its header
	$temp_results->{'columns'}->{'variable'} = length('Temperature (C)');
	
	# Cycle over the entire summary hash and summarize the control volume energy results
	foreach my $key (keys %{$parameters}) {

		if ($key =~ /^CHREM\/(zone_0\d|CLM)\/Temp\/Airpoint$/) {
			my $zone_name  = $1;
			if ($zone_name =~ /zone_0(\d)/) {$zone_name = $zone_num_name->{$1};} # Store the zone name
			else {$zone_name = 'ambient';};

			# Check to see if a column has been generated for this zone. If not then set it equal to the zone name length + 2 for spacing
			unless (defined($temp_results->{'columns'}->{$zone_name})) {
				$temp_results->{'columns'}->{$zone_name} = length($zone_name) + 2;
			};

			my $type = 'temperature';

			unless ($parameters->{$key}->{'units'}->{'normal'} eq 'C') {&die_msg("Bad normal data units for temperature: should be 'C'", $parameters->{$key}->{'units'}->{'normal'}, $coordinates);};

			# Store the resulting information
			foreach my $variable (qw(Minimum Maximum Average)) {
				my $var_xml = {qw(Minimum min Maximum max Average total_average)}->{$variable};
				
				# Check the length of the variable and if it is longer, set the column to that width
				if (length($variable) > $temp_results->{'columns'}->{'variable'}) {
					$temp_results->{'columns'}->{'variable'} = length($variable);
				};

				$temp_results->{$type}->{$variable}->{$zone_name} = sprintf("%+.1f", $parameters->{$key}->{'P00_Period'}->{$var_xml});

				# Compare the length of this value to the column size and modify if necessary
				if ((length($temp_results->{$type}->{$variable}->{$zone_name}) + 2) > $temp_results->{'columns'}->{$zone_name}) {
					$temp_results->{'columns'}->{$zone_name} = length($temp_results->{$type}->{$variable}->{$zone_name}) + 2;
				};

			};
		};
	};
	
#	print Dumper $temp_results;
	
	$file = $house_name . '.temperature';
	# Create a results file
	open (my $PERIOD, '>', $file);
	
	print $PERIOD "Simulation period: $XML->{'sim_period'}->{'begin'}->{'month'} $XML->{'sim_period'}->{'begin'}->{'day'} to $XML->{'sim_period'}->{'end'}->{'month'} $XML->{'sim_period'}->{'end'}->{'day'}\n\n";
	# Print the first column name of the header row, using the width specifified and a format involving a vertical bar afterwards
	printf $PERIOD ("%-$temp_results->{'columns'}->{'variable'}s |", 'Temperature (C)');
	
	# Select the printout orders
	my $print->{'zones'} = &order($temp_results->{'columns'}, [qw(ambient main bsmt crawl attic roof)], ['']); # Only print desired zones
	$print->{'type'} = &order($temp_results, ['temperature'], ['columns']); # Print the following energy types
	# The following three lines control the types of fluxes to be output
	$print->{'temperature'} = &order($temp_results->{'temperature'}, [qw(Minimum Maximum Average)], []); # Minimum Maximum Average
	
	# Print the zone names for each column using the width information and a double space afterwards
	foreach my $zone (@{$print->{'zones'}}) {
		printf $PERIOD ("%$temp_results->{'columns'}->{$zone}s", $zone);
	};

	# Cycle over the desired types
	foreach my $type (@{$print->{'type'}}) {
		
		# Print a header line for indication of this flux type
		print $PERIOD ("\n\n--" . uc($type) . "--\n");
		
		# Cycle over each matching  variable
		foreach my $variable (@{$print->{$type}}) {
			# Print the variable information
			printf $PERIOD ("%-$temp_results->{'columns'}->{'variable'}s |", $variable);
			# Cycle over the zones
			foreach my $zone (@{$print->{'zones'}}) {
				# Print the  formatted value
				printf $PERIOD ("%$temp_results->{'columns'}->{$zone}s", $temp_results->{$type}->{$variable}->{$zone});
			};
			print $PERIOD ("\n"); # Because we are columnar information we have multiple zones and when complete print an end of line
		};
	};
	# Close up the file
	close $PERIOD;
	
# 	print Dumper $parameters;
	return(1);
};


# ====================================================================
# secondary_consumption
# This writes out utility energy, quantity, and GHG from the xml log reporting
# ====================================================================

sub secondary_consumption {
	my $house_name = shift;
	my $coordinates = shift;
	
	my $file = $house_name . '.xml';
# 	print "In xml reporting at $file\n";
	my $XML = XMLin($file);
	
	# Remove the 'parameter' field
	my $parameters = $XML->{'parameter'};
# 	print Dumper $parameters;
	my $zone_num_name = {reverse(%{$XML->{'zone_name_num'}})};

	# Create an energy results hash reference to store accumulated data
	my $utilities;
	# The data will be sorted into a columnar printout, so store the width of the first column based on its header
	$utilities->{'columns'}->{'variable'} = length('Secondary consumption');
	
	my $sig_digs = {qw(GJ %+.1f kWh %+.0f kg %+.0f tonne %+.2f m3 %+.0f l %+.0f)};
	
	# Cycle over the entire summary hash and summarize the control volume energy results
	foreach my $key (keys %{$parameters}) {

		if ($key =~ /^CHREM\/SCD\/(.+)$/) {
			my $var_long  = $1;
			my ($type, $variable, $field);
			if ($var_long =~ /^(site)\/(\w+)$/) {
				$type = $1;
				$variable = $1;
				$field = $2;
			}
			elsif ($var_long =~ /^(src|use)\/(\w+)\/(\w+)$/) {
				$type = $1;
				$variable = $2;
				$field = $3;
			}
			elsif ($var_long =~ /^use\/(\w+)\/src\/(\w+)\/(\w+)$/) {
				$type = $1;
				$variable = $2;
				$field = $3;
			}
			elsif ($var_long =~ /^gen\/(\w+)\/src\/(\w+)\/(\w+)$/) {
				$type = $1;
				$variable = $2;
				$field = $3;
			}

			# Check the length of the type and variable and if it is longer, set the column to that width
			foreach my $check ($type, $variable) {
				if (length($check) > $utilities->{'columns'}->{'variable'}) {
					$utilities->{'columns'}->{'variable'} = length($check);
				};
			};

			# Check to see if a column has been generated for this field. If not then set it equal to the field name length + 2 for spacing
			unless (defined($utilities->{'columns'}->{$field})) {
				$utilities->{'columns'}->{$field} = length($field) + 2;
			};

			$utilities->{$type}->{$variable}->{$field} = sprintf($sig_digs->{$parameters->{$key}->{'units'}->{'integrated'}}, $parameters->{$key}->{'P00_Period'}->{'integrated'}) . ' ' . $parameters->{$key}->{'units'}->{'integrated'};

			# Compare the length of this value to the column size and modify if necessary
			if ((length($utilities->{$type}->{$variable}->{$field}) + 2) > $utilities->{'columns'}->{$field}) {
				$utilities->{'columns'}->{$field} = length($utilities->{$type}->{$variable}->{$field}) + 2;
			};

		};
	};
	
#	print Dumper $utilities;
	
	$file = $house_name . '.secondary';
	# Create a results file
	open (my $PERIOD, '>', $file);
	
	print $PERIOD "Simulation period: $XML->{'sim_period'}->{'begin'}->{'month'} $XML->{'sim_period'}->{'begin'}->{'day'} to $XML->{'sim_period'}->{'end'}->{'month'} $XML->{'sim_period'}->{'end'}->{'day'}\n\n";
	# Print the first column name of the header row, using the width specifified and a format involving a vertical bar afterwards
	printf $PERIOD ("%-$utilities->{'columns'}->{'variable'}s |", 'Secondary consumption');
	
	# Select the printout orders
	my $print->{'fields'} = &order($utilities->{'columns'}, [qw(energy quantity GHG)], ['']); # Only print desired zones
	$print->{'type'} = &order($utilities, [qw(site src use)], ['columns']); # Print the following energy types
	# The following three lines control the types of fluxes to be output
	foreach my $type (@{$print->{'type'}}) {
		$print->{$type} = &order($utilities->{$type}, [], []);
	};
	
	# Print the zone names for each column using the width information and a double space afterwards
	foreach my $field (@{$print->{'fields'}}) {
		printf $PERIOD ("%$utilities->{'columns'}->{$field}s", $field);
	};

	# Cycle over the desired types
	foreach my $type (@{$print->{'type'}}) {
		
		# Print a header line for indication of this flux type
		print $PERIOD ("\n\n--" . uc($type) . "--\n");
		
		# Cycle over each matching variable
		foreach my $variable (@{$print->{$type}}) {
			# Print the variable information
			printf $PERIOD ("%-$utilities->{'columns'}->{'variable'}s |", $variable);
			# Cycle over the zones
			foreach my $field (@{$print->{'fields'}}) {
				# Print the  formatted value
				printf $PERIOD ("%$utilities->{'columns'}->{$field}s", $utilities->{$type}->{$variable}->{$field});
			};
			print $PERIOD ("\n"); # Because we are columnar information we have multiple zones and when complete print an end of line
		};
	};
	# Close up the file
	close $PERIOD;
	
# 	print Dumper $parameters;
	return(1);
};


# ====================================================================
# GHG_conversion
# This writes converts utility energy to GHG from the xml log reporting
# ====================================================================

sub GHG_conversion {
	my $house_name = shift;
	my $coordinates = shift;
	
	my $file = $house_name . '.xml';
	
# 	print "In xml reporting at $file\n";
# 	my $XML = XMLin($file);
	my $XML = shift;
# 	copy($file,$file . '.bak2');
# 	Check if the input file format for <hierarchy> is in tree format then we have to reformat the XML file
	my $filename;
	
	if ($house_name =~ (/(..\/.+\/.+\/\w+\/)(\w+)$/)){ 
		my $folder = $1;
		$filename = $folder.'/input.xml';
	}
	else {$filename = 'input.xml';}
	my $INP = XMLin($filename); # Readin the XML data from the orig file
	if ($INP->{'hierarchy'} =~ /tree/) {
		# To access these sorted results at a later point, output them in XML format to a file
        # OCT 13 2016, ADW:  organize_xml_log_tree is only called in this module. No longer exported. Instead of receiving file path, receives the HASH
		#open (my $XML_file, '>', $file) or die ("\n\nERROR: can't open $file to rewrite xml log in sorted form\n"); # Open a writeout file
		#print $XML_file XMLout($XML);	# printout the XML data
		#close $XML_file;
		#&organize_xml_log_tree ($file);
        #$XML = XMLin ($file);
        
        # Organize the HASH
        $XML = organize_xml_log_tree ($XML);

        # print the new XML file
        open (my $XML_file, '>', $file) or die ("\n\nERROR: can't open $file to rewrite xml log in sorted form\n"); # Open a writeout file
        print $XML_file XMLout($XML);	# printout the XML data
        close $XML_file;
        
        # Reload the XML (XML simple will clean up the file a bit)
        undef $XML;
        $XML = XMLin ($file);
	}

    $XML = &site_balance($house_name, $XML, $coordinates); #Interpret the site balance
# 		
	my $ghg_file;
	if (-e '../../../keys/GHG_key.xml') {$ghg_file = '../../../keys/GHG_key.xml'}
	elsif (-e '../keys/GHG_key.xml') {$ghg_file = '../keys/GHG_key.xml'}
	my $GHG = XMLin($ghg_file);

	# Remove the 'parameter' field
	my $parameters = $XML->{'parameter'};
	
	# Remove the 'en_src' field
	my $en_srcs = $GHG->{'en_src'};
	
	my $site_ghg;
	my $use_ghg;
	
# 	# Cycle over the entire summary hash and summarize the control volume energy results
	foreach my $key (keys %{$parameters}) {
		if ($key =~ /^CHREM\/SCD\/src\/(\w+)\/quantity$/) {
			my $src = $1;
			unless ($src =~ /electricity/) {
				foreach my $period (@{&order($parameters->{$key}, [], [qw(units description)])}) {
					$parameters->{"CHREM/SCD/src/$src/GHG"}->{$period}->{'integrated'} = $parameters->{$key}->{$period}->{'integrated'} * $en_srcs->{$src}->{'GHGIF'} / 1000;
					unless (defined($site_ghg->{$period})) {$site_ghg->{$period} = 0;};
					$site_ghg->{$period} = $site_ghg->{$period} + $parameters->{"CHREM/SCD/src/$src/GHG"}->{$period}->{'integrated'};
				};
			}
			else { # electricity
				my $per_sum = 0;
				foreach my $period (@{&order($parameters->{$key}, [], [qw(units P00 description)])}) {
					my $mult;
					if (defined($en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'period'}->{$period}->{'GHGIFavg'})) {
						$mult = $en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'period'}->{$period}->{'GHGIFavg'};
					}
					else {
						$mult = $en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'period'}->{'P00_Period'}->{'GHGIFavg'};
					};
# 					print "En src mult $mult\n";
# 					print Dumper $en_srcs;
					$parameters->{"CHREM/SCD/src/$src/GHG"}->{$period}->{'integrated'} = $parameters->{$key}->{$period}->{'integrated'} / (1 - $en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'trans_dist_loss'}) * $mult / 1000;
					unless (defined($site_ghg->{$period})) {$site_ghg->{$period} = 0;};
					$site_ghg->{$period} = $site_ghg->{$period} + $parameters->{"CHREM/SCD/src/$src/GHG"}->{$period}->{'integrated'};
					$per_sum = $per_sum + $parameters->{"CHREM/SCD/src/$src/GHG"}->{$period}->{'integrated'}
				};
				$parameters->{"CHREM/SCD/src/$src/GHG"}->{'P00_Period'}->{'integrated'} = $per_sum;
				unless (defined($site_ghg->{'P00_Period'})) {$site_ghg->{'P00_Period'} = 0;};
				$site_ghg->{'P00_Period'} = $site_ghg->{'P00_Period'} + $parameters->{"CHREM/SCD/src/$src/GHG"}->{'P00_Period'}->{'integrated'};
			};
			$parameters->{"CHREM/SCD/src/$src/GHG"}->{'units'}->{'integrated'} = 'kg';
		}

		elsif ($key =~ /^CHREM\/SCD\/use\/(\w+)\/src\/(\w+)\/quantity$/) {
			my $use = $1;
			my $src = $2;
			unless ($src =~ /electricity/) {
				foreach my $period (@{&order($parameters->{$key}, [], [qw(units description)])}) {
					$parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{$period}->{'integrated'} = $parameters->{$key}->{$period}->{'integrated'} * $en_srcs->{$src}->{'GHGIF'} / 1000;
					unless (defined($use_ghg->{$use}->{$period})) {$use_ghg->{$use}->{$period} = 0;};
					$use_ghg->{$use}->{$period} = $use_ghg->{$use}->{$period} + $parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{$period}->{'integrated'};
				};
			}
			else { # electricity
				my $per_sum = 0;
				foreach my $period (@{&order($parameters->{$key}, [], [qw(units P00 description)])}) {
					my $mult;
					if (defined($en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'period'}->{$period}->{'GHGIFavg'})) {
						$mult = $en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'period'}->{$period}->{'GHGIFavg'};
					}
					else {
						$mult = $en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'period'}->{'P00_Period'}->{'GHGIFavg'};
					};
# 					print "En src mult $mult\n";
# 					print Dumper $en_srcs;
					$parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{$period}->{'integrated'} = $parameters->{$key}->{$period}->{'integrated'} / (1 - $en_srcs->{$src}->{'province'}->{$XML->{'province'}}->{'trans_dist_loss'}) * $mult / 1000;
					unless (defined($use_ghg->{$use}->{$period})) {$use_ghg->{$use}->{$period} = 0;};
					$use_ghg->{$use}->{$period} = $use_ghg->{$use}->{$period} + $parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{$period}->{'integrated'};
					$per_sum = $per_sum + $parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{$period}->{'integrated'}
				};
				$parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{'P00_Period'}->{'integrated'} = $per_sum;
				unless (defined($use_ghg->{$use}->{'P00_Period'})) {$use_ghg->{$use}->{'P00_Period'} = 0;};
				$use_ghg->{$use}->{'P00_Period'} = $use_ghg->{$use}->{'P00_Period'} + $parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{'P00_Period'}->{'integrated'};
			};
			$parameters->{"CHREM/SCD/use/$use/src/$src/GHG"}->{'units'}->{'integrated'} = 'kg';
		}

	};
	
	foreach my $period (keys(%{$site_ghg})) {
		$parameters->{"CHREM/SCD/site/GHG"}->{$period}->{'integrated'} = $site_ghg->{$period};
	};
	$parameters->{"CHREM/SCD/site/GHG"}->{'units'}->{'integrated'} = 'kg';
	
	foreach my $use (keys(%{$use_ghg})) {
		foreach my $period (keys(%{$use_ghg->{$use}})) {
			$parameters->{"CHREM/SCD/use/$use/GHG"}->{$period}->{'integrated'} = $use_ghg->{$use}->{$period};
		};
		$parameters->{"CHREM/SCD/use/$use/GHG"}->{'units'}->{'integrated'} = 'kg';
	};

	# To access these sorted results at a later point, output them in XML format to a file
	open (my $XML_file, '>', $file) or die ("\n\nERROR: can't open $file to rewrite xml log in sorted form\n"); # Open a writeout file
	print $XML_file XMLout($XML);	# printout the XML data
	close $XML_file;

		

# 	print Dumper $parameters;
	return(1);
};

# ====================================================================
# organize_xml_log_tree
# This reorganizes the XML log file if the format of hierarchy is tree.
# ====================================================================

sub organize_xml_log_tree {
	
	#my $XML_file = shift;

	#my $list = XMLin ($XML_file);
    # OCT 13 2016, ADW: subroutine now accepts the HASH directly
    my $list = shift;
    
	my $parameters = $list->{'CHREM'}; # Create a reference to the XML parameters

	my $new_par_for;
	my ($unit);
	my @month_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec); # Short month names
	my ($month_num, $num_month, $month_days); # Declare some month information hash refs
	@{$month_num}{@month_names} = (1..12); # Key = month name, value = month number [1..12]
	$num_month = {reverse(%{$month_num})}; # Key = month number [1..12], value = month name
	@{$month_days}{@month_names} = qw(31 28 31 30 31 30 31 31 30 31 30 31); # Key = month name, value = days in month

	my $month_num_begin;
	$month_num_begin = $list->{'sim_period'}->{'begin'}->{'month'};
	$month_num_begin = $month_num->{$month_num_begin};

	my $array;

	my $i = 0;
	
	foreach my $key (keys %{$parameters}) {

		my $par = $parameters->{$key};
		my @key_par = keys %{$par};
	
		foreach my $key_2 (@key_par){
		
			if ( ($key =~ /^zone|SCD|BCD/) ) {
				if ($key_2 =~ /src|use|Power/) {
					my @key_power = keys %{$par->{$key_2}};
					foreach my $key_3 (@key_power){
						unless ($key_3 =~ /energy|quantity|name/){
							if ($key_2 !~ /Power/) {
								my @last_key = keys %{$par->{$key_2}->{$key_3}};
								foreach my $last (@last_key) {
									if ($last =~ /^src/) {
										my @last_2_key =  keys %{$par->{$key_2}->{$key_3}->{$last}};
										foreach my $last_2 (@last_2_key) {
											if ($last_2 =~ /energy|quantity/){
												$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$key_3/$last/$par->{$key_2}->{$key_3}->{$last}->{'name'}/$last_2";
												$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{$key_3}->{$last}->{$last_2}->{'description'};
												($unit) = ($par->{$key_2}->{$key_3}->{$last}->{$last_2}->{'units'} =~ /\((.+)\)/); 
												$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
										
												foreach my $element (@{$par->{$key_2}->{$key_3}->{$last}->{$last_2}->{'binned_data'}}) {
													my $period; # Define a period variable
				
													if ($element->{'type'} eq 'annual') { # If the type is annual
														$period = 'P00_Period'; # Store the period name
														delete $element->{'type'};
													}
													elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
														my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
	# 												
															$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
															delete @{$element}{'type', 'index'}; # Delete the redundant information
														}
														$new_par_for->{'parameter'}->{$period} = dclone($element);
													}
													# Integrated data
													if (defined($par->{$key_2}->{$key_3}->{$last}->{$last_2}->{'integrated_data'})) {
				
		# 												# Cycle over the integrated data
														foreach my $element (@{$par->{$key_2}->{$key_3}->{$last}->{$last_2}->{'integrated_data'}->{'bin'}}) {
		# 										
															my $period; # Define a period variable
															if ($element->{'type'} eq 'annual') { # If the type is annual
																$period = 'P00_Period'; # Store the period
															}
															elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
																my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
																$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
															}					
															# Check that the integrated value is not NAN
															if ($element->{'content'} =~ /nan/i) {
																return(0);
															};
		# 					
		# 													# Save the information (integrated value) up the tree under a key of 'integrated'
															$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
														};
		# 
		# 												# Also store the integrated units type
														($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$key_3}->{$last}->{$last_2}->{'integrated_data'}->{'units'};
		# 												# Delete the redundant information
														delete $par->{$key_2}->{'integrated_data'};
													};
# 										
													if (defined $new_par_for->{'parameter'}){
														$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
														delete $new_par_for->{'parameter'};
														
														$i++;
													}
												}
											elsif ($last_2 =~ /electricity|natural_gas/) {
												my @name = keys %{$par->{$key_2}->{$key_3}->{$last}->{$last_2}};
												foreach my $nam (@name) {
	# 										
													$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$key_3/$last/$last_2/$nam";
														
													$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{$key_3}->{$last}->{$last_2}->{$nam}->{'description'};
													($unit) = ($par->{$key_2}->{$key_3}->{$last}->{$last_2}->{$nam}->{'units'} =~ /\((.+)\)/); 
													$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
												
													foreach my $element (@{$par->{$key_2}->{$key_3}->{$last}->{$last_2}->{$nam}->{'binned_data'}}) {
														my $period; # Define a period variable
					
														if ($element->{'type'} eq 'annual') { # If the type is annual
														$period = 'P00_Period'; # Store the period name
														delete $element->{'type'};
						
														}
														elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
															my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
	# 												
															$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
															delete @{$element}{'type', 'index'}; # Delete the redundant information
														}
														$new_par_for->{'parameter'}->{$period} = dclone($element);
													}
													# Integrated data
													if (defined($par->{$key_2}->{$key_3}->{$last}->{$last_2}->{$nam}->{'integrated_data'})) {
					
	# 													# Cycle over the integrated data
														foreach my $element (@{$par->{$key_2}->{$key_3}->{$last}->{$last_2}->{$nam}->{'integrated_data'}->{'bin'}}) {
	# 										
															my $period; # Define a period variable
															if ($element->{'type'} eq 'annual') { # If the type is annual
																$period = 'P00_Period'; # Store the period
															}
															elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
																my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
																$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
															}

															# Check that the integrated value is not NAN
															if ($element->{'content'} =~ /nan/i) {
																return(0);
															};		
	# 					
	# 														# Save the information (integrated value) up the tree under a key of 'integrated'
															$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
														};
	# 
	# 													# Also store the integrated units type
														($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$key_3}->{$last}->{$last_2}->{$nam}->{'integrated_data'}->{'units'};
	# 													# Delete the redundant information
														delete $par->{$key_2}->{'integrated_data'};
													};
													if (defined $new_par_for->{'parameter'}){
														$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
														delete $new_par_for->{'parameter'};
														$i++;
													}
												}
											}
										}
									  
									}
										else {
											if ($key_3 =~/HRV/) {
												$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/ventilation/$last";
											}
											elsif ($key_3 =~/DHW/) {
												$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/water_heating/$last";
											}
											else {
												$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$key_3/$last";
											}
											
											$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{$key_3}->{$last}->{'description'};
											($unit) = ($par->{$key_2}->{$key_3}->{$last}->{'units'} =~ /\((.+)\)/); 
											$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
										
											foreach my $element (@{$par->{$key_2}->{$key_3}->{$last}->{'binned_data'}}) {
												my $period; # Define a period variable
												if ($element->{'type'} eq 'annual') { # If the type is annual
													$period = 'P00_Period'; # Store the period name
													delete $element->{'type'};
												}
												elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
													my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
													$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
													delete @{$element}{'type', 'index'}; # Delete the redundant information
												}
												$new_par_for->{'parameter'}->{$period} = dclone($element);
											}
											# Integrated data
											if (defined($par->{$key_2}->{$key_3}->{$last}->{'integrated_data'})) {
						
		# 										# Cycle over the integrated data
												foreach my $element (@{$par->{$key_2}->{$key_3}->{$last}->{'integrated_data'}->{'bin'}}) {
		# 										
													my $period; # Define a period variable
													if ($element->{'type'} eq 'annual') { # If the type is annual
														$period = 'P00_Period'; # Store the period
													}
													elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
														my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
														$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
													}
											
													# Check that the integrated value is not NAN
													if ($element->{'content'} =~ /nan/i) {
														return(0);
													};
		# 					
		# 											# Save the information (integrated value) up the tree under a key of 'integrated'
													$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
												};
		# 
		# 										# Also store the integrated units type
												($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$key_3}->{$last}->{'integrated_data'}->{'units'};
		# 										# Delete the redundant information
												delete $par->{$key_2}->{'integrated_data'};
											};
		# 								 
											if (defined $new_par_for->{'parameter'}){
												$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
												delete $new_par_for->{'parameter'};
												$i++;
											}
										}
									
									}	
								}
							else {
								$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$key_3";
								$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{$key_3}->{'description'};
								($unit) = ($par->{$key_2}->{$key_3}->{'units'} =~ /\((.+)\)/);
								$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
							
								foreach my $element (@{$par->{$key_2}->{$key_3}->{'binned_data'}}) {
									my $period; # Define a period variable
									if ($element->{'type'} eq 'annual') { # If the type is annual
										$period = 'P00_Period'; # Store the period name
										delete $element->{'type'};
									}
									elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
										my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
										$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
										delete @{$element}{'type', 'index'}; # Delete the redundant information
									}
									$new_par_for->{'parameter'}->{$period} = dclone($element);
								}
								# Integrated data
								if (defined($par->{$key_2}->{$key_3}->{'integrated_data'})) {
					
	# 								# Cycle over the integrated data
									foreach my $element (@{$par->{$key_2}->{$key_3}->{'integrated_data'}->{'bin'}}) {
										my $period; # Define a period variable
										if ($element->{'type'} eq 'annual') { # If the type is annual
											$period = 'P00_Period'; # Store the period
										}
										elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
											my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
											$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
										}
										# Check that the integrated value is not NAN
										if ($element->{'content'} =~ /nan/i) {
											return(0);
										};
	# 					
	# 									# Save the information (integrated value) up the tree under a key of 'integrated'
										$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
									};
	# 
	# 								# Also store the integrated units type
									($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$key_3}->{'integrated_data'}->{'units'};
	# 								# Delete the redundant information
									delete $par->{$key_2}->{'integrated_data'};
								};
	# 						
								if (defined $new_par_for->{'parameter'}){
									$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
									delete $new_par_for->{'parameter'};
									$i++;
								}
	# 						
							}
						}
						else {
							if  ($key_3 =~ /energy|quantity/) {
								$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$par->{$key_2}->{'name'}/$key_3";
								$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{$key_3}->{'description'};
								($unit) = ($par->{$key_2}->{$key_3}->{'units'} =~ /\((.+)\)/);
								$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
								foreach my $element (@{$par->{$key_2}->{$key_3}->{'binned_data'}}) {
									my $period; # Define a period variable
									if ($element->{'type'} eq 'annual') { # If the type is annual
										$period = 'P00_Period'; # Store the period name
										delete $element->{'type'};
									}
									elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
										my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
										$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
										delete @{$element}{'type', 'index'}; # Delete the redundant information
									}
									$new_par_for->{'parameter'}->{$period} = dclone($element);
								}
								# Integrated data
								if (defined($par->{$key_2}->{$key_3}->{'integrated_data'})) {
						
		# 							# Cycle over the integrated data
									foreach my $element (@{$par->{$key_2}->{$key_3}->{'integrated_data'}->{'bin'}}) {
										my $period; # Define a period variable
										if ($element->{'type'} eq 'annual') { # If the type is annual
											$period = 'P00_Period'; # Store the period
										}
										elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
											my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
											$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
										}
										# Check that the integrated value is not NAN
										if ($element->{'content'} =~ /nan/i) {
											return(0);
										};
		# 					
		# 								# Save the information (integrated value) up the tree under a key of 'integrated'
										$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
									};
		# 
		# 							# Also store the integrated units type
									($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$key_3}->{'integrated_data'}->{'units'};
		# 							# Delete the redundant information
									delete $par->{$key_2}->{'integrated_data'};
								};
								if (defined $new_par_for->{'parameter'}){
									$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
									delete $new_par_for->{'parameter'};
									$i++;
								}
							}
						}
					}
				}
				elsif ($key_2 =~ /^AL|DHW/) {
					my @key_BCD = keys %{$par->{$key_2}};
					foreach my $BCD_element (@key_BCD){
						$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$BCD_element";
						$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{$BCD_element}->{'description'};
						($unit) = ($par->{$key_2}->{$BCD_element}->{'units'} =~ /\((.+)\)/);
						$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
						
						foreach my $element (@{$par->{$key_2}->{$BCD_element}->{'binned_data'}}) {
							my $period; # Define a period variable
							if ($element->{'type'} eq 'annual') { # If the type is annual
								$period = 'P00_Period'; # Store the period name
								delete $element->{'type'};
							}
							elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
								my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
								$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
								delete @{$element}{'type', 'index'}; # Delete the redundant information
							}
							$new_par_for->{'parameter'}->{$period} = dclone($element);
						}
						# Integrated data
						if (defined($par->{$key_2}->{$BCD_element}->{'integrated_data'})) {
				
# 							# Cycle over the integrated data
							foreach my $element (@{$par->{$key_2}->{$BCD_element}->{'integrated_data'}->{'bin'}}) {
								my $period; # Define a period variable
								if ($element->{'type'} eq 'annual') { # If the type is annual
									$period = 'P00_Period'; # Store the period
								}
								elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
									my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
									$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
								}
								# Check that the integrated value is not NAN
								if ($element->{'content'} =~ /nan/i) {
									return(0);
								};
# 					
# 								# Save the information (integrated value) up the tree under a key of 'integrated'
								$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
							};
# 
# 							# Also store the integrated units type
							($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$BCD_element}->{'integrated_data'}->{'units'};
# 							# Delete the redundant information
							delete $par->{$key_2}->{'integrated_data'};
						};
# 						
						if (defined $new_par_for->{'parameter'}){
							$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
							delete $new_par_for->{'parameter'};
							$i++;
						}
# 						
					}
				}
				
				else {

					$new_par_for->{'parameter'}->{'name'}  = "CHREM/$key/$key_2/$parameters->{$key}->{$key_2}->{'name'}";
					$new_par_for->{'parameter'}->{'description'}= $par->{$key_2}->{'description'};
					($unit) = ($par->{$key_2}->{'units'} =~ /\((.+)\)/);
					$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
# 				
					foreach my $element (@{$par->{$key_2}->{'binned_data'}}) {
						my $period; # Define a period variable
				
						if ($element->{'type'} eq 'annual') { # If the type is annual
							$period = 'P00_Period'; # Store the period name
							delete $element->{'type'};
						}
						elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
							my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
							$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
							delete @{$element}{'type', 'index'}; # Delete the redundant information
						}
# 					
						$new_par_for->{'parameter'}->{$period} = dclone($element);
					}
					# Integrated data
					if (defined($par->{$key_2}->{'integrated_data'})) {
				
# 						# Cycle over the integrated data
						foreach my $element (@{$par->{$key_2}->{'integrated_data'}->{'bin'}}) {
# 					
							my $period; # Define a period variable
							if ($element->{'type'} eq 'annual') { # If the type is annual
								$period = 'P00_Period'; # Store the period
							}
							elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
								my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
								$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
							}				
							# Check that the integrated value is not NAN
							if ($element->{'content'} =~ /nan/i) {
								 return(0);
							};
# 					
# 							# Save the information (integrated value) up the tree under a key of 'integrated'
							$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
						};
# 
# 						# Also store the integrated units type
						($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{'integrated_data'}->{'units'};
# 					
# 						# Delete the redundant information
						delete $par->{$key_2}->{'integrated_data'};
					};
					if (defined $new_par_for->{'parameter'}){
						$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
						delete $new_par_for->{'parameter'};
						$i++;
					}
# 				
				}
			}

			elsif ($key =~ /^DHW/) {
				$new_par_for->{'parameter'}->{'name'}  = "CHREM/$key/$key_2";
				$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{'description'};
				($unit) = ($par->{$key_2}->{'units'} =~ /\((.+)\)/); # Strip the units value of brackets and store it as 'normal' units
				$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
				foreach my $element (@{$par->{$key_2}->{'binned_data'}}) {
					my $period; # Define a period variable
				
					if ($element->{'type'} eq 'annual') { # If the type is annual
						$period = 'P00_Period'; # Store the period name
						delete $element->{'type'};	
					}
					elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
						my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
						$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
						delete @{$element}{'type', 'index'}; # Delete the redundant information
					}
					$new_par_for->{'parameter'}->{$period} = dclone($element);
				}
				# Integrated data
				if (defined($par->{$key_2}->{'integrated_data'})) {
				
# 					# Cycle over the integrated data
					foreach my $element (@{$par->{$key_2}->{'integrated_data'}->{'bin'}}) {
						my $period; # Define a period variable
						if ($element->{'type'} eq 'annual') { # If the type is annual
							$period = 'P00_Period'; # Store the period
						}
						elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
							my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
							$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
						}
						# Check that the integrated value is not NAN
						if ($element->{'content'} =~ /nan/i) {
							return(0);
						};
# 					
# 						# Save the information (integrated value) up the tree under a key of 'integrated'
						$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
					};
# 
# 					# Also store the integrated units type
					($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{'integrated_data'}->{'units'};
# 					# Delete the redundant information
					delete $par->{$key_2}->{'integrated_data'};
				};
# 			
				if (defined $new_par_for->{'parameter'}){
					$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
			
					delete $new_par_for->{'parameter'};
					$i++;
				}
# 			
			}
			elsif( ($key =~ /^CLM/) ) {
		
				my @key_clm = keys %{$par->{$key_2}};
				foreach my $key_3 (@key_clm){
					$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$key_3";
					$new_par_for->{'parameter'}->{'description'}= $par->{$key_2}->{$key_3}->{'description'};
					($unit) = ($par->{$key_2}->{$key_3}->{'units'} =~ /\((.+)\)/); # Strip the units value of brackets and store it as 'normal' units
					$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
				
					foreach my $element (@{$par->{$key_2}->{$key_3}->{'binned_data'}}) {
						my $period; # Define a period variable
				
						if ($element->{'type'} eq 'annual') { # If the type is annual
							$period = 'P00_Period'; # Store the period name
							delete $element->{'type'};
						}
						elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
							my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
							$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
							delete @{$element}{'type', 'index'}; # Delete the redundant information
						}
						$new_par_for->{'parameter'}->{$period} = dclone($element);
					}
					# Integrated data
					if (defined($par->{$key_2}->{$key_3}->{'integrated_data'})) {
				
# 						# Cycle over the integrated data
						foreach my $element (@{$par->{$key_2}->{$key_3}->{'integrated_data'}->{'bin'}}) {
							my $period; # Define a period variable
							if ($element->{'type'} eq 'annual') { # If the type is annual
								$period = 'P00_Period'; # Store the period
							}
							elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
								my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
								$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
							}
							# Check that the integrated value is not NAN
							if ($element->{'content'} =~ /nan/i) {
								 return(0);
							};
# 					
# 							# Save the information (integrated value) up the tree under a key of 'integrated'
							$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
						};
# 
# 						# Also store the integrated units type
						($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{$key_3}->{'integrated_data'}->{'units'};
# 						# Delete the redundant information
						delete $par->{$key_2}->{$key_3}->{'integrated_data'};
					};
# 				
					if (defined $new_par_for->{'parameter'}){
						$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
						delete $new_par_for->{'parameter'};
						$i++;
					}
# 				
				}
			}
			else {
				$new_par_for->{'parameter'}->{'name'} = "CHREM/$key/$key_2/$parameters->{$key}->{$key_2}->{'name'}";
				$new_par_for->{'parameter'}->{'description'} = $par->{$key_2}->{'description'};
				($unit) = ($par->{$key_2}->{'units'} =~ /\((.+)\)/); # Strip the units value of brackets and store it as 'normal' units
				$new_par_for->{'parameter'}->{'units'} = {'normal' => $unit};
			
				foreach my $element (@{$par->{$key_2}->{'binned_data'}}) {
					my $period; # Define a period variable
				
					if ($element->{'type'} eq 'annual') { # If the type is annual
						$period = 'P00_Period'; # Store the period name
						delete $element->{'type'};	
					}
					elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
						my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
# 					
						$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
						delete @{$element}{'type', 'index'}; # Delete the redundant information
					}
					$new_par_for->{'parameter'}->{$period} = dclone($element);
				}
				# Integrated data
				if (defined($par->{$key_2}->{'integrated_data'})) {
				
# 					# Cycle over the integrated data
					foreach my $element (@{$par->{$key_2}->{'integrated_data'}->{'bin'}}) {
						my $period; # Define a period variable
						if ($element->{'type'} eq 'annual') { # If the type is annual
							$period = 'P00_Period'; # Store the period
						}
						elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
							my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
							$period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
						}
						# Check that the integrated value is not NAN
						if ($element->{'content'} =~ /nan/i) {
							return(0);
						};
# 					
# 						# Save the information (integrated value) up the tree under a key of 'integrated'
						$new_par_for->{'parameter'}->{$period}->{'integrated'} = $element->{'content'};
					};
# 
# 					# Also store the integrated units type
					($new_par_for->{'parameter'}->{'units'}->{'integrated'}) = $par->{$key_2}->{'integrated_data'}->{'units'};
# 					# Delete the redundant information
					delete $par->{$key_2}->{'integrated_data'};
				};
# 			
				if (defined $new_par_for->{'parameter'}){
					$array->{'parameter'}[$i] = $new_par_for->{'parameter'};
					delete $new_par_for->{'parameter'};
					$i++;
				}

			  }
# 		

		}
	
	}
	$array->{'province'}= $list->{'province'};
	$array->{'version'}=$list->{'version'};
	foreach my $element (keys %{$list->{'sim_period'}}) {

		$array->{'sim_period'}->{$element} = dclone($list->{'sim_period'}->{$element});
	  
	}
	$array->{'zone_name_num'} = dclone($list->{'zone_name_num'});
    
	#open (my $XML_file2, '>', $XML_file) or die ("\n\nERROR: can't open $XML_file to rewrite xml log in sorted form\n"); # Open a writeout file
	#print $XML_file2 XMLout($array);	# printout the XML data
	#close $XML_file2;
	
	#return (1);
    return ($array);
};

# ====================================================================
# site_balance
# This pull the data from the .xml.orig output file regarding site
# generation and load 
# ====================================================================

sub site_balance {
	my $house_name = shift; # House name
    my $XMLMOD = shift;     # The XML data being processed
	my $coordinates = shift; # House coordinate information for error reporting
    
	my $parameters = $XMLMOD->{'parameter'}; # Create a HASH reference

	my $file = $house_name . '.xml'; # Create a complete filename with extension
    
    foreach my $key (keys %{$parameters}) {
        if ($key =~ /NodeBalance/ || $key =~ /PCU/ ) {
            delete $parameters->{$key};
        };
    };
    
	# If the xml.orig file exists
	if (-e "$file.orig") {
        my $XML = XMLin("$file.orig"); # Readin the XML data from the orig file
        my $NodeBalance->{'parameter'} = dclone($XML->{'CHREM'}->{'Site_Bal'}->{'NodeBalance'}->{'V_node_1'}); # Create a reference to the XML house bus node
        
        my @month_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec); # Short month names
        my ($month_num, $num_month, $month_days); # Declare some month information hash refs
        @{$month_num}{@month_names} = (1..12); # Key = month name, value = month number [1..12]
        $num_month = {reverse(%{$month_num})}; # Key = month number [1..12], value = month name
        @{$month_days}{@month_names} = qw(31 28 31 30 31 30 31 31 30 31 30 31); # Key = month name, value = days in month
        
        my $month_num_begin = $month_num->{'Jan'};
        my $month_num_end = $month_num->{'Dec'};
        
        # Pull data from house bus
        foreach my $param (keys %{$NodeBalance->{'parameter'}}) {
            # Use key convention
            my $NewName = "CHREM/Site_Bal/NodeBalance/V_node_1/$param";
            $parameters->{$param}->{'name'} = $NewName;
            $parameters->{$param}->{'description'} = $NodeBalance->{'parameter'}->{$param}->{'description'};
        
            my ($unit) = ($NodeBalance->{'parameter'}->{$param}->{'units'} =~ /\((.+)\)/); # Strip the units value of brackets and store it as 'normal' units
            $parameters->{$param}->{'units'} = {'normal' => $unit}; # Set units equal to this as the nominal unit type for non-integrated values
            
            # Cycle over the binned_data (by month and annual) and relocate the data up the tree
            foreach my $element (@{$NodeBalance->{'parameter'}->{$param}->{'binned_data'}}) {
                my $period; # Define a period variable
                if ($element->{'type'} eq 'annual') { # If the type is annual
                    $period = 'P00_Period'; # Store the period name
                    delete $element->{'type'}; # Delete the redundant information
                }
                elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
                    my $month = $num_month->{$element->{'index'} + $month_num_begin}; # Store the period by month name.
                    $period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
                    delete @{$element}{'type', 'index'}; # Delete the redundant information
                    }
                else { # Report if the type is unknown
         		&die_msg("Bad XML reporting binned data type in $file: should be 'annual' or 'monthly'", $element->{'type'}, $coordinates);
                };
                # Save the information up the tree by cloning the remainder of the element to that period
                $parameters->{$param}->{$period} = dclone($element);
            };
            # Delete the redundant information
            delete $NodeBalance->{'parameter'}->{$param}->{'binned_data'};
                        
            # Integrated data
            if (defined($NodeBalance->{'parameter'}->{$param}->{'integrated_data'})) {
                # Cycle over the integrated data
                foreach my $element (@{$NodeBalance->{'parameter'}->{$param}->{'integrated_data'}->{'bin'}}) {
                    my $period; # Define a period variable
                    if ($element->{'type'} eq 'annual') { # If the type is annual
                        $period = 'P00_Period'; # Store the period
                    }
                    elsif ($element->{'type'} eq 'monthly') { # Elsif the type is monthly
                        my $month = $num_month->{$element->{'number'} + $month_num_begin}; # Store the period by month name.
                        $period = sprintf("P%02u_%s", $month_num->{$month}, $month); # Store the period by mm_mmm
                    }
                    else { # Report if the type is unknown
         			&die_msg("Bad XML reporting integrated data bin type in $file: should be 'annual' or 'monthly'", $element->{'type'}, $coordinates);
                    };
                    
                    # Check that the integrated value is not NAN
                    if ($element->{'content'} =~ /nan/i) {
                        return(0);
                    };
                    
                    # Save the information (integrated value) up the tree under a key of 'integrated'
                    $parameters->{$param}->{$period}->{'integrated'} = $element->{'content'};
                };
        
                # Also store the integrated units type
                ($parameters->{$param}->{'units'}->{'integrated'}) = $NodeBalance->{'parameter'}->{$param}->{'integrated_data'}->{'units'};
                # Delete the redundant information
                delete $NodeBalance->{'parameter'}->{$param}->{'integrated_data'};
            };
        };
        
        return($XMLMOD);
        
    } else {return(0);};
};    

# Final return value of one to indicate that the perl module is successful
1;
