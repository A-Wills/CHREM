# ====================================================================
# Zoning.pm
# Author: Lukas Swan
# Date: Jan 2010
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# lower_and_upper_zone: record the zone name and number of zones above and zones below
# ====================================================================

# Declare the package name of this perl module
package Zoning;

# Declare packages used by this perl module
use strict;


# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(lower_and_upper_zone);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# lower_and_upper_zone
# This subroutine determines and assigns the name/num of the zone above/below
# These values are used when creating zones or surfaces to determine if or what
# they face.
#
# ====================================================================

sub lower_and_upper_zone {
	my $zones = shift; # the exiting zoning information
	my $lower_zone_name = shift;
	my $upper_zone_name = shift;
	
	# Record the names and numbers of the zones above/below
	$zones->{$lower_zone_name}->{'above_num'} = $zones->{'name->num'}->{$upper_zone_name}; # record zone number of level above
	$zones->{$lower_zone_name}->{'above_name'} = $upper_zone_name; # record zone name of level above
	$zones->{$upper_zone_name}->{'below_num'} = $zones->{'name->num'}->{$lower_zone_name}; # record zone number of level below
	$zones->{$upper_zone_name}->{'below_name'} = $lower_zone_name; # record zone name of level below

	return ($zones);
};

# Final return value of one to indicate that the perl module is successful
1;
