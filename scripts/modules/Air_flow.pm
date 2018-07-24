# ====================================================================
# Air_flow.pm
# Author: Lukas Swan
# Date: Feb 2010
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# zone_zone_flow: creates the components and connections for fixed zone-zone advection and zone-zone leakage
# 
# afn_degrees: calculates the degrees that a side is facing (CCW from North)
# ====================================================================

# Declare the package name of this perl module
package Air_flow;

# Declare packages used by this perl module
use strict;
# use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;
use General;


# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(afn_node afn_component afn_connection zone_zone_flow amb_zone_flow afn_degrees);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# afn_node
# This fills out nodal information
# ====================================================================

sub afn_node {
	# Read in the information
	my $hse_file = shift; # Access information for file printout
	my $afn = shift; # AFN information storage
	my $name = shift; # Node name
	my $air_water = shift; # Air or water AFN node
	my $type = shift; # Node condition type
	my $height_m = shift; # Vertical height (m)
	my $temperature_C = shift; # Initialization temperature (C)
	my $data_1 = shift; # Data bits
	my $data_2 = shift; # Data bits
	my $coordinates = shift; # For error reporting

	# Key the air water to a number
	$air_water = {'air' => 1, 'water' => 2}->{$air_water} || &die_msg('Bad AFN air_water type', $air_water, $coordinates);
	
	# Key the condition type to a number
	$type = {'int_unk' => '0', 'bnd_wind_ind' => 3}->{$type};
	if ($type !~ /[0|3]/) {&die_msg('Bad AFN node condition type', $type, $coordinates);}

	# Insert a node
	&insert ($hse_file->{'afn'}, "#END_NODES", 1, 0, 0, "%s %u %u %.1f %.1f %u %.1f\n", $name, $air_water, $type, $height_m, $temperature_C, $data_1, $data_2);

	# Increment the node counter
	$afn->{'nodes'}++; 

	# Return true
	return(1);
};


# ====================================================================
# afn_component
# This fills out component information
# ====================================================================

sub afn_component {
	# Read in the information
	my $hse_file = shift; # Access information for file printout
	my $afn = shift; # AFN information storage
	my $name = shift; # Component name
	my $type = shift; # Component type
	my $data_1 = shift; # Data bits
	my $data_2 = shift; # Data bits
	my $data_3 = shift; # Data bits
	my $data_4 = shift; # Data bits
	my $coordinates = shift; # For error reporting

	# Provide a map of component numbers and descriptions
	my $comp_map = {'spec_open' => {'num' => 110, 'desc' => 'Specific opening area'}, 'const_mass_flow'  => {'num' => 35, 'desc' => 'Constant mass flow rate'}};

	# Determine the component number and description
	my $number = $comp_map->{$type}->{'num'} || &die_msg('Bad AFN component type - for num', $type, $coordinates);
	my $description = $comp_map->{$type}->{'desc'} || &die_msg('Bad AFN component type - for description', $type, $coordinates);

	# Insert component line 1
	&insert ($hse_file->{'afn'}, "#END_COMPONENTS", 1, 0, 0, "%s %u %u %u %s\n", $name, $number, $data_1, $data_2, $description);
	
	# Insert component line 2
	&insert ($hse_file->{'afn'}, "#END_COMPONENTS", 1, 0, 0, "%.1f %.5f\n", $data_3, $data_4);

	# Increment the component counter;
	$afn->{'components'}++; 

	# Return true
	return(1);
};


# ====================================================================
# afn_connection
# This fills out connection information
# ====================================================================

sub afn_connection {
	# Read in the information
	my $hse_file = shift; # Access information for file printout
	my $afn = shift; # AFN information storage
	my $node_1 = shift; # Node 1 name (Note that flow FROM Node 1 TO Node 2 will be considered positive)
	my $vert_1_m = shift; # Vertical height difference (m) FROM Node 1 TO the component
	my $node_2 = shift; # Node 2 name (Note that flow FROM Node 2 TO Node 1 will be considered positive)
	my $vert_2_m = shift; # Vertical height difference (m) FROM Node 2 TO the component
	my $component = shift; # Component name
	my $coordinates = shift; # For error reporting

	# Insert the connection
	&insert ($hse_file->{'afn'}, "#END_CONNECTIONS", 1, 0, 0, "%s %.1f %s %.1f %s\n", $node_1, $vert_1_m, $node_2, $vert_2_m, $component);

	# Increment the connection counter
	$afn->{'connections'}++;

	# Return true
	return(1);
};

# ====================================================================
# zone_zone_flow
# This fills out components and connections to facilitate zone-zone
# advection. This is accomplished with a fixed flowrate fan and a
# return opening.
# ====================================================================

sub zone_zone_flow {
	my $hse_file = shift; # Access information for file printout
	my $afn = shift; # AFN information storage
	my $zone_1 = shift; # The first zone name
	my $vert_1_m = shift; # Vertical hight difference (m) FROM Zone 1 TO component
	my $vol = shift; # Volume of Zone 1 to base the AC/h values
	my $zone_2 = shift; # The second zone name
	my $vert_2_m = shift; # Vertical hight difference (m) FROM Zone 2 TO component
	my $coordinates = shift; # For error reporting

	# Isolate the first and last letters of the zone name so that components names can be kept short (less than 12 digits)
	$zone_1 =~ /^(\w)\w*(\w)$/;
	my $zone_1_short = $1 . $2;
	$zone_2 =~ /^(\w)\w*(\w)$/;
	my $zone_2_short = $1 . $2;

	# Combine the short names with a dash
	my $zones_short = $zone_1_short . '-' . $zone_2_short;

	# Insert a constant mass flow rate fan component between the zones based on the zone_1 volume and an air exchange rate of 0.35 AC/h (converted to kg/s)
	$main::AfnCount++;
	&afn_component($hse_file, $afn, $zones_short . '_fan', 'const_mass_flow', 2, 0, 1, $vol * 0.35 / 3600 * 1.225, $coordinates);

	# Connect a fan in the forward direction from Zone 1 to Zone 2
	&afn_connection($hse_file, $afn, $zone_1, $vert_1_m, $zone_2, $vert_2_m, $zones_short . '_fan', $coordinates);

	# Connect a fan in the reverse direction from Zone 2 to Zone 1
	&afn_connection($hse_file, $afn, $zone_2, $vert_2_m, $zone_1, $vert_1_m, $zones_short . '_fan', $coordinates);

	# Insert an open area component (1 m^2) between the zones to facilitate stack effect flows
	# THE FOLLOWING IS COMMENTED BECAUSE OF THE AIM-2 AND AFN INTERATION. AIM-2 ONLY OVERRIDES INFILTRATION BUT THIS WILL AFFECT THE STACK ZONE-ZONE AIR FLOW
#	&afn_component($hse_file, $afn, $zones_short . '_open', 'spec_open', 2, 0, 1, 1, $coordinates);

	# Connect Zone 1 to Zone 2 opening
#	&afn_connection($hse_file, $afn, $zone_1, $vert_1_m, $zone_2, $vert_2_m, $zones_short . '_open', $coordinates);

	return(1);
};


# ====================================================================
# 
# ====================================================================
sub amb_zone_flow {
	my $hse_file = shift; # Access information for file printout
	my $afn = shift; # AFN information storage
	my $zone = shift; # The zone
	my $surface = shift; # The surface (front, right, back, left)
	my $opening = shift; # Opening type (window, vent, eave)
	my $area = shift; # Area of the opening
	my $height = shift; # Height of the opening
	my $vert_amb_comp = shift; # Vertical difference from ambient to the component (usually 0 m)
	my $vert_zone_comp = shift; # Vertical difference from zone to component
	my $AFN_degrees = shift; # The facing direction degrees (0 is N and then CW)
	my $coordinates = shift; # For error reporting

	# Shorten the side to the first and last letters because ESP-r naming only supports 12 digits
	$surface =~ /^(\w)\w*(\w)$/ or &die_msg('Bad AFN surface - two letter identification', $surface, $coordinates);
	my $sf = $1 . $2;
	
	# Determine the opening type
	my $open_type = {'window' => 'wd', 'vent' => 'vt', 'eave' => 'ev'}->{$opening} || &die_msg('Bad AFN opening type', $opening, $coordinates);

	# Insert a node for that side
	&afn_node($hse_file, $afn, $zone . '-' . $sf . '_' . $open_type, 'air', 'bnd_wind_ind', $height, 0, 18, $AFN_degrees, $coordinates);
	
	# Insert an opening
	$main::AfnCount++;
	if ($open_type =~ 'wd') {push @main::AfnCompInd, [ "$main::AfnCount",$zone,$zone . '-' . $sf . '_' . $open_type];}
	&afn_component($hse_file, $afn, $zone . '-' . $sf . '_' . $open_type, 'spec_open', 2, 0, 1, $area, $coordinates);
	
	# Connect the opening to the zone
	&afn_connection($hse_file, $afn, $zone . '-' . $sf . '_' . $open_type, $vert_amb_comp, $zone, $vert_zone_comp, $zone . '-' . $sf . '_' . $open_type, $coordinates);

	return(1);
};


# ====================================================================
# afn_degrees
# This determines the side's facing degrees for the AFN. The AFN uses
# north as the 0 degrees and proceeds clock-wise (CW) looking down.
# In comparison, the CSDDRD uses south as position 1 (of 8) and proceeds
# in a CCW direction.
# ====================================================================
sub afn_degrees {
	my $surface = shift; # Front, right, back, left
	my $CSDDRD_front_orientation = shift; # 1 - 8 going CCW from South
	my $coordinates = shift; # For error reporting

	# We have to examine the orientation (coded) and use this to convert to degrees (This is not trivial b/c of the 360 -> 0 degree feature)
	# Create an array corresponding the CSDDRD orientations (1 is South and then follows CCW)
	my @AFN_orientation = (1, 2, 3, 4, 5, 6, 7, 8);
	# The AFN operates from North and goes CW - so reverse the array (i.e. 8, 7, 6, 5, 4, 3, 2, 1)
	@AFN_orientation = reverse(@AFN_orientation);
	# We have to get the 1 into the 5th element - so shift and push 3 times (i.e. 5, 4, 3, 2, 1, 8, 7, 6)
	foreach (1..3) {push(@AFN_orientation,shift(@AFN_orientation));};
	# We may not be on the front side - so determine how many more shift/pushes we need (Note that sides are at right angles and we have 8 directions, so go 2 each side change)
	my $AFN_rotation = {'front' => 0, 'right' => 2, 'back' => 4, 'left' => 6}->{$surface};
	if ($AFN_rotation !~ /[0|2|4|6]/) {&die_msg('Bad AFN surface - determining rotation index', $surface, $coordinates);}
	# Now do the shift/push to account for the sides
	foreach (1..$AFN_rotation) {push(@AFN_orientation,shift(@AFN_orientation));};

	# Now look up the side in the new coordinate system and multiply by 45 degrees. This value will never exceed 325 degrees.
	# B/C the first array element is 0, subtract 1 from front_orientation, then subtract 1 prior to multiplication so that N is 0 degrees
	my $AFN_degrees = ($AFN_orientation[$CSDDRD_front_orientation - 1] - 1) * 45;

	return($AFN_degrees);
};

# Final return value of one to indicate that the perl module is successful
1;
