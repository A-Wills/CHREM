# ====================================================================
# Results.pm
# Author: Lukas Swan
# Date: Apr 2010
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# 
# ====================================================================

# Declare the package name of this perl module
package Results;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;
use XML::Simple;
use General;
use Storable  qw(dclone);
# use File::Copy;	# (to copy the xml file)

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(check_add_house_result results_headers print_results_out print_results_out_difference GHG_conversion_difference print_results_out_alt);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# check_add_house_result
# Checks and adds a house result to the results accumulation
# ====================================================================

sub check_add_house_result {
	my $hse_name = shift; # House name
	my $key = shift; # XML results key name
	my $param = shift; # Important part of the XML results key name
	my $val_type = shift; # e.g. integrated, minimum, maximum
	my $units = shift; # Units formats
	my $results_hse = shift; # The XML results for this house
	my $results_all = shift; # The results storage for all houses

	# Check to see if the value is defined
	if (defined($results_hse->{'parameter'}->{$key}->{'P00_Period'}->{$val_type})) {
		# Determine the units
		my $unit;
		if ($val_type eq 'integrated') {$unit = $results_hse->{'parameter'}->{$key}->{'units'}->{'integrated'};} # If integrated type
		else {$unit = $results_hse->{'parameter'}->{$key}->{'units'}->{'normal'};}; # All other types are normal

		# To account for ventilation fans, CHREM incorporated these into CHREM_AL. With the exception for space_cooling. As such the fan power for heating fans was set to zero, but the fan power for cooling fans was not. Therefore, any consumption for ventilation is actually associated with space cooling. Rather than have an extra consumption end-use associated with ventilation, this incorporates such consumption into the space_cooling
		my $var = $param; # Declare a variable the same as res_total to support changing the name without affecting the original
        # ADW JUL 2016: Ventilation should have it's own end use category. Adding ventilation power to space cooling skews the space cooling COP 
        #               post-processing calculation
		#$var =~ s/ventilation/space_cooling/; # Check for 'ventilation' and replace with 'space cool

		# Check to see if we have already defined this parameter. If not, then set it equal to the units. Later the parameter list will be used as a key to print everything out and provide info on the units
		unless (defined($results_all->{'parameter'}->{$var . '/' . $val_type})) {
			$results_all->{'parameter'}->{$var . '/' . $val_type} = $unit;
		};

		# Store the resultant house data that is formatted for units
		# Because of the ventilation/space_cooling issues, make sure to verify if space_cooling already exists.
		# If it does, then add to the result. If it doesn't, then simply set the result
		if (defined($results_all->{'house_results'}->{$hse_name}->{$var . '/' . $val_type})) {
			$results_all->{'house_results'}->{$hse_name}->{$var . '/' . $val_type} = $results_all->{'house_results'}->{$hse_name}->{$var . '/' . $val_type} + sprintf($units->{$unit}, $results_hse->{'parameter'}->{$key}->{'P00_Period'}->{$val_type});
		}
		else {
			$results_all->{'house_results'}->{$hse_name}->{$var . '/' . $val_type} = sprintf($units->{$unit}, $results_hse->{'parameter'}->{$key}->{'P00_Period'}->{$val_type});
		};
		
		# Store electricity consumption by month, as we need this later for the GHG emissions analysis
		if ($var =~ /electricity\/quantity$/) { # Check if we are that particular key
			my $elec_unit = $unit; # Store the units
			# NOTE - we could update the units here to give greater resolution if we felt it was necessary. But since the quantity of electricity is in units of kWh (high resolution) it is not presently of concern.
			# Loop over the periods - specifically ignore POO_Period which is annual and ignore everything else
			foreach my $period (@{&order($results_hse->{'parameter'}->{$key}, ['P0[1-9]_', 'P1\d_'], [''])}) {
				# Check that it exists
				if (defined($results_hse->{'parameter'}->{$key}->{$period}->{$val_type})) {
					# The following is the same as above
					if (defined($results_all->{'house_results_electricity'}->{$hse_name}->{$var . '/' . $val_type}->{$period})) {
						$results_all->{'house_results_electricity'}->{$hse_name}->{$var . '/' . $val_type}->{$period} = $results_all->{'house_results_electricity'}->{$hse_name}->{$var . '/' . $val_type}->{$period} + sprintf($units->{$elec_unit}, $results_hse->{'parameter'}->{$key}->{$period}->{$val_type});
					}
					else {
						$results_all->{'house_results_electricity'}->{$hse_name}->{$var . '/' . $val_type}->{$period} = sprintf($units->{$elec_unit}, $results_hse->{'parameter'}->{$key}->{$period}->{$val_type});
					};
				};
			};
		}
		
		# Check if we are a zone heat flux. If so - add them up according to the heating months from Nov thru Mar
		elsif ($var =~ /^zone_\d\d\/(CD_Opaq|CD_Trans|AV_AmbVent|AV_Infil|SW_Opaq|SW_Trans)\/energy$/) {
			# Check the months
			foreach my $period (@{&order($results_hse->{'parameter'}->{$key}, ['P0[1-3]_', 'P1[1-2]'], [''])}) {
				# Check that it exists
				if (defined($results_hse->{'parameter'}->{$key}->{$period}->{$val_type})) {
					# The following is the same as above
					if (defined($results_all->{'house_results'}->{$hse_name}->{'WNDW/' . $1 . '/energy/' . $val_type})) {
						$results_all->{'house_results'}->{$hse_name}->{'WNDW/' . $1 . '/energy/' . $val_type} = $results_all->{'house_results'}->{$hse_name}->{'WNDW/' . $1 . '/energy/' . $val_type} + sprintf($units->{$unit}, $results_hse->{'parameter'}->{$key}->{$period}->{$val_type});
					}
					else {
						$results_all->{'house_results'}->{$hse_name}->{'WNDW/' . $1 . '/energy/' . $val_type} = sprintf($units->{$unit}, $results_hse->{'parameter'}->{$key}->{$period}->{$val_type});
					};
				};
			};
			# Make sure to add it to the parameters list
			unless (defined($results_all->{'parameter'}->{'WNDW/' . $1 . '/energy/' . $val_type})) {
				$results_all->{'parameter'}->{'WNDW/' . $1 . '/energy/' . $val_type} = $unit;
			};
		};

	};

	return(1);
};


# ====================================================================
# results_headers
# Determines the results file header information such as groups, src, use, etc.
# ====================================================================

sub results_headers {
	my @parameters = @{shift()}; # The passed parameters to evaluate
	my @units = @{shift()}; # The passed units

	my $header_lines = {}; # Storage variable for the header lines
	my $line; # Temporarily holds the line type

	# Determine the group (site, src, use)
	$line = 'group';
	@{$header_lines->{$line}} = grep(s/^(\w+)\/.+$/$1/, @{dclone([@parameters])});
	
	# Determine the src (e.g. electricity, natural_gas)
	$line = 'src';
	foreach my $param (@parameters) {
# 		print "$param \n";
		if ($param =~ /^src\/(\w+)\//) {push(@{$header_lines->{$line}}, $1);} # If 
		elsif ($param =~ /^use\/\w+\/src\/(\w+)\//) {push(@{$header_lines->{$line}}, $1);}
		elsif ($param =~ /^gen\/\w+\/src\/(\w+)\//) {push(@{$header_lines->{$line}}, $1);}
		else {push(@{$header_lines->{$line}}, 'all');};
	};

	# Determine the use (e.g. space-heating, CHREM_AL)
	$line = 'use';
	foreach my $param (@parameters) {
		if ($param =~ /^use\/(\w+)\//) {push(@{$header_lines->{$line}}, $1);}
		else {push(@{$header_lines->{$line}}, 'all');};
	};
	
	# Determine the generation (e.g. PV)
	$line = 'gen';
	foreach my $param (@parameters) {
		if ($param =~ /^gen\/(\w+)\//) {push(@{$header_lines->{$line}}, $1);}
		else {push(@{$header_lines->{$line}}, 'all');};
	};

	# Determine the variable (e.g. GHG, energy, quantity)
	$line = 'variable';
	@{$header_lines->{$line}} = grep(s/^.+\/(\w+)\/\w+$/$1/, @{dclone([@parameters])});

	# Determine the descriptor (e.g. integrated, min, max)
	$line = 'descriptor';
	@{$header_lines->{$line}} = grep(s/^.+\/(\w+)$/$1/, @{dclone([@parameters])});

	# Determine the units (e.g. GJ, W)
	$line = 'units';
	@{$header_lines->{$line}} = @units;
	
	
	# Now construct a field name that is useful for displaying in tables
	$line = 'field';
	# Cycle over each element of the arrays. We use element number to keep track
	foreach my $element (0..$#parameters) {
		# If it is at the site level, then call it Total
		if ($header_lines->{'group'}->[$element] eq 'site') {
			# If it is integrated we don't need to say that
			if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
				push(@{$header_lines->{$line}}, 'Total ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			}
			# If it is not integrated then it is a power type so call it power instead of energy and provide the min/max etc.
			else {
				push(@{$header_lines->{$line}}, 'Total power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			};
		}
		# If it is a zone result
		elsif ($header_lines->{'group'}->[$element] =~ /^zone/) {
			# If it is integrated we don't need to say that
			if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
				push(@{$header_lines->{$line}}, $header_lines->{'group'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			}
			# If it is not integrated then it is a power type so call it power instead of energy and provide the min/max etc.
			else {
				push(@{$header_lines->{$line}}, $header_lines->{'group'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			};
		}
		# If it is a SH or SC result
		elsif ($header_lines->{'group'}->[$element] =~ /^(Heating_Sys|Cooling_Sys)/) {
			# If it is integrated we don't need to say that
			if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
				push(@{$header_lines->{$line}}, $header_lines->{'group'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			}
			# If it is not integrated then it is a power type so call it power instead of energy and provide the min/max etc.
			else {
				push(@{$header_lines->{$line}}, $header_lines->{'group'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			};
		}
		# Different energy src types
		elsif ($header_lines->{'group'}->[$element] eq 'src') {
			if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
				push(@{$header_lines->{$line}}, $header_lines->{'src'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			}
			else {
				push(@{$header_lines->{$line}}, $header_lines->{'src'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
			}; 
		}
		# Different end use groups
		elsif ($header_lines->{'group'}->[$element] eq 'use') {
			# Check to see if it is the total for the group or if it is by energy src
			if ($header_lines->{'src'}->[$element] eq 'all') {
				if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
					push(@{$header_lines->{$line}}, $header_lines->{'use'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				}
				else {
					push(@{$header_lines->{$line}}, $header_lines->{'use'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				};
			}
			# This is by energy src
			else {
				if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
					push(@{$header_lines->{$line}}, $header_lines->{'use'}->[$element] . ' ' . $header_lines->{'src'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				}
				else {
					push(@{$header_lines->{$line}}, $header_lines->{'use'}->[$element] . ' ' . $header_lines->{'src'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				};
			};
		}
		# Different generation of electricty
		elsif ($header_lines->{'group'}->[$element] eq 'gen') {
			# Check to see if it is the total for the group or if it is by energy src
			if ($header_lines->{'src'}->[$element] eq 'all') {
				if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
					push(@{$header_lines->{$line}}, $header_lines->{'gen'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				}
				else {
					push(@{$header_lines->{$line}}, $header_lines->{'gen'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				};
			}
			# This is by energy src
			else {
				if ($header_lines->{'descriptor'}->[$element] eq 'integrated') {
					push(@{$header_lines->{$line}}, $header_lines->{'gen'}->[$element] . ' ' . $header_lines->{'src'}->[$element] . ' ' . $header_lines->{'variable'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				}
				else {
					push(@{$header_lines->{$line}}, $header_lines->{'gen'}->[$element] . ' ' . $header_lines->{'src'}->[$element] . ' power ' . $header_lines->{'descriptor'}->[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
				};
			};
		}
		# Otherwise simply output the full name and units because we don't know what to do
		else {
			push(@{$header_lines->{$line}}, $parameters[$element] . ' (' . $header_lines->{'units'}->[$element] . ')');
		};
		# Finally capitalize the first digit to make it look better
		push(@{$header_lines->{$line}}, &capitalize_first_letter(pop(@{$header_lines->{$line}})));
	};

	return($header_lines);
};



#--------------------------------------------------------------------
# Subroutine to print out the Results
#--------------------------------------------------------------------
sub print_results_out {
	my $results_all = shift;
	my $set_name = shift;

	# List the provinces in the preferred order
	my @provinces = ('NEWFOUNDLAND', 'NOVA SCOTIA' ,'PRINCE EDWARD ISLAND', 'NEW BRUNSWICK', 'QUEBEC', 'ONTARIO', 'MANITOBA', 'SASKATCHEWAN' ,'ALBERTA' ,'BRITISH COLUMBIA');
	my $prov_acronym;
	@{$prov_acronym}{@provinces} = qw(NF NS PE NB QC OT MB SK AB BC);
	
	# If there is BAD HOUSE data then print it
	if (defined($results_all->{'bad_houses'})) {
		# Create a file to print out the bad houses
		my $filename = "../summary_files/Results$set_name" . '_Bad.csv';
		open (my $FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Print the header information
		print $FILE CSVjoin(qw(*header region province hse_type hse_name issue)) . "\n";

		# Cycle over each region, ,province and house type to print the bad house issue
		foreach my $region (@{&order($results_all->{'bad_houses'})}) {
			foreach my $province (@{&order($results_all->{'bad_houses'}->{$region}, [@provinces])}) {
				foreach my $hse_type (@{&order($results_all->{'bad_houses'}->{$region}->{$province})}) {
					# Cycle over each house with results and print out the issue
					foreach my $hse_name (@{&order($results_all->{'bad_houses'}->{$region}->{$province}->{$hse_type})}) {
						my ($region_short) = ($region =~ /\d-(\w{2})/);
						my ($hse_type_short) = ($hse_type =~ /\d-(\w{2})/);
						my $prov_short = $prov_acronym->{$province};
						print $FILE CSVjoin('*data', $region_short, $prov_short, $hse_type_short, $hse_name, $results_all->{'bad_houses'}->{$region}->{$province}->{$hse_type}->{$hse_name}) . "\n";
					};
				};
			};
		};
		close $FILE; # The Bas house data file is complete
	};



	# Declare and fill out a set out formats for values with particular units
	my $units = {};
	@{$units}{qw(GJ W kg kWh l m3 tonne COP)} = qw(%.1f %.0f %.0f %.0f %.0f %.0f %.3f %.2f);

	my $SHEU03_houses = {}; # Declare a variable to store the total number of desired houses based on SHEU-1993

	# Fill out the number of desired houses for each province. These values are a combination of SHEU-2003 (being the baseline and providing the regional values) and CENSUS 2006 (to distribute the regional values by province)
	@{$SHEU03_houses->{'1-SD'}}{@provinces} = qw(148879 259392 38980 215084 1513497 2724438 305111 285601 790508 910051);
	@{$SHEU03_houses->{'2-DR'}}{@provinces} = qw(26098 38778 6014 23260 469193 707777 34609 29494 182745 203449);


	if (defined($results_all->{'parameter'}) && defined($results_all->{'house_names'})) {
		# Order the results that we want to printout for each house
# 		my @result_params = @{&order($results_all->{'parameter'}, [qw(site src use)])};

		# Also create a totalizer of integrated units that will sum up for each province and house type individually
		my @result_total = grep(/^site\/\w+\/integrated$/, @{&order($results_all->{'parameter'}, [qw(site src use gen)])}); # Only store site consumptions
		push(@result_total, grep(/^src\/\w+\/\w+\/integrated$/, @{&order($results_all->{'parameter'}, [qw(site src use gen)])})); # Append src total consumptions
		push(@result_total, grep(/^use\/\w+\/\w+\/integrated$/, @{&order($results_all->{'parameter'}, [qw(site src use gen)])})); # Append end use total consumptions
		push(@result_total, grep(/^gen\/\w+\/\w+\/\w+\/\w+\/integrated$/, @{&order($results_all->{'parameter'}, [qw(site src use gen)])})); # Append electricity generation
		push(@result_total, @{&order($results_all->{'parameter'}, [qw(Zone_heat Heating_Sys Zone_cool Cooling_Sys)], [''])}); # Append zone and system heating/cooling info
		push(@result_total, @{&order($results_all->{'parameter'}, [qw(WNDW)], [''])}); # Append zone WNDW analysis information
# 		print Dumper $results_all->{'parameter'};
# 		print "\n@result_total\n";;
		# Create a file to print out the house results to
		my $filename = "../summary_files/Results$set_name" . '_Houses.csv';
		open (my $FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Setup the header lines for printing by passing refs to the variables and units
# 		my $header_lines = &results_headers([@result_params], [@{$results_all->{'parameter'}}{@result_params}]);
		my $header_lines = &results_headers([@result_total], [@{$results_all->{'parameter'}}{@result_total}]);

		# We have a few extra fields to put in place so make some spaces for other header lines
		my @space = ('', '', '', '', '');

		# Print out the header lines to the file. Note the space usage
		print $FILE CSVjoin(qw(*group), @space, @{$header_lines->{'group'}}) . "\n";
		print $FILE CSVjoin(qw(*src), @space, @{$header_lines->{'src'}}) . "\n";
		print $FILE CSVjoin(qw(*use), @space, @{$header_lines->{'use'}}) . "\n";
		print $FILE CSVjoin(qw(*gen), @space, @{$header_lines->{'gen'}}) . "\n";
		print $FILE CSVjoin(qw(*variable), @space, @{$header_lines->{'variable'}}) . "\n";
		print $FILE CSVjoin(qw(*descriptor), @space, @{$header_lines->{'descriptor'}}) . "\n";
		print $FILE CSVjoin(qw(*units), @space, @{$header_lines->{'units'}}) . "\n";
		print $FILE CSVjoin(qw(*field house_name region province hse_type required_multiplier), @{$header_lines->{'field'}}) . "\n";


		# Declare a variable to store the total results by province and house type
		my $results_tot;

		# Cycle over each region, ,province and house type to store and accumulate the results
		foreach my $region (@{&order($results_all->{'house_names'})}) {
			foreach my $province (@{&order($results_all->{'house_names'}->{$region}, [@provinces])}) {
				foreach my $hse_type (@{&order($results_all->{'house_names'}->{$region}->{$province})}) {
					
					my ($region_short) = ($region =~ /\d-(\w{2})/);
					my ($hse_type_short) = ($hse_type =~ /\d-(\w{2})/);
					my $prov_short = $prov_acronym->{$province};
					
					# To determine the multiplier for the house type for a province, we must first determine the total desirable houses
					my $total_houses;
					# If it is defined in SHEU then use the number (this is to account for test cases like 3-CB)
					if (defined($SHEU03_houses->{$hse_type}->{$province})) {$total_houses = $SHEU03_houses->{$hse_type}->{$province};}
					# Otherwise set it equal to the number of present houses so the multiplier is 1
					else {$total_houses = @{$results_all->{'house_names'}->{$region}->{$province}->{$hse_type}};};
					
					# Calculate the house multiplier and format
					my $multiplier = sprintf("%.1f", $total_houses / @{$results_all->{'house_names'}->{$region}->{$province}->{$hse_type}});
					# Store the multiplier in the totalizer where it will be used later to scale the total results
					$results_tot->{$region}->{$province}->{$hse_type}->{'multiplier'} = $multiplier;

					# Cycle over each house with results and print out the results
					foreach my $hse_name (@{&order($results_all->{'house_names'}->{$region}->{$province}->{$hse_type})}) {
						# Print out the desirable fields and hten printout all the results for this house
# 						print $FILE CSVjoin('*data', $hse_name, $region_short, $prov_short, $hse_type_short, $multiplier, @{$results_all->{'house_results'}->{$hse_name}}{@result_params}) . "\n";
						print $FILE CSVjoin('*data', $hse_name, $region_short, $prov_short, $hse_type_short, $multiplier, @{$results_all->{'house_results'}->{$hse_name}}{@result_total}) . "\n";
						
						# Accumulate the results for this house into the provincial and house type total
						# Only cycle over the desirable fields (integrated only)
						foreach my $res_tot (@result_total) {
							# If the field exists for this house, then add it to the accumulator
							if (defined($results_all->{'house_results'}->{$hse_name}->{$res_tot})) {
								# To account for ventilation fans, CHREM incorporated these into CHREM_AL. With the exception for space_cooling. As such the fan power for heating fans was set to zero, but the fan power for cooling fans was not. Therefore, any consumption for ventilation is actually associated with space cooling. Rather than have an extra consumption end-use associated with ventilation, this incorporates such consumption into the space_cooling
								my $var = $res_tot; # Declare a variable the same as res_total to support changing the name without affecting the original
								$var =~ s/ventilation/space_cooling/; # Check for 'ventilation' and replace with 'space cooling'
								
								# If this is the first time encountered then set equal to zero. Use '$var'
								unless (defined($results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var})) {
									$results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var} = 0;
								};

								# Note the use of 'simulated'. This is so we can have a 'scaled' and 'per house' later
								# Note the use of $var for the totalizer and the use of $res_tot for the individual house results
								$results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var} = $results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var} + $results_all->{'house_results'}->{$hse_name}->{$res_tot};
							};
						};
					};
				};
			};
		};

		close $FILE; # The individual house data file is complete

		# Create a file to print the total scaled provincial results to
		$filename = "../summary_files/Results$set_name" . '_Total.csv';
		open ($FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Declare and fill out a set of unit conversions for totalizing
		my @unit_base = qw(GJ kg kWh l m3 tonne COP);
		my $unit_conv = {};
		@{$unit_conv->{'unit'}}{@unit_base} = qw(PJ Mt TWh Ml km3 Mt BOGUS);
		@{$unit_conv->{'mult'}}{@unit_base} = qw(1e-6 1e-9 1e-9 1e-6 1e-9 1e-6 0);
		@{$unit_conv->{'format'}}{@unit_base} = qw(%.1f %.2f %.1f %.1f %.3f %.2f %.0f);

		# Determine the appropriate units for the totalized values
		my @converted_units = @{$unit_conv->{'unit'}}{@{$results_all->{'parameter'}}{@result_total}};

		# Setup the header lines for printing by passing refs to the variables and units
		$header_lines = &results_headers([@result_total], [@converted_units]);


		# We have a few extra fields to put in place so make some spaces for other header lines
		@space = ('', '', '', '', '');

		# Print out the header lines to the file. Note the space usage
		print $FILE CSVjoin(qw(*group), @space, @{$header_lines->{'group'}}) . "\n";
		print $FILE CSVjoin(qw(*src), @space, @{$header_lines->{'src'}}) . "\n";
		print $FILE CSVjoin(qw(*use), @space, @{$header_lines->{'use'}}) . "\n";
		print $FILE CSVjoin(qw(*gen), @space, @{$header_lines->{'gen'}}) . "\n";
		print $FILE CSVjoin(qw(*variable), @space, @{$header_lines->{'variable'}}) . "\n";
		print $FILE CSVjoin(qw(*descriptor), @space, @{$header_lines->{'descriptor'}}) . "\n";
		print $FILE CSVjoin(qw(*units), @space, @{$header_lines->{'units'}}) . "\n";
		print $FILE CSVjoin(qw(*field source region province hse_type multiplier_used), @{$header_lines->{'field'}}) . "\n";

		my $results_Canada = {};

		# Cycle over the provinces and house types
		foreach my $region (@{&order($results_tot)}) {
			foreach my $province (@{&order($results_tot->{$region}, [@provinces])}) {
				foreach my $hse_type (@{&order($results_tot->{$region}->{$province})}) {
				
					my ($region_short) = ($region =~ /\d-(\w{2})/);
					my ($hse_type_short) = ($hse_type =~ /\d-(\w{2})/);
					my $prov_short = $prov_acronym->{$province};
				
					# Cycle over the desired accumulated results and scale them to national values using the previously calculated house representation multiplier
					foreach my $res_tot (@result_total) {
						if (defined($results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$res_tot})) {
							my $unit_orig = $results_all->{'parameter'}->{$res_tot};
							my $conversion = $unit_conv->{'mult'}->{$unit_orig};
							my $format = $unit_conv->{'format'}->{$unit_orig};
							# Note these are placed at 'scaled' so as not to corrupt the 'simulated' results, so that they may be used at a later point
							$results_tot->{$region}->{$province}->{$hse_type}->{'scaled'}->{$res_tot} = sprintf($format, $results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$res_tot} * $results_tot->{$region}->{$province}->{$hse_type}->{'multiplier'} * $conversion);
							# Add it to the national total
							unless (defined($results_Canada->{$hse_type_short}->{$res_tot})) {
								$results_Canada->{$hse_type_short}->{$res_tot} = 0
							};
							$results_Canada->{$hse_type_short}->{$res_tot} = sprintf($format, $results_Canada->{$hse_type_short}->{$res_tot} + $results_tot->{$region}->{$province}->{$hse_type}->{'scaled'}->{$res_tot});
						};
						
					};
					# Print out the national total results
					print $FILE CSVjoin('*data', 'CHREM', $region_short, $prov_short, $hse_type_short, $results_tot->{$region}->{$province}->{$hse_type}->{'multiplier'}, @{$results_tot->{$region}->{$province}->{$hse_type}->{'scaled'}}{@result_total}) . "\n";
				};
			};
		};
		
		foreach my $hse_type (@{&order($results_Canada, [qw(SD DR)])}) {
			print $FILE CSVjoin('*data', 'CHREM', 'Canada', '', $hse_type, 1, @{$results_Canada->{$hse_type}}{@result_total}) . "\n";
		};
		
		$filename = "../keys/SHEU_03_results.xml";
		my $SHEU_03_results = XMLin($filename, ContentKey => '-value');
# 		print Dumper XMLout($SHEU_03_results);
		foreach my $region (@{&order($SHEU_03_results->{'region'}, [qw(AT QC OT PR BC Canada)])}) {
			foreach my $hse_type (@{&order($SHEU_03_results->{'region'}->{$region}->{'house_type'}, [qw(SD DR)])}) {
				# Print out the national total results
				print $FILE CSVjoin('*data', 'SHEU-03', $region, '', $hse_type, 1, @{$SHEU_03_results->{'region'}->{$region}->{'house_type'}->{$hse_type}->{'var'}}{@result_total}) . "\n";
			};
		};
		
		$filename = "../keys/REUM_00_04_results.xml";
		my $REUM_00_04_results = XMLin($filename);
# 		print Dumper ($REUM_00_04_results);
		foreach my $hse_type (@{&order($REUM_00_04_results->{'house_type'}, [qw(SD DR)])}) {
			foreach my $var(@{&order($REUM_00_04_results->{'house_type'}->{$hse_type}->{'var'})}) {
				my $short = $REUM_00_04_results->{'house_type'}->{$hse_type}->{'var'}->{$var};
				$REUM_00_04_results->{'house_type'}->{$hse_type}->{'var'}->{$var} = sprintf("%.1f", $short->{'value'} * $short->{'multiplier'});
			};
			# Print out the national total results
			print $FILE CSVjoin('*data', 'REUM-00-04', 'Canada', '', $hse_type, 1, @{$REUM_00_04_results->{'house_type'}->{$hse_type}->{'var'}}{@result_total}) . "\n";
		};
		

		close $FILE; # The national scaled totals are now complete


		# Create a file to print the total scaled provincial results to
		$filename = "../summary_files/Results$set_name" . '_Average.csv';
		open ($FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Determine the header lines. Because this is per house the base units will stay
		$header_lines = &results_headers([@result_total], [@{$results_all->{'parameter'}}{@result_total}]);

		# We have a few extra fields to put in place so make some spaces for other header lines
		@space = ('', '', '', '');

		# Print out the header lines to the file. Note the space usage
		print $FILE CSVjoin(qw(*group), @space, @{$header_lines->{'group'}}) . "\n";
		print $FILE CSVjoin(qw(*src), @space, @{$header_lines->{'src'}}) . "\n";
		print $FILE CSVjoin(qw(*use), @space, @{$header_lines->{'use'}}) . "\n";
		print $FILE CSVjoin(qw(*gen), @space, @{$header_lines->{'gen'}}) . "\n";
		print $FILE CSVjoin(qw(*variable), @space, @{$header_lines->{'variable'}}) . "\n";
		print $FILE CSVjoin(qw(*descriptor), @space, @{$header_lines->{'descriptor'}}) . "\n";
		print $FILE CSVjoin(qw(*units), @space, @{$header_lines->{'units'}}) . "\n";
		print $FILE CSVjoin(qw(*field region province hse_type multiplier_used), @{$header_lines->{'field'}}) . "\n";

		# Cycle over the provinces and house types. NOTE we also cycle over region so we can pick up the total number of houses to divide by
		foreach my $region (@{&order($results_tot)}) {
			foreach my $province (@{&order($results_tot->{$region}, [@provinces])}) {
				foreach my $hse_type (@{&order($results_tot->{$region}->{$province})}) {
				
					my ($region_short) = ($region =~ /\d-(\w{2})/);
					my ($hse_type_short) = ($hse_type =~ /\d-(\w{2})/);
					my $prov_short = $prov_acronym->{$province};
				
					# Cycle over the desired accumulated results and divide them down to the avg house using the total number of simulated houses
					foreach my $res_tot (@result_total) {

						if (defined($results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$res_tot})) {
					
							# Note these are placed at 'avg' so as not to corrupt the 'simulated' results, so that they may be used at a later point
							$results_tot->{$region}->{$province}->{$hse_type}->{'avg'}->{$res_tot} = sprintf($units->{$results_all->{'parameter'}->{$res_tot}}, $results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$res_tot} / @{$results_all->{'house_names'}->{$region}->{$province}->{$hse_type}});
						};
					};
					print $FILE CSVjoin('*data', $region_short, $prov_short, $hse_type_short, 'avg per house', @{$results_tot->{$region}->{$province}->{$hse_type}->{'avg'}}{@result_total}) . "\n";
				};
			};
		};

		close $FILE;
	};
	return();
};

#--------------------------------------------------------------------
# Subroutine to print out the Results
# This is very similar to the last routine, with the exception that it doesnt include national comparitors (i.e. SHEU and REUM),
# and uses difference units because upgrades effects are smaller than PJ and Mt
#--------------------------------------------------------------------
sub print_results_out_difference {
	my $results_all = shift; # Three sets of results: orig, upgraded, difference
	my $set_name = shift; # The set name to store the difference results at
	print "Started the print_results_out_difference routine\n";

	# We only want to focus on the difference
	# NOTE that we pass all the sets to get the correct multipliers
	my $results_diff = $results_all->{'difference'};

	# List the provinces in the preferred order
	my @provinces = ('NEWFOUNDLAND', 'NOVA SCOTIA' ,'PRINCE EDWARD ISLAND', 'NEW BRUNSWICK', 'QUEBEC', 'ONTARIO', 'MANITOBA', 'SASKATCHEWAN' ,'ALBERTA' ,'BRITISH COLUMBIA');
	my $prov_acronym;
	@{$prov_acronym}{@provinces} = qw(NF NS PE NB QC OT MB SK AB BC);

	# Declare and fill out a set out formats for values with particular units
	my $units = {};
	@{$units}{qw(GJ W kg kWh l m3 tonne COP)} = qw(%.1f %.0f %.0f %.0f %.0f %.0f %.3f %.2f);

	my $SHEU03_houses = {}; # Declare a variable to store the total number of desired houses based on SHEU-1993

	# Fill out the number of desired houses for each province. These values are a combination of SHEU-2003 (being the baseline and providing the regional values) and CENSUS 2006 (to distribute the regional values by province)
	@{$SHEU03_houses->{'1-SD'}}{@provinces} = qw(148879 259392 38980 215084 1513497 2724438 305111 285601 790508 910051);
	@{$SHEU03_houses->{'2-DR'}}{@provinces} = qw(26098 38778 6014 23260 469193 707777 34609 29494 182745 203449);

	# Insure that ordered information and houses are present
	if (defined($results_diff->{'parameter'}) && defined($results_diff->{'house_names'})) {
		# Order the results that we want to printout for each house
		# Create a totalizer of integrated units that will sum up for each province and house type individually
		my @result_total = grep(/^site\/\w+\/integrated$/, @{&order($results_diff->{'parameter'}, [qw(site src use gen)])}); # Only store site consumptions
		push(@result_total, grep(/^src\/\w+\/\w+\/integrated$/, @{&order($results_diff->{'parameter'}, [qw(site src use gen)])})); # Append src total consumptions
		push(@result_total, grep(/^use\/\w+\/\w+\/integrated$/, @{&order($results_diff->{'parameter'}, [qw(site src use gen)])})); # Append end use total consumptions
		push(@result_total, grep(/^gen\/\w+\/\w+\/\w+\/\w+\/integrated$/, @{&order($results_diff->{'parameter'}, [qw(site src use gen)])})); # Append elecricity generation
		push(@result_total, @{&order($results_diff->{'parameter'}, [qw(Zone_heat Heating_Sys Zone_cool Cooling_Sys)], [''])}); # Append zone and system heating/cooling info
		
		# Create a file to print out the house results to
		my $filename = "../summary_files/Results$set_name" . '_Houses.csv';
		open (my $FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Setup the header lines for printing by passing refs to the variables and units
		my $header_lines = &results_headers([@result_total], [@{$results_diff->{'parameter'}}{@result_total}]);

		# We have a few extra fields to put in place so make some spaces for other header lines
		my @space = ('', '', '', '', '');

		# Print out the header lines to the file. Note the space usage
		print $FILE CSVjoin(qw(*group), @space, @{$header_lines->{'group'}}) . "\n";
		print $FILE CSVjoin(qw(*src), @space, @{$header_lines->{'src'}}) . "\n";
		print $FILE CSVjoin(qw(*use), @space, @{$header_lines->{'use'}}) . "\n";
		print $FILE CSVjoin(qw(*variable), @space, @{$header_lines->{'variable'}}) . "\n";
		print $FILE CSVjoin(qw(*descriptor), @space, @{$header_lines->{'descriptor'}}) . "\n";
		print $FILE CSVjoin(qw(*units), @space, @{$header_lines->{'units'}}) . "\n";
		# The previous space was used to save room for the following fields
		print $FILE CSVjoin(qw(*field house_name region province hse_type required_multiplier), @{$header_lines->{'field'}}) . "\n";

		# Declare a variable to store the total results by province and house type
		my $results_tot;

		# Cycle over each region, province, and house type to store and accumulate the results
		foreach my $region (@{&order($results_diff->{'house_names'})}) {
			foreach my $province (@{&order($results_diff->{'house_names'}->{$region}, [@provinces])}) {
				foreach my $hse_type (@{&order($results_diff->{'house_names'}->{$region}->{$province})}) {
					
					my ($region_short) = ($region =~ /\d-(\w{2})/);
					my ($hse_type_short) = ($hse_type =~ /\d-(\w{2})/);
					my $prov_short = $prov_acronym->{$province};
					
					# To determine the multiplier for the house type for a province, we must first determine the total desirable houses
					my $total_houses;
					# If it is defined in SHEU then use the number (this is to account for test cases like 3-CB)
					if (defined($SHEU03_houses->{$hse_type}->{$province})) {$total_houses = $SHEU03_houses->{$hse_type}->{$province};}
					# Otherwise set it equal to the number of present houses so the multiplier is 1
					else {$total_houses = @{$results_diff->{'house_names'}->{$region}->{$province}->{$hse_type}};};
					
					# Calculate the house multiplier and format -NOTE USE THE ORIGINAL NUMBER OF HOUSES TO SCALE CORRECTLY
					# If we scale based the difference, the multiplier would be large as it would be to scale the upgraded only houses up to national.
					# Instead use the multipliers from the original set
					my $multiplier = sprintf("%.1f", $total_houses / @{$results_all->{'orig'}->{'house_names'}->{$region}->{$province}->{$hse_type}});
					# Store the multiplier in the totalizer where it will be used later to scale the total results
					$results_tot->{$region}->{$province}->{$hse_type}->{'multiplier'} = $multiplier;

					# Cycle over each house with results and print out the results
					foreach my $hse_name (@{&order($results_diff->{'house_names'}->{$region}->{$province}->{$hse_type})}) {
						# Print out the desirable fields and then printout all the results for this house
						print $FILE CSVjoin('*data', $hse_name, $region_short, $prov_short, $hse_type_short, $multiplier, @{$results_diff->{'house_results'}->{$hse_name}}{@result_total}) . "\n";
						
						# Accumulate the results for this house into the provincial and house type total
						# Only cycle over the desirable fields (integrated only)
						foreach my $res_tot (@result_total) {
							# If the field exists for this house, then add it to the accumulator
							if (defined($results_diff->{'house_results'}->{$hse_name}->{$res_tot})) {
								# To account for ventilation fans, CHREM incorporated these into CHREM_AL. With the exception for space_cooling. As such the fan power for heating fans was set to zero, but the fan power for cooling fans was not. Therefore, any consumption for ventilation is actually associated with space cooling. Rather than have an extra consumption end-use associated with ventilation, this incorporates such consumption into the space_cooling
								my $var = $res_tot; # Declare a variable the same as res_total to support changing the name without affecting the original
								$var =~ s/ventilation/space_cooling/; # Check for 'ventilation' and replace with 'space cooling'
								
								# If this is the first time encountered then set equal to zero. Use '$var'
								unless (defined($results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var})) {
									$results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var} = 0;
								};

								# Note the use of 'simulated'. This is so we can have a 'scaled' and 'per house' later
								# Note the use of $var for the totalizer and the use of $res_tot for the individual house results
								$results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var} = $results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$var} + $results_diff->{'house_results'}->{$hse_name}->{$res_tot};
							};
						};
					};
				};
			};
		};

		close $FILE; # The individual house data file is complete
		print "Completed the Individual House difference values printout\n";

		# Print out any bad houses that did not do a difference
		if (defined($results_all->{'difference'}->{'house_names_bad'})) {
			# Create a file to print the bad house names results
			$filename = "../summary_files/Results$set_name" . '_Bad_Houses.txt';
			open ($FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");
			print $FILE Dumper $results_all->{'difference'}->{'house_names_bad'};
			close $FILE; # The bad house file is complete
			print "Completed the Bad House Names printout\n";
		};

		# Create a file to print the total scaled provincial results
		$filename = "../summary_files/Results$set_name" . '_Total.csv';
		open ($FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Declare and fill out a set of unit conversions for totalizing
		my @unit_base = qw(GJ kg kWh l m3 tonne COP);
		my $unit_conv = {};
		# These units have been adjusted to represent just the upgrades (so the units are less than PJ and Mt)
		@{$unit_conv->{'unit'}}{@unit_base} = qw(TJ kt GWh kl km3 kt BOGUS);
		@{$unit_conv->{'mult'}}{@unit_base} = qw(1e-3 1e-6 1e-6 1e-3 1e-9 1e-3 0);
		@{$unit_conv->{'format'}}{@unit_base} = qw(%.1f %.2f %.1f %.1f %.3f %.2f %.0f);

		# Determine the appropriate units for the totalized values
		my @converted_units = @{$unit_conv->{'unit'}}{@{$results_diff->{'parameter'}}{@result_total}};

		# Setup the header lines for printing by passing refs to the variables and units
		$header_lines = &results_headers([@result_total], [@converted_units]);


		# We have a few extra fields to put in place so make some spaces for other header lines
		@space = ('', '', '', '', '');

		# Print out the header lines to the file. Note the space usage
		print $FILE CSVjoin(qw(*group), @space, @{$header_lines->{'group'}}) . "\n";
		print $FILE CSVjoin(qw(*src), @space, @{$header_lines->{'src'}}) . "\n";
		print $FILE CSVjoin(qw(*use), @space, @{$header_lines->{'use'}}) . "\n";
		print $FILE CSVjoin(qw(*variable), @space, @{$header_lines->{'variable'}}) . "\n";
		print $FILE CSVjoin(qw(*descriptor), @space, @{$header_lines->{'descriptor'}}) . "\n";
		print $FILE CSVjoin(qw(*units), @space, @{$header_lines->{'units'}}) . "\n";
		print $FILE CSVjoin(qw(*field source region province hse_type multiplier_used), @{$header_lines->{'field'}}) . "\n";

		my $results_Canada = {};

		# Cycle over the provinces and house types
		foreach my $region (@{&order($results_tot)}) {
			foreach my $province (@{&order($results_tot->{$region}, [@provinces])}) {
				foreach my $hse_type (@{&order($results_tot->{$region}->{$province})}) {
				
					my ($region_short) = ($region =~ /\d-(\w{2})/);
					my ($hse_type_short) = ($hse_type =~ /\d-(\w{2})/);
					my $prov_short = $prov_acronym->{$province};
				
					# Cycle over the desired accumulated results and scale them to national values using the previously calculated house representation multiplier
					foreach my $res_tot (@result_total) {
						if (defined($results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$res_tot})) {
							my $unit_orig = $results_diff->{'parameter'}->{$res_tot};
							my $conversion = $unit_conv->{'mult'}->{$unit_orig};
							my $format = $unit_conv->{'format'}->{$unit_orig};
							# Note these are placed at 'scaled' so as not to corrupt the 'simulated' results, so that they may be used at a later point
							$results_tot->{$region}->{$province}->{$hse_type}->{'scaled'}->{$res_tot} = sprintf($format, $results_tot->{$region}->{$province}->{$hse_type}->{'simulated'}->{$res_tot} * $results_tot->{$region}->{$province}->{$hse_type}->{'multiplier'} * $conversion);
							# Add it to the national total
							unless (defined($results_Canada->{$hse_type_short}->{$res_tot})) {
								$results_Canada->{$hse_type_short}->{$res_tot} = 0
							};
							$results_Canada->{$hse_type_short}->{$res_tot} = sprintf($format, $results_Canada->{$hse_type_short}->{$res_tot} + $results_tot->{$region}->{$province}->{$hse_type}->{'scaled'}->{$res_tot});
						};
						
					};
					# Print out the national total results
					print $FILE CSVjoin('*data', 'CHREM', $region_short, $prov_short, $hse_type_short, $results_tot->{$region}->{$province}->{$hse_type}->{'multiplier'}, @{$results_tot->{$region}->{$province}->{$hse_type}->{'scaled'}}{@result_total}) . "\n";
				};
			};
		};
		
		foreach my $hse_type (@{&order($results_Canada, [qw(SD DR)])}) {
			print $FILE CSVjoin('*data', 'CHREM', 'Canada', '', $hse_type, 1, @{$results_Canada->{$hse_type}}{@result_total}) . "\n";
		};
		

		close $FILE; # The national scaled totals are now complete
		print "Completed the Canada and Provinces difference values printout\n";

	};
	return();
};


# ====================================================================
# GHG_conversion_difference
# This converts utility energy to GHG from the xml log reporting
# ====================================================================

sub GHG_conversion_difference {
	my $results_all = shift;

	my $ghg_file;
	if (-e '../../../keys/GHG_key.xml') {$ghg_file = '../../../keys/GHG_key.xml'}
	elsif (-e '../keys/GHG_key.xml') {$ghg_file = '../keys/GHG_key.xml'}
	my $GHG = XMLin($ghg_file);

	# Remove the 'en_src' field
	my $en_srcs = $GHG->{'en_src'};


	# Cycle over the energy and quantity differences and calculate the change in GHG emissions
	foreach my $region (keys(%{$results_all->{'difference'}->{'house_names'}})) { # By region
		foreach my $province (keys(%{$results_all->{'difference'}->{'house_names'}->{$region}})) { # By province
			foreach my $hse_type (keys(%{$results_all->{'difference'}->{'house_names'}->{$region}->{$province}})) { # By house type
				foreach my $house (@{$results_all->{'difference'}->{'house_names'}->{$region}->{$province}->{$hse_type}}) { # Cycle over each listed house
					# Declare variables to accumulate GHG values
					my $site_ghg; # The total GHG emissions at the site
					my $use_ghg; # The total emissions for a given use type
					
					# Create a shortcut
					my $house_result = $results_all->{'difference'}->{'house_results'}->{$house};
					my $house_elec_result = $results_all->{'difference'}->{'house_results_electricity'}->{$house};
				
					# Cycle over the difference results for this house and do the comparison
					foreach my $key (keys(%{$house_result})) {
						# Calculate for the different energy sources (all end uses combined)
						if ($key =~ /^src\/(\w+)\/quantity\/integrated$/) {
							my $src = $1; # Store the source type
							# Apply the GHG emission intensity factor if it is any on-site fuel
							unless ($src =~ /electricity/) {
								$house_result->{"src/$src/GHG/integrated"} = $house_result->{$key} * $en_srcs->{$src}->{'GHGIF'} / 1000;
							}
							# Treat electricity differently due to the marginal factor and the monthly values
							else { # electricity
								my $per_sum = 0; # Declare for Period summations
								foreach my $period (@{&order($house_elec_result->{$key})}) { # These are months and annual
									my $mult;
									# Check to see if a monthly EIF exists. If it does use it.
									if (defined($en_srcs->{$src}->{'province'}->{$province}->{'period'}->{$period}->{'GHGIFmarginal'})) {
										$mult = $en_srcs->{$src}->{'province'}->{$province}->{'period'}->{$period}->{'GHGIFmarginal'};
									}
									# Otherwise use the annual marginal value
									else {
										$mult = $en_srcs->{$src}->{'province'}->{$province}->{'period'}->{'P00_Period'}->{'GHGIFmarginal'};
									};
									# Keep a running total - add each month up as the factors may be different but we also want to give a annual savings value
									$per_sum += $house_elec_result->{$key}->{$period} / (1 - $en_srcs->{$src}->{'province'}->{$province}->{'trans_dist_loss'}) * $mult / 1000;
								};
								# Store the annual sum (which is based off the monthly sums)
								$house_result->{"src/$src/GHG/integrated"} = $per_sum;
							};
							# Keep a running total of total site GHG
							$site_ghg += $house_result->{"src/$src/GHG/integrated"};
							# Store the units of GHG emissions
							$results_all->{'difference'}->{'parameter'}->{"src/$src/GHG/integrated"} = 'kg';
						}
						# Calculate for each end-use by energy type
						elsif ($key =~ /^use\/(\w+)\/src\/(\w+)\/quantity\/integrated$/) {
							my $use = $1;
							my $src = $2;
							# For all on-site consumption determine the emission factor and apply it
							unless ($src =~ /electricity/) {
								$house_result->{"use/$use/src/$src/GHG/integrated"} = $house_result->{$key} * $en_srcs->{$src}->{'GHGIF'} / 1000;
							}
							# Treat electricity separately due to the marginal and monthly use
							# See the above comments regarding what this code does
							else { # electricity
								my $per_sum = 0;
								foreach my $period (@{&order($house_elec_result->{$key})}) {
									my $mult;
									if (defined($en_srcs->{$src}->{'province'}->{$province}->{'period'}->{$period}->{'GHGIFmarginal'})) {
										$mult = $en_srcs->{$src}->{'province'}->{$province}->{'period'}->{$period}->{'GHGIFmarginal'};
									}
									else {
										$mult = $en_srcs->{$src}->{'province'}->{$province}->{'period'}->{'P00_Period'}->{'GHGIFmarginal'};
									};

									$per_sum += $house_elec_result->{$key}->{$period} / (1 - $en_srcs->{$src}->{'province'}->{$province}->{'trans_dist_loss'}) * $mult / 1000;
								};
								$house_result->{"use/$use/src/$src/GHG/integrated"} = $per_sum;
							};
							# Totalizes by end-use type
							$use_ghg->{$use} += $house_result->{"use/$use/src/$src/GHG/integrated"};
							$results_all->{'difference'}->{'parameter'}->{"use/$use/src/$src/GHG/integrated"} = 'kg';
						}

					};
					
					# Store the total site values
					$house_result->{"site/GHG/integrated"} = $site_ghg;
					$results_all->{'difference'}->{'parameter'}->{"site/GHG/integrated"} = 'kg';
					
					# Store the end-use totals
					foreach my $use (keys(%{$use_ghg})) {
						$house_result->{"use/$use/GHG/integrated"} = $use_ghg->{$use};
						$results_all->{'difference'}->{'parameter'}->{"use/$use/GHG/integrated"} = 'kg';
					};
				};
			};
		};
	};

# 	print Dumper $parameters;
	return(1);
};

#--------------------------------------------------------------------
# Subroutine to print out the Results
#--------------------------------------------------------------------
sub print_results_out_alt {
	my $results_all = shift;
	my $set_name = shift;

	# List the provinces in the preferred order
	my @hse_types = qw(SD DR);
	my @regions = qw(AT QC OT PR BC);
	my @provinces = qw(NF NS PE NB QC OT MB SK AB BC);
	my @uses = qw(space_heating space_cooling water_heating CHREM_AL);
	my @groups = qw(energy GHG quantity);
	my @srcs = qw(electricity natural_gas oil mixed_wood);
	my @periods = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	

	# If there is BAD HOUSE data then print it
	if (defined($results_all->{'bad_houses'})) {
		# Create a file to print out the bad houses
		my $filename = "../summary_files/Results$set_name" . '_Bad_alt.csv';
		open (my $FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");

		# Print the header information
		print $FILE CSVjoin(qw(*header hse_type region province hse_name issue)) . "\n";

		# Cycle over each region, ,province and house type to print the bad house issue
		foreach my $hse_type (@{&order($results_all->{'bad_houses'})}) {
			foreach my $region (@{&order($results_all->{'bad_houses'}->{$hse_type})}) {
				foreach my $province (@{&order($results_all->{'bad_houses'}->{$hse_type}->{$region}, [@provinces])}) {
				
					# Cycle over each house with results and print out the issue
					foreach my $hse_name (@{&order($results_all->{'bad_houses'}->{$hse_type}->{$region}->{$province})}) {
						print $FILE CSVjoin('*data', $hse_type, $region, $province, $hse_name, $results_all->{'bad_houses'}->{$hse_type}->{$region}->{$province}->{$hse_name}) . "\n";
					};
				};
			};
		};
		close $FILE; # The Bad house data file is complete
	};


	if (defined($results_all->{'sum'})) {

		# Create a file to print the total scaled provincial results to
		my $filename = "../summary_files/Results$set_name" . '_Total_alt.csv';
		open (my $FILE, '>', $filename) or die ("\n\nERROR: can't open $filename\n");


		my $SHEU03_houses = {}; # Declare a variable to store the total number of desired houses based on SHEU-1993

		# Fill out the number of desired houses for each province. These values are a combination of SHEU-2003 (being the baseline and providing the regional values) and CENSUS 2006 (to distribute the regional values by province)
		@{$SHEU03_houses->{'SD'}}{@provinces} = qw(148879 259392 38980 215084 1513497 2724438 305111 285601 790508 910051);
		@{$SHEU03_houses->{'DR'}}{@provinces} = qw(26098 38778 6014 23260 469193 707777 34609 29494 182745 203449);

		# Declare and fill out a set of unit conversions for totalizing
		my @unit_base = qw(GJ kg kWh l m3 tonne COP);
		my $unit_conv = {};
		@{$unit_conv->{'unit'}}{@unit_base} = qw(PJ Mt TWh Ml km3 Mt BOGUS);
		@{$unit_conv->{'mult'}}{@unit_base} = qw(1e-6 1e-9 1e-9 1e-6 1e-9 1e-6 0);
		@{$unit_conv->{'format'}}{@unit_base} = qw(%.1f %.2f %.1f %.1f %.3f %.2f %.0f);

		my @header = qw(*header hse_type region province multiplier use period);
		if (defined($results_all->{'units'})) {
			foreach my $group (@{&order($results_all->{'units'}, [@groups])}) {
				foreach my $src (@{&order($results_all->{'units'}->{$group}, [@srcs])}) {
					my $unit = $unit_conv->{'unit'}->{$results_all->{'units'}->{$group}->{$src}};
					push(@header, &capitalize_first_letter($src) . ' (' . $unit . ')');
				};
			};
		};

		print $FILE CSVjoin (@header) . "\n";

		# Cycle over each region, ,province and house type to store the results
		foreach my $hse_type (@{&order($results_all->{'sum'}, [@hse_types])}) {
			foreach my $region (@{&order($results_all->{'sum'}->{$hse_type}, [@regions])}) {
				foreach my $province (@{&order($results_all->{'sum'}->{$hse_type}->{$region}, [@provinces])}) {

					# To determine the multiplier for the house type for a province, we must first determine the total desirable houses
					my $total_houses;
					# If it is defined in SHEU then use the number (this is to account for test cases like 3-CB)
					if (defined($SHEU03_houses->{$hse_type}->{$province})) {$total_houses = $SHEU03_houses->{$hse_type}->{$province};}
					# Otherwise set it equal to the number of present houses so the multiplier is 1
					else {$total_houses = $results_all->{'count_houses'}->{$hse_type}->{$region}->{$province};};
					
					# Calculate the house multiplier and format
					my $multiplier = $total_houses / $results_all->{'count_houses'}->{$hse_type}->{$region}->{$province};
					my $multiplier_formatted = sprintf("%.1f", $multiplier);

					# Cycle over results and print out the results
					foreach my $use (@{&order($results_all->{'sum'}->{$hse_type}->{$region}->{$province}, [@uses])}) {
						foreach my $period (@{&order($results_all->{'sum'}->{$hse_type}->{$region}->{$province}->{$use}, [@periods])}) {

							my @data_line = ('*data', $hse_type, $region, $province, $multiplier_formatted, $use, $period);
							
							foreach my $group (@{&order($results_all->{'units'}, [@groups])}) {
								foreach my $src (@{&order($results_all->{'units'}->{$group}, [@srcs])}) {
									my $value = $results_all->{'sum'}->{$hse_type}->{$region}->{$province}->{$use}->{$period}->{$group}->{$src} * $multiplier * $unit_conv->{'mult'}->{$results_all->{'units'}->{$group}->{$src}};
									my $format = $unit_conv->{'format'}->{$results_all->{'units'}->{$group}->{$src}};
									push(@data_line, sprintf($format, $value));
								};
							};
							
							print $FILE CSVjoin(@data_line) . "\n";
						};
					};

				};
			};
		};



		close $FILE; # The national scaled totals are now complete

	};
	return();
};



# Final return value of one to indicate that the perl module is successful
1;
