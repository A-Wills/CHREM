# ====================================================================
# BASESIMP.pm
# Author: Lukas Swan
# Date: May 2010
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# bsmt_basesimp_num: determine the basesimp number for a basement
# ====================================================================

# Declare the package name of this perl module
package BASESIMP;

# Declare packages used by this perl module
use strict;


# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(bsmt_basesimp_num);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# bsmt_basesimp_num
# This subroutine determines the basesimp number for a basement.
# It is a detailed routine because a different number is specified based on
# wall type, slab type, interior insul, exterior insul, slab insul
#
# ====================================================================

sub bsmt_basesimp_num {
	# cc = concrete
	# wd = wood
	my $type = shift; # basement type (1 = cc walls and slab; 2 = wd walls and cc slab; 3 = wd walls and slab)
	my $int = shift; # interior wall insulation (1 = none; 2 = full height; 3 = all but bottom 0.2 m; 4 = down to 0.6 m below grade)
	my $ext = shift; # exterior wall insulation (1 = none; 2 = full height; 3 = down to 0.6 m below grade; 4 = below grade)
	my $slab = shift; # slab insulation (1= none, 2 = top perimeter; 3 = top full; 4 = bottom perimeter; 5 = bottom full)

	foreach my $check ($int, $ext, $slab) {
		$check =~ s/^0$/1/;
	};

	my $basesimp_num;
	
	# The following checks on the bsmt type, and all insulation placements to determine the appropriate basesimp number.
	# The numbers were determined by the key BASESIMP_configuration.pdf, and from the ESP-r source code at:
	# src/esrubld/bscoeff.F and src/cetc/bscoeff_extended.F
	# Only coefficients that appear in the CSDDRD were included. If this is changed later then the database must be extended.

	if ($type == 1 && $int == 1 && $ext == 1 && $slab == 1 ) {$basesimp_num = 10;}
	elsif ($type == 1 && $int == 2 && $ext == 1 && $slab == 1 ) {$basesimp_num = 1;}
	elsif ($type == 1 && $int == 3 && $ext == 1 && $slab == 1 ) {$basesimp_num = 2;}
	elsif ($type == 1 && $int == 4 && $ext == 1 && $slab == 1 ) {$basesimp_num = 4;}
	elsif ($type == 1 && $int == 1 && $ext == 2 && $slab == 1 ) {$basesimp_num = 6;}
	elsif ($type == 1 && $int == 2 && $ext == 2 && $slab == 1 ) {$basesimp_num = 68;}
	elsif ($type == 1 && $int == 3 && $ext == 2 && $slab == 1 ) {$basesimp_num = 12;}
	elsif ($type == 1 && $int == 1 && $ext == 3 && $slab == 1 ) {$basesimp_num = 110;}
	elsif ($type == 1 && $int == 2 && $ext == 3 && $slab == 1 ) {$basesimp_num = 69;}
	elsif ($type == 1 && $int == 3 && $ext == 3 && $slab == 1 ) {$basesimp_num = 69;}
	elsif ($type == 1 && $int == 1 && $ext == 4 && $slab == 1 ) {$basesimp_num = 8;}
	elsif ($type == 1 && $int == 2 && $ext == 4 && $slab == 1 ) {$basesimp_num = 12;}
	elsif ($type == 1 && $int == 3 && $ext == 4 && $slab == 1 ) {$basesimp_num = 12;}
	elsif ($type == 1 && $int == 4 && $ext == 4 && $slab == 1 ) {$basesimp_num = 12;}
	elsif ($type == 1 && $int == 2 && $ext == 1 && $slab == 2 ) {$basesimp_num = 121;}
	elsif ($type == 1 && $int == 3 && $ext == 1 && $slab == 2 ) {$basesimp_num = 121;}
	elsif ($type == 1 && $int == 1 && $ext == 2 && $slab == 2 ) {$basesimp_num = 129;}
	elsif ($type == 1 && $int == 1 && $ext == 1 && $slab == 3 ) {$basesimp_num = 98;}
	elsif ($type == 1 && $int == 2 && $ext == 1 && $slab == 3 ) {$basesimp_num = 72;}
	elsif ($type == 1 && $int == 3 && $ext == 1 && $slab == 3 ) {$basesimp_num = 73;}
	elsif ($type == 1 && $int == 4 && $ext == 1 && $slab == 3 ) {$basesimp_num = 73;}
	elsif ($type == 1 && $int == 1 && $ext == 2 && $slab == 3 ) {$basesimp_num = 71;}
	elsif ($type == 1 && $int == 2 && $ext == 2 && $slab == 3 ) {$basesimp_num = 94;}
	elsif ($type == 1 && $int == 1 && $ext == 3 && $slab == 3 ) {$basesimp_num = 98;}
	elsif ($type == 1 && $int == 2 && $ext == 3 && $slab == 3 ) {$basesimp_num = 93;}
	elsif ($type == 1 && $int == 3 && $ext == 4 && $slab == 3 ) {$basesimp_num = 93;}
	elsif ($type == 1 && $int == 2 && $ext == 1 && $slab == 4 ) {$basesimp_num = 20;}
	elsif ($type == 1 && $int == 3 && $ext == 1 && $slab == 4 ) {$basesimp_num = 20;}
	elsif ($type == 1 && $int == 4 && $ext == 1 && $slab == 4 ) {$basesimp_num = 20;}
	elsif ($type == 1 && $int == 2 && $ext == 2 && $slab == 4 ) {$basesimp_num = 92;}
	elsif ($type == 1 && $int == 2 && $ext == 3 && $slab == 4 ) {$basesimp_num = 115;}
	elsif ($type == 1 && $int == 1 && $ext == 1 && $slab == 5 ) {$basesimp_num = 119;}
	elsif ($type == 1 && $int == 2 && $ext == 1 && $slab == 5 ) {$basesimp_num = 19;}
	elsif ($type == 1 && $int == 3 && $ext == 1 && $slab == 5 ) {$basesimp_num = 19;}
	elsif ($type == 1 && $int == 4 && $ext == 1 && $slab == 5 ) {$basesimp_num = 119;}
	elsif ($type == 1 && $int == 1 && $ext == 2 && $slab == 5 ) {$basesimp_num = 99;}
	elsif ($type == 1 && $int == 2 && $ext == 2 && $slab == 5 ) {$basesimp_num = 114;}
	elsif ($type == 1 && $int == 2 && $ext == 4 && $slab == 5 ) {$basesimp_num = 114;}
	elsif ($type == 2 && $int == 1 && $ext == 1 && $slab == 1 ) {$basesimp_num = 89;}
	elsif ($type == 2 && $int == 2 && $ext == 1 && $slab == 1 ) {$basesimp_num = 108;}
	elsif ($type == 2 && $int == 3 && $ext == 1 && $slab == 1 ) {$basesimp_num = 108;}
	elsif ($type == 2 && $int == 2 && $ext == 1 && $slab == 3 ) {$basesimp_num = 111;}
	elsif ($type == 2 && $int == 3 && $ext == 1 && $slab == 4 ) {$basesimp_num = 112;}
	elsif ($type == 2 && $int == 2 && $ext == 1 && $slab == 5 ) {$basesimp_num = 113;}
	elsif ($type == 3 && $int == 2 && $ext == 1 && $slab == 1 ) {$basesimp_num = 14;}
	elsif ($type == 3 && $int == 3 && $ext == 1 && $slab == 1 ) {$basesimp_num = 15;}
	elsif ($type == 3 && $int == 1 && $ext == 4 && $slab == 1 ) {$basesimp_num = 18;}
	elsif ($type == 3 && $int == 3 && $ext == 1 && $slab == 3 ) {$basesimp_num = 103;}
	elsif ($type == 3 && $int == 2 && $ext == 1 && $slab == 5 ) {$basesimp_num = 133;}
	elsif ($type == 1 && $int == 3 && $ext == 2 && $slab == 3 ) {$basesimp_num = 94;}
	
	else {$basesimp_num = 'bad'};

	# Pass the value back
	return ($basesimp_num);
};

# Final return value of one to indicate that the perl module is successful
1;
