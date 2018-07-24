# ====================================================================
# Control.pm
# Author: Lukas Swan
# Date: Nov 2009
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# basic_5_season: applies the basic controller with 5 season types to control heat/cool use
# slave: slave controller for zones that key off the central thermostat in basic_5_season
# free_float: a free floating controller
# ====================================================================

# Declare the package name of this perl module
package Control;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Data::Dumper;


# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(basic_5_season slave free_float CFC_control SDHW_control AFN_control);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# basic_5_season
# This fills out the basic control type with 5 season types
# to control the use of heating and cooling throughout the year
# ====================================================================

sub basic_5_season {
	my $zone_num = shift; # zone number
	my $heat_W = shift; # maximum heating system watts
	my $cool_W = shift; # maximum cooling system watts
	my $vol_ratio = shift; # volume ratio of the zone to all conditioned zones
    my $heat_T = shift; # Heating setpoint (deg C)
    my $cool_T = shift; # Cooling setpoint (deg C)
	
	# Apply the zone volume ratio to the heating and cooling capacities so they are for this zone only
	$heat_W = sprintf("%.0f", $heat_W * $vol_ratio);
	$cool_W = sprintf("%.0f", $cool_W * $vol_ratio);
	
	# Declare heating and cooling setpoints
    if((not defined $heat_T) || (not defined $cool_T)) {
        $heat_T = 21;
        $cool_T = 25;
    } else {
        $heat_T = sprintf("%.1f", $heat_T);
        $cool_T = sprintf("%.1f", $cool_T);
    };

	# Develop the control information lines in an array
	my @control = 
		('#',
		'#',
		"#CTL_TAG - THIS IS A MASTER OR DISTRIBUTED CONTROLLER FOR ZONE $zone_num",
		'* Control function',
		'#SENSOR_DATA four values - zero for in zone, first digit is zone num if sense in one zone only',
		"$zone_num 0 0 0",
		'#ACTUATOR_DATA three values - zero for in zone',
		"$zone_num 0 0",
		'#NUM_YEAR_PERIODS number of periods in year',
		'5 # To represent the seasonal use of the thermostat for heating and cooling',
		'#',
		'#VALID_DAYS day # to day #; THIS IS WINTER HEATING',
		'1 91',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (basic control), start @ hr',
		'0 1 0',
		'#NUM_DATA_ITEMS Number of data items',
		'7',
		'#DATA_LINE1 space seperated',
		"$heat_W 0 $cool_W 0 $heat_T 100 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?",
		'#',
		'#VALID_DAYS day # to day #; THIS IS SPRING WITH BOTH HEAT AND COOL',
		'92 154',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (basic control), start @ hr',
		'0 1 0',
		'#NUM_DATA_ITEMS Number of data items',
		'7',
		'#DATA_LINE1 space seperated',
		"$heat_W 0 $cool_W 0 $heat_T $cool_T 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?",
		'#',
		'#VALID_DAYS day # to day #; THIS IS SUMMER COOLING',
		'155 259',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (basic control), start @ hr',
		'0 1 0',
		'#NUM_DATA_ITEMS Number of data items',
		'7',
		'#DATA_LINE1 space seperated',
		"$heat_W 0 $cool_W 0 0 $cool_T 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?",
		'#',
		'#VALID_DAYS day # to day #; THIS IS FALL WITH BOTH HEAT AND COOL',
		'260 280',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (basic control), start @ hr',
		'0 1 0',
		'#NUM_DATA_ITEMS Number of data items',
		'7',
		'#DATA_LINE1 space seperated',
		"$heat_W 0 $cool_W 0 $heat_T $cool_T 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?",
		'#',
		'#VALID_DAYS day # to day #; THIS IS WINTER HEATING',
		'281 365',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (basic control), start @ hr',
		'0 1 0',
		'#NUM_DATA_ITEMS Number of data items',
		'7',
		'#DATA_LINE1 space seperated',
		"$heat_W 0 $cool_W 0 $heat_T 100 0 # heat_max_W heat_min_W cool_max_W cool_min_W heat_setpoint_C cool_setpoint_C relative_humidity?");
	
	# Declare a string to store the concatenated control lines
	my $string = '';
	
	# Cycle over the array and concatenate the lines with an end of line character
	foreach my $line (@control) {
		$string = $string . $line . "\n";
	};
	
	# Return the string
	return ($string);
};


# ====================================================================
# slave
# This fills out the slave control type which relies on links to the 
# master zone for the sensor and the master controller for on/off
# ====================================================================

sub slave {
	my $zone_num = shift; # zone number
	my $heat_W = shift; # maximum heating system watts
	my $cool_W = shift; # maximum cooling system watts
	my $vol_ratio = shift; # volume ratio of the zone to all conditioned zones
	my $master_num = shift; # the master zone controller number which is equal to the main_1 zone number
	
	# Apply the zone volume ratio to the heating and cooling capacities so they are for this zone only
	$heat_W = sprintf("%.0f", $heat_W * $vol_ratio);
	$cool_W = sprintf("%.0f", $cool_W * $vol_ratio);
	
	# Develop the control information lines in an array
	my @control = 
		('#',
		'#',
		"#CTL_TAG - THIS IS THE SLAVE CONTROLLER FOR ZONE NUMBER $zone_num",
		'* Control function',
		'#SENSOR_DATA four values - master controller zone number followed by zeroes',
		"$master_num 0 0 0",
		'#ACTUATOR_DATA three values - actuator zone number followed by zeroes',
		"$zone_num 0 0",
		'#NUM_YEAR_PERIODS number of periods in year',
		'1',
		'#',
		'#VALID_DAYS day # to day #',
		'1 365',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (SLAVE), start @ hr',
		'0 21 0',
		'#NUM_DATA_ITEMS Number of data items',
		'3',
		'#DATA_LINE1 space seperated: master controller number, heat capacity (W), cool capacity (W)',
		"$master_num $heat_W $cool_W");

	# Declare a string to store the concatenated control lines
	my $string = '';
	
	# Cycle over the array and concatenate the lines with an end of line character
	foreach my $line (@control) {
		$string = $string . $line . "\n";
	};
	
	# Return the string
	return ($string);
};



sub free_float {

	# Construct an array of the required control lines
	my @control =
		('#',
		'#',
		'#CTL_TAG - THIS IS A FREE-FLOAT CONTROLLER',
		'* Control function',
		'#SENSOR_DATA four values - zero for in present zone followed by zeroes',
		'0 0 0 0',
		'#ACTUATOR_DATA three values - zero for in present zone followed by zeroes',
		'0 0 0',
		'#NUM_YEAR_PERIODS number of periods in year',
		'1',
		'#',
		'#VALID_DAYS day # to day #',
		'1 365',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, law (FREE FLOATING), start @ hr',
		'0 2 0',
		'#NUM_DATA_ITEMS Number of data items',
		'0');

	# Declare a string to store the concatenated control lines
	my $string = '';
	
	# Cycle over the array and concatenate the lines with an end of line character
	foreach my $line (@control) {
		$string = $string . $line . "\n";
	};
	
	# Return the string
	return ($string);
};
# ====================================================================
# CFC_control
# This fills out the venetian blind control with 5 season types
# to control the shading through winter and summer - we need more than one control
# there are 3 period in day
# ====================================================================

sub CFC_control {
	my $zone_num = shift; # zone number
	my $surface = shift;
	my $surface_num = shift;
	my $cfc_type = shift;
	my $sensor_value1 = shift; # sensing condition
	my $actuator_value1 = shift; # actuator mode
	my $ctl_type = 0;
 
	my $sensor_value2;
	my $sensor_value3;
	my $sensor_comment;
	my $actuator_comment;
	my $actuator_value2 = $zone_num;
	my $actuator_value3 = $cfc_type;
	my $ctl_law;
	my $data_num;
	my $data_1;
	my $data_2;
	my $data_3;
	my $data_4;
	my $shade_on_sol = 233; # (W/m2), shade closed, Based on paper "MANUAL VS. OPTIMAL CONTROL OF EXTERIOR AND INTERIOR BLIND SYSTEMS" by Deuk-Woo Kim, and Cheol-Soo Park
	my $shade_off_sol = 200; # (W/m2), shade open
	my $shade_on_temp = 24;
	my $shade_off_temp = 21;
	my $slat_angle_on = 89;
	my $slat_angle_off = 0;

	if ($sensor_value1 == -4) {
		$sensor_comment = "senses incident solar rad on $surface in zone $zone_num";
		$sensor_value2 = $zone_num;
		$sensor_value3 = $surface_num;
	}
	elsif ($sensor_value1 == 0) {
		$sensor_comment = 'no sensor - schedule only';
		$sensor_value2 = 0;
		$sensor_value3 = 0;
	}
	else {
		$sensor_comment = "senses dry bulb temperature in zone $zone_num";
		$sensor_value1 = "$zone_num";
		$sensor_value2 = 0;
		$sensor_value3 = 0;
	}
	
	if ($actuator_value1 == 0) {
		$actuator_comment = "# actuates Shading ON/OFF in CFC type $cfc_type in zone $zone_num";
		$data_num = 2;
	}
	elsif ($actuator_value1 == 1) {
		$actuator_comment = "# actuates Slat angle in CFC type $cfc_type in zone $zone_num";
		$data_num = 4;
	}
	else {
		$actuator_comment = "# actuates Shade ON/OFF and slat angle(schedule) $cfc_type in zone $zone_num";
		$data_num = 2;
	}
	
	# check the compatibility between sensor and actuator and assign the ctl_type
	if ($sensor_value1 == -4) { # senses solar_rad
		if ($actuator_value1 == 0) {# actuate shading on/off
			$ctl_type = 3;
		}	
		elsif ($actuator_value1  == 1) {# actuate slat angle
			$ctl_type  = 4;
		}
		else { # schedule (can't be used in this case)
			die "check sensor data!\n";
		}
	}
	elsif ($sensor_value1 == 0) {# schedule mode
		if ($actuator_value1 == 2) {# actuate both shading on/off and slat/angle
			$ctl_type = 7;
		}
		else {
			die "check sensor or actuator data! \n";
		}
	}
	else { #sense temperature
		if ($actuator_value1 == 0) {# actuate shading on/off
			$ctl_type = 1;
		}	
		elsif ($actuator_value1  == 1) {# actuate slat angle
			$ctl_type  = 2;
		}
		else { # schedule (can't be used in this case)
			die "check sensor data!\n";
		}
	}
	
	my $law;
	if ($ctl_type == 7) {
		$ctl_law = 2; #schedule
		$law = 'schedule';
	}
	else {
		$ctl_law = 1; #basic control
		$law = 'basic control';
	}
	
	if ($sensor_value1 == -4) {
		if  ($actuator_value1 == 0) {
			$data_1 = $shade_on_sol;
			$data_2 = $shade_off_sol;
		}
		elsif ($actuator_value1 == 1) {
			$data_1 = $shade_on_sol;
			$data_2 = $shade_off_sol;
			$data_3 = $slat_angle_on;
			$data_4 = $slat_angle_off;
		}
	}
	else {
		if  ($actuator_value1 == 0) {
			$data_1 = $shade_on_temp;
			$data_2 = $shade_off_temp;
		}
		elsif ($actuator_value1 == 1) {
			$data_1 = $shade_on_temp;
			$data_2 = $shade_off_temp;
			$data_3 = $slat_angle_on;
			$data_4 = $slat_angle_off;
		}
	}
	
	
	my @control;
	if ($actuator_value1 == 0) {  
		@control = 
			('#',
			'* Control function',
			"# $sensor_comment",
			"$sensor_value1 $sensor_value2 $sensor_value3 0 # sensor data",
			"$actuator_comment",
			"$actuator_value1 $actuator_value2 $actuator_value3 # actuator data",
			'5 # No. day types',
			'1 91 # winter time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'7 2 7.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'0 0.000',
			'7 2 18.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'92 154 # spring time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			"$ctl_type $ctl_law 7.000 # ctl type, law ($law), start @",
			"$data_num # No. of data items",
			"$data_1 $data_2",
			'7 2 19.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'155 259 # summer time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			"$ctl_type $ctl_law 6.000 # ctl type, law ($law), start @",
			"$data_num # No. of data items",
			"$data_1 $data_2",
			'7 2 20.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'260 280 # fall time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			"$ctl_type $ctl_law 7.000 # ctl type, law ($law), start @",
			"$data_num # No. of data items",
			"$data_1 $data_2",
			'7 2 19.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'281 365 # winter time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'7 2 7.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'0 0.000',
			'7 2 18.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000');
	}
	elsif ($actuator_value1 == 1) {
		@control = 
			('#',
			'* Control function',
			"# $sensor_comment",
			"$sensor_value1 $sensor_value2 $sensor_value3 0 # sensor data",
			"$actuator_comment",
			"$actuator_value1 $actuator_value2 $actuator_value3 # actuator data",
			'5 # No. day types',
			'1 91 # winter time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'7 2 7.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'0 0.000',
			'7 2 18.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'92 154 # spring time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			"$ctl_type $ctl_law 7.000 # ctl type, law ($law), start @",
			"$data_num # No. of data items",
			"$data_1 $data_2 $data_3 $data_4",
			'7 2 19.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'155 259 # summer time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			"$ctl_type $ctl_law 6.000 # ctl type, law ($law), start @",
			"$data_num # No. of data items",
			"$data_1 $data_2 $data_3 $data_4",
			'7 2 20.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'260 280 # fall time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			"$ctl_type $ctl_law 7.000 # ctl type, law ($law), start @",
			"$data_num # No. of data items",
			"$data_1 $data_2 $data_3 $data_4",
			'7 2 19.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'#',
			'281 365 # winter time',
			'3 # No. of periods in day',
			'7 2 0.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000',
			'7 2 7.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'0 0.000',
			'7 2 18.000 # ctl type, law (schedule), start @',
			'2 # No. of data items',
			'1 89.000');
	}
	# Declare a string to store the concatenated control lines
	my $string = '';
	
	# Cycle over the array and concatenate the lines with an end of line character
	foreach my $line (@control) {
		$string = $string . $line . "\n";
	};
	
	# Return the string
	return ($string);
};

# ====================================================================
# SDHW_control
# This fills out the SDHW control with 1 season types
# ====================================================================

sub SDHW_control {
	my $sys_type = shift; # SDHW system type
	my $fuel = shift; # fuel source for auxiliary tank
	my $mult = shift; # dhw multiplier
	my $pump_stat = shift; # collector pump status on or off
	$mult = sprintf("%.2f", $mult);
	my $node_dhw;
	my $node_solar;
	my $dhw_tank;
	unless ($fuel == 2) { #in case of electricity or oil we use electricity tank which will be actuated by their first node
		$node_dhw =1;
		$dhw_tank = 'electric_tank';
	}
	else  { #in case of NG tank which will be actuated by its second node
		$node_dhw =2;
		$dhw_tank = 'fuel_tank';
	}
	if ($sys_type == 3) { 
		$node_solar = 1;
	}
	elsif ($sys_type == 4) { 
		$node_solar = 2;
	}
	my $pump_flow;
	
	if ($pump_stat =~ /NO|N/i) {
		$pump_flow = sprintf ("%.5f",0);
		
	}
	else {
		$pump_flow = sprintf ("%.5f",0.00002);
		
	}
	my @control;
	if ($sys_type =~ /2/) {
		@control = 
			('#', 
			'* Control loops 1',
			'# sen var diff bet compt. 1:solar_collector @ node 1and compt 3:storage_tank @ node 1',
			'-1 1 1 3 1 # sensor',
			'# plant component 2:collector_pump @ node no. 1',
			'-1 2 1 0 # actuator',
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'24 8 0.000 #ctl type, law (On-Off control.), start @',
			'7. # No. of data items',
			"1.00000 1.00000 5.00000 0.00000 $pump_flow 0.00000 0.00000",
			'* Control loops 2',
			'# sen var diff bet compt. 1:solar_collector @ node 1and compt 3:storage_tank @ node 1',
			'-1 1 1 3 1 # sensor',
			'# plant component 6:tank_pump @ node no. 1',
			'-1 6 1 0 # actuator',
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'24 8 0.000 #ctl type, law (On-Off control.), start @',
			'7. # No. of data items',
			"1.00000 1.00000 5.00000 0.00000 $pump_flow 0.00000 0.00000",
			'* Control loops 3',
			"# senses var in compt. 4:$dhw_tank @ node no. 1",
			'-1 4 1 0 0 # sensor', 
			"# plant component 4:$dhw_tank @ node no. $node_dhw",
			"-1 4 $node_dhw 0 # actuator",
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'12 8 0.000 #ctl type, law (On-Off control.), start @',
			'7. # No. of data items',
			'1.00000 54.00000 57.00000 1.00000 0.00000 0.00000 0.00000',
			'* Control loops 4',
			'# measures dummy sensor in compt. 9:water_flow @ node no. 1',
			'-1 9 1 0 0 # sensor',
			'# plant component 9:water_flow @ node no. 2',
			'-1 9 2 0 # actuator',
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'0 12 0.000 #ctl type, law (Boundary condition control), start @',
			'3. # No. of data items',
			"1.00000 1.00000 $mult");
	}
	else {
		@control = 
			('#', 
			'* Control loops 1',
			"# sen var diff bet compt. 1:solar_collector @ node 1and compt 3:solar_tank @ node $node_solar",
			"-1 1 1 3 $node_solar # sensor",
			'# plant component 2:collector_pump @ node no. 1',
			'-1 2 1 0 # actuator',
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'24 8 0.000 #ctl type, law (On-Off control.), start @',
			'7. # No. of data items',
			"1.00000 1.00000 5.00000 0.00000 $pump_flow 0.00000 0.00000",
			'* Control loops 2',
			"# senses var in compt. 4:$dhw_tank @ node no. 1",
			'-1 4 1 0 0 # sensor', 
			"# plant component 4:$dhw_tank @ node no. $node_dhw",
			"-1 4 $node_dhw 0 # actuator",
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'12 8 0.000 #ctl type, law (On-Off control.), start @',
			'7. # No. of data items',
			'1.00000 54.00000 57.00000 1.00000 0.00000 0.00000 0.00000',
			'* Control loops 3',
			'# measures dummy sensor in compt. 6:water_flow @ node no. 1',
			'-1 6 1 0 0 # sensor',
			'# plant component 9:water_flow @ node no. 2',
			'-1 6 2 0 # actuator',
			'1 # all daytypes',
			'1 365 # valid Mon-01-Jan - Mon-31-Dec',
			'1 # No. of periods in day: weekdays',
			'0 12 0.000 #ctl type, law (Boundary condition control), start @',
			'3. # No. of data items',
			"1.00000 1.00000 $mult");
	}
	
	
	# Declare a string to store the concatenated control lines
	my $string = '';
	
	# Cycle over the array and concatenate the lines with an end of line character
	foreach my $line (@control) {
		$string = $string . $line . "\n";
	};
	# Return the string
	return ($string);
};

# ====================================================================
# AFN_control
# This fills out the AFN Window Controller
# ====================================================================

sub AFN_control {
	my $index = shift; # Window facing
	my $zoneNum = shift; # Zone Number
	
	my $Comp_num = $main::AfnCompInd[$index][0];   # AFN component number
    my $Zonal = "$main::AfnCompInd[$index][1]";      # Name of zone connected to component
	my $Comp_name = "$main::AfnCompInd[$index][2]";  # Name of component/boundary node
	
	# Prepare strings for input to control function
	my $FuncLine= sprintf("* Control mass    %d", $index+1);
	my $actuate = sprintf("-4  %d  1", $Comp_num);

#	# Construct an array of the required control lines
#	# This is a multi-sensor controller set to open the windows 
#	# IF main_1 > 25 oC .AND. outside > 21 oC
	my @control =
		('#',
		'#AFN_TAG - THIS IS A MULTI-SENSOR CONTROLLER',
		$FuncLine,
		"# senses dry bulb temperature in main_1",
		"1 0 0 0",
		"# actuates flow component: $Comp_name",
		$actuate,
		'#NUM_YEAR_PERIODS number of periods in year',
		'1',
		'#',
		'#VALID_DAYS day # to day #',
		'1 365',
		'#NUM_DAY_PERIODS',
		'1',
		'#CTL_TYPE ctl type, (dry bulb > flow), law (AIM-2 Window Control Port), starting @',
		'1 7 0',
		'#NUM_DATA_ITEMS Number of data items',
		'5.',
		'#AFN_CTL_INPUTS, cooling_sensor_zone (zone for central cooling check) hot_setpoint (above this zone temp windows can operate) cold_setpoint(below this zone temp the windows are closed) DeltaT (if zone - ambient > deltaT windows can operate) minimum_ambient_temp (the minimum ambient temp which allows windows to open so as to prevent very cold air)',
		'  1.0000 25.0000 21.0000 1.0000 21.0000',
		"$Comp_name   $Zonal    $Comp_name");

	# Declare a string to store the concatenated control lines
	my $string = '';
	
	# Cycle over the array and concatenate the lines with an end of line character
	foreach my $line (@control) {
		$string = $string . $line . "\n";
	};
	
	# Return the string
	return ($string);
};

# Final return value of one to indicate that the perl module is successful
1;
