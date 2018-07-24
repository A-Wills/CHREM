# ====================================================================
# Archetypes.pm
# Author: Adam Wills
# Date: Nov 2017
# NRC-CNRC Construction
# ====================================================================
# The following subroutines are included in the perl module:
# getClimateZone: Returns the climate zone for the city
# 
# afn_degrees: calculates the degrees that a side is facing (CCW from North)
# ====================================================================

# Declare the package name of this perl module
package Archetypes;

# Declare packages used by this perl module
use strict;
# use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;
use General;


# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(getClimateZone);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# getClimateZone
# Determines the climate zone for the Canadian city
# ====================================================================

sub getClimateZone {
	# Inputs
	my $iHDD_18C = shift; # Heating degree days (Base 18 degC)
    
    # Outputs
    my $sClimZone;

    if(($iHDD_18C<3000) && ($iHDD_18C>0)) {
        $sClimZone='Zone_4';
    } elsif($iHDD_18C<3999) {
        $sClimZone='Zone_5';
    } elsif($iHDD_18C<4999) {
        $sClimZone='Zone_6';
    } elsif($iHDD_18C<5999) {
        $sClimZone='Zone_7A';
    } elsif($iHDD_18C<6999) {
        $sClimZone='Zone_7B';
    } elsif($iHDD_18C>=7000) {
        $sClimZone='Zone_8';
    };
	

	# Return true
	return($sClimZone);
};


# Final return value of one to indicate that the perl module is successful
1;
