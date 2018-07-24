# ====================================================================
# AL_Profile_Gen.pm
# Author: Adam Wills
# Date: June 2015
# Copyright: Carleton University
# ====================================================================
# The following subroutines are included in the perl module:
# setDryerProfile: Sets the annual dryer electrical usage
# setColdProfile: Sets the annual electrical usage profile for fridge=1, or freezer=2
# ====================================================================

# Declare the package name of this perl module
package AL_Profile_Gen;

# Declare packages used by this perl module
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Cwd;
use Data::Dumper;
use POSIX qw(ceil floor);
use Switch;

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(setStartState OccupancySimulation LightingSimulation GetIrradiance GetUEC setColdProfile ActiveStatParser GetApplianceStock GetApplianceProfile IncreaseTimestepPower rand_range GetMonteCarloNormalDistGuess UpdateBCD GetDHWData StretchProfile FindAnnualALandDHW GetStoveAppliances SetApplianceProfile);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# setStartState
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
#
# REFERENCES: - Richardson, Thomson, Infield, Clifford "Domestic Energy Use:
#               A high-resolution energy demand model". Energy and Buildings, 
#               42, 2010.
#             
# ====================================================================

sub setStartState {
	# Read in inputs
    my ($numOcc, $pdf) = @_;
    
    # Local variables
    my $fRand = rand();
    my $fCumulativeP = 0;
    my $StartActive;
    my @ky = qw(zero one two three four five six);
    
    SET_IT: for (my $i = 0; $i<=6 && exists $pdf->{"$ky[$i]"}; $i++) {
        $fCumulativeP = $fCumulativeP + $pdf->{"$ky[$i]"};
        if ($fRand < $fCumulativeP) {
            $StartActive = $i;
            last SET_IT;
        };
    }; 
    if (!defined $StartActive) {$StartActive = 0};
    
    return ($StartActive);
};

# ====================================================================
# OccupancySimulation
#       This subroutine generates the annual occupancy profile at a 1 
#       minute timestep.
#
# INPUT     numOcc: number of occupants in the house
#           initial: initial number of active occupants for the set
#           dayWeek: initial day of the week [1=Sun, 7=Sat]
# OUTPUT    StartActive: number of active occupants 
#
# REFERENCES: - Richardson, Thomson, Infield, Clifford "Domestic Energy Use:
#               A high-resolution energy demand model". Energy and Buildings, 
#               42, 2010.
#             
# ====================================================================

sub OccupancySimulation {
	# Read in inputs
    my ($numOcc, $initial, $dayWeek, $dir) = @_;
    
    # Local variables
    my @Occ = ($initial) x 10; # Array holding number of active occupants in dwelling per minute
    my $bStart=1;
    if (not defined $dir) {$dir = getcwd};
    
    # Check to see if occupancy exceeds model limits
    if ($numOcc>5) { # Reduce the number of occupants to 5
        $numOcc=5;
        # TODO: WARN THE USER
    };
    
    # Load both transition matrices
    my @TRmatWD=(); # Array to hold weekday transition matrix
    my @TRmatWE=(); # Array to hold weekend transition matrix
    
    my $WDfile = $dir . "/Occ_Lighting/tpm" . "$numOcc" . "_wd.csv";
    open my $fh, '<', $WDfile or die "Cannot open $WDfile: $!";
    while (my $dat = <$fh>) {
        chomp $dat;
        push(@TRmatWD,$dat);
    };
    @TRmatWD = @TRmatWD[ 1 .. $#TRmatWD ]; # Trim out header
    close $fh;
    
    my $WEfile = $dir . "/Occ_Lighting/tpm" . "$numOcc" . "_we.csv";
    open my $fhdl, '<', $WEfile or die "Cannot open $WEfile: $!";
    while (my $dat = <$fhdl>) {
        chomp $dat;
        push(@TRmatWE,$dat);
    };
    @TRmatWE = @TRmatWE[ 1 .. $#TRmatWE ]; # Trim out header
    close $fhdl;
    
    YEAR: for (my $i=1; $i<=365; $i++) { # for each day of the year
        # Determine which transition matrix to use
        my $tDay; 
        my @TRmat;
        if ($dayWeek>7){$dayWeek=1};
        if ($dayWeek == 1 || $dayWeek == 7) {
            @TRmat = @TRmatWE;
        } else { 
            @TRmat = @TRmatWD;
        };

        if ($bStart) { # first call, first 10 minutes don't matter
            @TRmat = @TRmat[ 7 .. $#TRmat ];
            $bStart=0;
        };
        DAY: for (my $j=0; $j<=$#TRmat; $j=$j+7) { # Cycle through each period in the matrix
            my $current = $Occ[$#Occ]; # Current occupancy
            # Find the appropriate distribution data
            my $k=$j+$current;
            my $dist = $TRmat[$k];
            chomp $dist;
            my @data = split /,/, $dist;
            @data = @data[ 2 .. $#data ]; # Trim out the index values
            my $fCumulativeP=0; # Cumulative probability for period
            my $fRand = rand();
            my $future=0; # future occupancy
            TEN: while ($future < $numOcc) {
                $fCumulativeP=$fCumulativeP+$data[$future];
                if ($fRand < $fCumulativeP) {
                    last TEN;
                };
                $future++;
            }; # END TEN
            
            # Update the Occupancy array
            for (my $m=0; $m<10; $m++) { # This will be the occupancy for the next ten minutes
                push(@Occ,$future);
            };
        }; # END DAY
        $dayWeek++;
    }; # END YEAR 

    return (\@Occ);
};

# ====================================================================
# LightingSimulation
#       This subroutine generates the annual occupancy profile at a 1 
#       minute timestep.
#
# INPUT     ref_Occ: Annual dwelling occupancy at 1 min timestep
#           climate: EPW weather file for house
#           fBulbs: Array holding wattage for each lamp [W]
#           fCalibrationScalar: Calibration scalar for lighting model
#           MeanThresh: Mean threshold for light ON [W/m2]
#           STDThresh: Std. dev for light ON [W/m2]
# OUTPUT    Light: Annual lighting power at 1 min timestep [kW]
#           AnnPow: Annual power consumption of dwelling for lighting [kWh]
#
# REFERENCES: - Richardson, Thomson, Infield, Delahunty "Domestic Lighting:
#               A high-resolution energy demand model". Energy and Buildings, 
#               41, 2009.
# ====================================================================

sub LightingSimulation {
    # Read in inputs
    my ($ref_Occ, $Irr_ref, $fBulbs_ref, $fCalibrationScalar,$MeanThresh,$STDThresh) = @_;
    my @Occ = @$ref_Occ;
    my @Irr = @$Irr_ref;
    my @fBulbs = @$fBulbs_ref;
    
    if ($#Occ != $#Irr) {die "Number of occupancy and irradiance timesteps do not match"};
    
    # Set local variables
    my $Tsteps = scalar @Occ;
    my $SMALL = 1.0e-20;
    
    # Declare output
    my @Light=(0) x $Tsteps;
    my $AnnPow=0;

    # Determine the irradiance threshold of this house
    my $iIrradianceThreshold = GetMonteCarloNormalDistGuess($MeanThresh,$STDThresh);

    # Assign weightings to each bulb
    BULB: for (my $i=0;$i<=$#fBulbs;$i++) { # For each dwelling bulb
        # Determine this bulb's relative usage weighting
        my $fRand = rand();
        if ($fRand < $SMALL) {$fRand = $SMALL}; # Avoid domain errors
        my $fCalibRelUseW = -1*$fCalibrationScalar*log($fRand);

        # Calculate this bulb's usage for each timestep
        my $iTime=0;
        TIME: while ($iTime<=$#Occ) {
            # Is this bulb switched on to start with?
            # This concept is not implemented in this example.
            # The simplified assumption is that all bulbs are off to start with.
            
            # First determine if there are any occupants active for a switch-on event
            if ($Occ[$iTime]==0) { # No occupants, jump to next period
                $iTime++;
                next TIME;
            };
            # Determine if the bulb switch-on condition is passed
            # ie. Insuffient irradiance and at least one active occupant
            # There is a 5% chance of switch on event if the irradiance is above the threshold
            my $bLowIrradiance;
            if (($Irr[$iTime] < $iIrradianceThreshold) || (rand() < 0.05)) {
                $bLowIrradiance = 1;
            } else {
                $bLowIrradiance = 0;
            };
            
            # Get the effective occupancy for this number of active occupants to allow for sharing
            my $fEffectiveOccupancy = GetEffectiveOccupancy($Occ[$iTime]);

            # Check the probability of a switch on at this time
            if ($bLowIrradiance && (rand() < ($fEffectiveOccupancy*$fCalibRelUseW))) { # This is a switch on event
                # Determine how long this bulb is on for
                my $iLightDuration = GetLightDuration();
                
                DURATION: for (my $j=1;$j<=$iLightDuration;$j++) {
                    # Range Check
                    if ($iTime > $#Occ) {last TIME};
                    
                    # If there are no active occupants, turn off the light and increment the time
                    if ($Occ[$iTime] <=0) {
                        $iTime++;
                        next TIME;
                    };
                    
                    # Store the demand
                    $Light[$iTime] = $Light[$iTime]+($fBulbs[$i]/1000); # [kW]
                    
                    # Increment the time
                    $iTime++;
                }; # END DURATION
                
            } else { # The bulb remains off
                $iTime++;
            };
        }; # END TIME 
    }; # END BULB
    
    # Integrate bulb usage to find annual consumption, and scale to kW
    for (my $k=0; $k<=$#Light; $k++) {
        $AnnPow=$AnnPow+($Light[$k]*60); # [kJ]
    };
    
    # Express annual consumption in kWh
    $AnnPow=$AnnPow/3600;

    return(\@Light, $AnnPow);
};

# ====================================================================
# GetIrradiance
#       This subroutine loads the irradiance data and returns it 
#
# INPUT     file: path and file name of input
# OUTPUT    Irr: Array holding the irradiance data [W/m2]
#
# ====================================================================

sub GetIrradiance {
    # Read in inputs
    my ($file) = @_;
    
    # Declare output
    my @Irr=();
    
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my $i=0;
    RAD: while (my $dat = <$fh>) {
            if ($i<2) { # Header data, skip
                $i++;
                next RAD;
            };
            chomp $dat;
            my @temp = split /\t/, $dat,2;
            $temp[1] = sprintf("%.10g", $temp[1]);
            push(@Irr, $temp[1]); 
    }; # END RAD
    close $fh;
    
    pop(@Irr); # Trim out last timestep

    return(\@Irr);
};

# ====================================================================
# GetUEC
#   This subroutine determines the UEC of cold appliances of specified
#   type, vintage, and size. Fridge data is read directly from the HASH.
#   Freezers are not sorted by size but type. The type is randomly selected
#   from the distribution, and the associated UEC is selected.
#
#   INPUTS:     type: Type of cold appliance (Refrigerator or Freezer)
#               vintage: Year of fridge manufacture
#               size: Size of the cold appliance [cu. ft.]
#               ColdHash: Hash holding the efficiency data
#   OUTPUTS     UEC: Unit energy consumption [kWh/yr]
#           cType: String indicating appliance type (Refrigerator Upright_Freezer Chest_Freezer)
# ====================================================================
sub GetUEC {
    # Read in the inputs
    my $type = shift;
    my $vintage = shift;
    my $size = shift;
    my $ColdHash = shift;
    
    # Declare the outputs
    my $UEC;
    my $cType;
    
    # Determine the type of cold appliance
    if ($type =~ m/Refrigerator/) { # Fridge
        my $sizeInd = $ColdHash->{'Sizes'}->{'intervals'};
        if ($size > $ColdHash->{'Sizes'}->{"_$sizeInd"}->{'max'}) {
            $size = $ColdHash->{'Sizes'}->{"_$sizeInd"}->{'max'};
        };
        my $i = 1;
        while ($ColdHash->{'Sizes'}->{"_$i"}->{'max'} < $size) { # Find consumption data for appliance size
            $i++;
        };
        
        $UEC = $ColdHash->{'Eff'}->{"_$vintage"}->{"_$i"};
        $cType = 'Refrigerator';
        
    } elsif ($type =~ m/Freezer/) { # Freezer
        # Select a freezer type using distribution for particular vintage
        my $U = rand(100);
        my $j=0;
        my $fType;
        
        foreach my $Ind (keys (%{$ColdHash->{'types'}->{"_$vintage"}})) {
            $j=$j+$ColdHash->{'types'}->{"_$vintage"}->{"_$Ind"};
            if ($j > $U) {
                $fType = $Ind;
                last;
            };
        };
        
        $UEC = $ColdHash->{'Eff'}->{"_$vintage"}->{"_$fType"};
        
        if (($fType == 10) || ($fType == 18)) {
            $cType = 'Chest_Freezer';
        } else {
            $cType = 'Upright_Freezer';
        };
    
    } else { # Error
        die "Invalid cold appliance type\n";
    };
    
    return ($UEC,$cType);
};

# ====================================================================
# setColdProfile
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     UEC: Unit energy consumption [kWh/yr]
#           iCyclesPerYear: number of cycles per year
#           iMeanCycleLength: mean cycle length [min]
#           iRestartDelay: delay restart after cycle [min]
# OUTPUT    Cold: Annual electrical consumption profile of cold appliance [W]
# ====================================================================

sub setColdProfile {
    # Declare inputs
    my $UEC = shift;
    my $iCyclesPerYear = shift;
    my $iMeanCycleLength = shift;
    my $iRestartDelay = shift;
    
    # Local variables
    my $fPower; # Power draw when cycle is on [W]
    my $dCalibrate; # Calibration value to determine switch-on events
    my $iRestartDelayTimeLeft; # Counter to hold time left in the delay restart
    
    # Declare outputs
    my @Cold=(0) x 525600;
    my $cType;
    
    # Determine time appliance is running in a year [min]
    my $Trunning=$iCyclesPerYear*$iMeanCycleLength;
    
    # Determine the minutes in a year when an event can occur
    my $Ms = 525600-($Trunning+($iCyclesPerYear*$iRestartDelay));
    
    # Determine the mean time between start events [min]
    my $MT=$Ms/$iCyclesPerYear;
    $dCalibrate=1/$MT;
    
    # Estimate the cycle power [W]
    $fPower=($UEC/($Trunning/60))*1000;
    
    # ====================================================================
    # Begin generating profile
    # ====================================================================
    # Randomly delay the start of appliances that have a restart delay (e.g. cold appliances with more regular intervals)
    $iRestartDelayTimeLeft = int(rand()*$iRestartDelay*2); # Weighting is 2 just to provide some diversity
    my $iCycleTimeLeft = 0;
    my $iMinute = 0;
    
    MINUTE: while ($iMinute < 525600) { # For each minute of the year
        if ($iCycleTimeLeft <= 0 && $iRestartDelayTimeLeft > 0) { # If this appliance is off having completed a cycle (ie. a restart delay)
            # Decrement the cycle time left
            $iRestartDelayTimeLeft--;
        } elsif ($iCycleTimeLeft <= 0) { # Else if this appliance is off
            if (rand() < $dCalibrate) { # Start Appliance
                $Cold[$iMinute] = $fPower;
                $iRestartDelayTimeLeft = $iRestartDelay;
                $iCycleTimeLeft = $iMeanCycleLength-1;
            };
        } else { # The appliance is on
            $Cold[$iMinute] = $fPower;
            $iCycleTimeLeft--;
        };
        $iMinute++;
    }; # END MINUTE
    
    return(\@Cold);
};

# ====================================================================
# ActiveStatParser
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     path: String, path to the activity stats file
# OUTPUT    Activity: HASH holding the activity data
# ====================================================================

sub ActiveStatParser {
    # Declare inputs
    my $path = shift;
    
    # Local variables
    my $fh;     # File handle
    my $day='wd';    # String to hold weekend or weekday
    my $NOcc;        # Number of occupants
    my $Act;         # String, activity type

    # Declare outputs
    my $Activity;
    
    
    open($fh,'<',$path) or die "Could not open file '$path' $!";
    # Read data line by line
    while (my $row = <$fh>) {
        chomp $row;
        my @data = split /,/, $row;
        if ($data[0]>0) {$day='we'};
        $NOcc = $data[1]; # Get active occupant count
        $Act = $data[2];  # Get the activity name
        @data = @data[ 3 .. $#data ]; # trim out the above data
        $Activity->{$day}->{"$NOcc"}->{$Act} = \@data; # Store the statistics
    };

    return($Activity);
};

# ====================================================================
# GetApplianceStock
#       This subroutine uses a top-down approach to generate high-resolution
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     NN: HASH containing the NN inputs from the CHREM
# OUTPUT    stock: Array of strings containing the appliance stock for this dwelling
# ====================================================================

sub GetApplianceStock {
    # Declare inputs
    my $NN = shift;
    my $AppRegion = shift;
    
    # Local variables
    my $iTVs = 0;     # Number of TVs in dwelling

    # Declare outputs
    my @stock=();
    
    # Determine appliances from CHREM NN inputs
    
    # Presence only
    #if($NN->{'Stove'} > 0) {
    #    push(@stock,'Range');
    #    push(@stock,'Oven');
    #};
    if($NN->{'Microwave'} > 0) {push(@stock,'Microwave')};
    #if($NN->{'Clothes_Dryer'} > 0) {push(@stock,'Clothes_Dryer')};
    if($NN->{'Dishwasher'} > 0) {push(@stock,'Dishwasher')};
    if($NN->{'Fish_Tank'} > 0) {push(@stock,'Fish_Tank')};
    if($NN->{'Clothes_Washer'} > 0) {push(@stock,'Clothes_Washer')};
    if($NN->{'Sauna'} > 0) {push(@stock,'Sauna')};
    if($NN->{'Jacuzzi'} > 0) {push(@stock,'Jacuzzi')};

    if($NN->{'Central_Vacuum'} > 0) {
        push(@stock,'Central_Vacuum');
    } elsif (rand() < $AppRegion->{'Vacuum'}) {
        push(@stock,'Vacuum');
    };
    
    # Determine TV stock
    #==============================================
    if($NN->{'Color_TV'} > 0) {
        for(my $i=1; $i<=$NN->{'Color_TV'};$i++) {
            #push(@stock,'TV');
            $iTVs++;
        };
    };
    if($NN->{'BW_TV'} > 0) {
        for(my $i=1; $i<=$NN->{'BW_TV'};$i++) {
            #push(@stock,'TV');
            $iTVs++;
        };
    };
    my $ref_TV = getTVstock($iTVs,$AppRegion);
    my @sTVStock = @$ref_TV;
    push(@stock,@sTVStock);
    
    
    if($NN->{'Computer'} > 0) {
        for(my $i=1; $i<=$NN->{'Computer'};$i++) {
            push(@stock,'Computer_desk');
            if (rand() < $AppRegion->{'Printer'}) {
                push(@stock,'Printer');
            };
        };
    };
    if($NN->{'VCR'} > 0) {
        for(my $i=1; $i<=$NN->{'VCR'};$i++) {
            push(@stock,'VCR');
        };
    };
    
    if($NN->{'CD_Player'} > 0) {
        for(my $i=1; $i<=$NN->{'CD_Player'};$i++) {
            push(@stock,'CD_Player');
        };
    };
    if($NN->{'Stereo'} > 0) {
        for(my $i=1; $i<=$NN->{'Stereo'};$i++) {
            push(@stock,'Stereo');
        };
    };

    # Randomly distribute the remaining CREST appliances
    if (rand() < $AppRegion->{'Iron'}->{'Portion'}) {
        push(@stock,'Iron');
    };
    if (rand() < $AppRegion->{'Kettle'}->{'Portion'}) {
        push(@stock,'Kettle');
    };
    if (rand() < $AppRegion->{'Hair_Dryer'}->{'Portion'}) {
        push(@stock,'Hair_Dryer');
    };
    
    # Determine TV accessory stock
    if ($iTVs>0) {
        if (rand() < $AppRegion->{'TV_Reciever_box'}->{'Portion'}) { # Is there an associated receiver box?
            # How many?
            push(@stock,'TV_Reciever_box');
            if ($iTVs>1) { # More than one TV
                if (rand() > $AppRegion->{'TV_Reciever_box'}->{'Only_One'}) {push(@stock,'TV_Reciever_box')}; # Add another console
            };
        };
        if (rand() < $AppRegion->{'Game_Console'}->{'Portion'}) {
            # How many?
            push(@stock,'Game_Console');
            if ($iTVs>1) { # More than one TV
                if (rand() > $AppRegion->{'Game_Console'}->{'Only_One'}) {push(@stock,'Game_Console')}; # Add another console
            };
        };
    }
    return(\@stock);
};

# ====================================================================
# GetApplianceProfile
#       This subroutine uses generates the 
#       power draw profiles for cold appliances. The approach is similar to the 
#       cyclic load patterns found in Widen & Wackelgard 2010, although the ON/OFF
#       periods are assigned constant values for simplicity. 
#
# INPUT     Occ_ref: Reference to array holding annual occupancy data
#           item: String, name of the appliance
#           sUseProfile: String indicating the usage type
#           iMeanCycleLength: Mean length of each cycle [min]
#           iCyclesPerYear: Calibrated number of cycles per year
#           iStandbyPower: Standby power [W]
#           iRatedPower: Rated power during cycles [W]
#           iRestartDelay: Delay prior to starting a cycle [min]
#           fAvgActProb: Average activity probability [-]
#           ActStat: HASH holding the activity statistics
#           MeanActOcc: fraction of time occupants are active [-]
#           sOccDepend: Activity occupant presence dependent [YES/NO]
#           dayWeek: day of the week [1=Sunday, 7=Saturday]
# OUTPUT    Profile: The power consumption for this appliance at a 1-minute timestep [kW]
# ====================================================================

sub GetApplianceProfile {
    # Declare inputs
    my $Occ_ref = shift;
    my @Occ = @$Occ_ref;
    my $item = shift;
    my $sUseProfile = shift;
    my $iMeanCycleLength = shift;
    my $iCyclesPerYear = shift;
    my $iStandbyPower = shift;
    my $iRatedPower = shift;
    my $iRestartDelay = shift;
    my $fAvgActProb = shift;
    my $ActStat = shift;
    my $MeanActOcc = shift;
    my $sOccDepend = shift;
    my $dayWeek = shift;
    
    # Local variables
    my $iCycleTimeLeft = 0;
    my $sDay;   # String to indicate weekday or weekend
    my $iYear=0; # Counter for minute of the year
    my $iRestartDelayTimeLeft = rand()*$iRestartDelay*2; # Randomly delay the start of appliances that have a restart delay
    my $bDayDep=1; # Flag indicating if appliance is dependent on weekend/weekday (default is true)
    my @PDF=(); # Array to hold the ten minute interval usage statistics for the appliance
    my $fAppCalib;
    my $bBaseL=0; # Boolean to state whether this appliance is a constant base load
    
    # Declare outputs
    my @Profile=($iStandbyPower) x 525600; # Initialize to constant standby power [W]
    
    # Determine the calibration scalar
    if ($iCyclesPerYear > 0) {
        $fAppCalib = ApplianceCalibrationScalar($iCyclesPerYear,$iMeanCycleLength,$MeanActOcc,$iRestartDelay,$sOccDepend,$fAvgActProb);
    } else { # This is just a constant load
        $bBaseL=1;
    };
    
    if ($bBaseL < 1) { # Not a baseload appliance, calculate the timestep data
        # Make the rated power variable over a normal distribution to provide some variation [W]
        $iRatedPower = GetMonteCarloNormalDistGuess($iRatedPower,($iRatedPower/10));
        
        # Determine if appliance operation is weekday/weekend dependent
        if($sUseProfile =~ m/Active_Occ/ || $sUseProfile =~ m/Level/) {$bDayDep=0};
        
        # Start looping through each day of the year
        DAY: for(my $iDay=1;$iDay<=365;$iDay++) {
            my $DayStat; # HASH reference for current day
            
            # If this appliance depends on day type, get the relevant activity statistics
            if($bDayDep) { 
                if($dayWeek>7){$dayWeek=1};
                if($dayWeek == 1 || $dayWeek == 7) { # Weekend
                    $sDay = 'we';
                } else { # Weekday
                    $sDay = 'wd';
                };
                $DayStat=$ActStat->{$sDay};
            };
            
            # For each 10 minute period of the day
            TEN_MIN: for(my $iTenMin=0;$iTenMin<144;$iTenMin++) {
                # For each minute of the day
                MINUTE: for(my $iMin=0;$iMin<10;$iMin++) {
                    # If this appliance is off having completed a cycle (ie. a restart delay)
                    if ($iCycleTimeLeft <= 0 && $iRestartDelayTimeLeft > 0) {
                        $iRestartDelayTimeLeft--; # Decrement the cycle time left
                        
                    # Else if this appliance is off    
                    } elsif ($iCycleTimeLeft <= 0) {
                        # There must be active occupants, or the profile must not depend on occupancy for a start event to occur
                        if (($Occ[$iYear] > 0 && $sUseProfile !~ m/Custom/) || $sUseProfile =~ m/Level/) {
                            # Variable to store the event probability (default to 1)
                            my $dActivityProbability = 1;
                            
                            # For appliances that depend on activity profiles
                            if (($sUseProfile !~ m/Level/) && ($sUseProfile !~ m/Active_Occ/) && ($sUseProfile !~ m/Custom/)) {
                                # Get the probability for this activity profile for this time step
                                my $CurrOcc = $Occ[$iYear]; # Current occupancy this timestep
                                my $Prob_ref = $DayStat->{"$CurrOcc"}->{$sUseProfile};
                                my @Prob=@$Prob_ref;
                                $dActivityProbability = $Prob[$iTenMin];
                            };
                            
                            # If there is seasonal variation, adjust the calibration scalar
                            if ($item =~ m/^Clothes_Dryer$/) { # Dryer usage varies seasonally
                                my $fAmp =  20.5; # based on difference in average loads/week winter/summer (SHEU 2011);
                                my $fModCyc = ($fAmp*sin(((2*3.14159265*$iDay)/365)-((1241*3.14159265)/730)))+$iCyclesPerYear;
                                $fAppCalib = ApplianceCalibrationScalar($fModCyc,$iMeanCycleLength,$MeanActOcc,$iRestartDelay,$sOccDepend,$fAvgActProb); #Adjust the calibration
                            }; # elsif .. (Other appliances)
                            
                            # Check the probability of a start event
                            if (rand() < ($fAppCalib*$dActivityProbability)) {
                                ($iCycleTimeLeft,$iRestartDelayTimeLeft,$Profile[$iYear]) = StartAppliance($item,$iRatedPower,$iMeanCycleLength,$iRestartDelay,$iStandbyPower);
                            };
                        } elsif ($sUseProfile =~ m/Custom/) {
                            # PLACE CODE HERE FOR CUSTUM APPLIANCE BEHAVIOUR
                            # THIS CODE BLOCK DETERMINES HOW CUSTOM APPLIANCE IS SWITCHED ON
                            # ($iCycleTimeLeft,$iRestartDelayTimeLeft,$Profile[$iYear]) = StartCustom($item,$iRatedPower,$iMeanCycleLength,$iRestartDelay,$iStandbyPower);
                        };
    
                    # The appliance is on - if the occupants become inactive, switch off the appliance
                    } else {
                        if (($Occ[$iYear] == 0) && ($sUseProfile !~ m/Level/) && ($sUseProfile !~ m/Act_Laundry/) && ($item !~ m/Dishwasher/) && ($sUseProfile !~ m/Custom/)) {
                            # Do nothing. The activity will be completed upon the return of the active occupancy.
                            # Note that LEVEL means that the appliance use is not related to active occupancy.
                            # Note also that laundry appliances do not switch off upon a transition to inactive occupancy.
                            # The original CREST model was modified to include dishwashers here as well
                        } elsif ($sUseProfile !~ m/Custom/) { 
                            # Set the power
                            $Profile[$iYear]=GetPowerUsage($item,$iRatedPower,$iCycleTimeLeft,$iStandbyPower);
                            
                            # Decrement the cycle time left
                            $iCycleTimeLeft--;
                        } else { # Custum Use profile
                            # PLACE CODE HERE FOR CUSTUM APPLIANCE BEHAVIOUR
                            # THIS CODE BLOCK DETERMINES HOW CUSTOM APPLIANCE BEHAVES 
                            # WHILE IT IS ON
                            # $Profile[$iYear]=GetCustomUsage($item,$iRatedPower,$iCycleTimeLeft,$iMeanCycleLength,$iStandbyPower);
                        };
                    };
    
                    $iYear++; # Increment the minute of the year
                }; # END MINUTE
            }; # END TEN_MIN
            $dayWeek++; # Increment the day of the week
        }; # END DAY
    }; # END CALCS

    return(\@Profile);
};

# ====================================================================
# GetMonteCarloNormalDistGuess
#   This subroutine randomly selects a value from a normal distribution.
#   Inputs are the mean and standard deviation
# ====================================================================
sub GetMonteCarloNormalDistGuess {
    my ($dMean, $dSD) = @_;
    my $iGuess=0;
    my $bOk;
    
    if($dMean == 0) {
        $bOk = 1;
    } else {
        $bOk = 0;
    };
    
    while (!$bOk) {
        $iGuess = (rand()*($dSD*8))-($dSD*4)+$dMean;
        my $px = (1/($dSD * sqrt(2*3.14159))) * exp(-(($iGuess - $dMean) ** 2) / (2 * $dSD * $dSD));

        if ($px >= rand()) {$bOk=1};

    };

    return $iGuess;
};

# ====================================================================
# IncreaseTimestepPower
#       This subroutine increases the timestep of a vector of power data
#
# INPUT     data: 1D array holding the data [W]
#           OldTstep: Old timestep of data [min]
#           NexTstep: New timestep of data [min]
# OUTPUT    NewData: 1D array holding the conditioned data
#           Errflg: Integer error flag to indicate process was successful
# ====================================================================
sub IncreaseTimestepPower {
    
    # Declare inputs
    my $data_ref = shift;
    my @data = @$data_ref;
    my $OldTstep = shift;
    my $NewTstep = shift;
    
    # Declare outputs
    my @NewData;
    my $Errflg=1;
    
    # Gather input data characteristics
    my $length = $#data+1; # length of array
    if (($length*$OldTstep) % $NewTstep) {
        # Invalid averaging period
        $Errflg=0;
    };

    # Condition the power data
    my $i=0;
    while ($i < $length) {
        my $SumOver = 0.0;
        for(my $j=0; $j<($NewTstep/$OldTstep);$j++) {
            $SumOver=$SumOver+$data[$i];
            $i++;
        };
        my $Out = $SumOver/($NewTstep/$OldTstep);
        push(@NewData,$Out);
    };

    return(\@NewData,$Errflg);
};
# ====================================================================
# rand_range
#   Randomly select an integer between two defined integers
# ====================================================================
sub rand_range {
    my ($x, $y) = @_;
    return int(rand($y - $x)) + $x;
};

# ====================================================================
# UpdateBCD
#   Randomly select an integer between two defined integers
# ====================================================================
sub UpdateBCD {	# subroutine to perform a simple element replace (house file to read/write, keyword to identify row, rows below keyword to replace, replacement text)
	my $hse_file = shift (@_);	# the house file to read/write
	my $Stove_ref = shift (@_);	# Stove power profile [W]
    my $Dryer_ref = shift (@_);	# Dryer power profile [W]
	my $Other_ref = shift (@_);	# Other AL power profile [W]
    my $DHW_ref = shift (@_);	# DHW draw profile [L/hr]
    my $Stovefuel = shift (@_);	# the house file to read/write
    my $TStep = shift (@_);	# timestep of the simulation [min]
    my @Stove = @$Stove_ref;
    my @Dryer = @$Dryer_ref;
    my @Other = @$Other_ref;
    
    # Declare outputs
    my $StoveE=0.0; # Stove energy [kWh]
    my $DryerE=0.0; # Dryer energy [kWh]
    my $OtherE=0.0; # Other energy [kWh]
    
    my $line = 0;
    CHECK_LINES: while ($line<=$#{$hse_file}) {
        if ($hse_file->[$line] =~ /data_start/) {
            $line++; # advance to the next line and begin inserting new data
            my $k=0;
            while ($hse_file->[$line] !~ m/data_end/) {
                my ($DHW) = $hse_file->[$line] =~ /(\d+)/; # Get the DHW data
                # Populate new line
                $Stove[$k]=sprintf("%d",$Stove[$k]);
                $Dryer[$k]=sprintf("%d",$Dryer[$k]);
                $Other[$k]=sprintf("%d",$Other[$k]);

                my $newline = sprintf "%26s %15s %15s %10s %15s\n", $DHW, $Stove[$k],$Stove[$k],$Dryer[$k],$Other[$k];
                $hse_file->[$line] = $newline;
                # Update the energy counts
                $StoveE=$StoveE+(($Stove[$k]*$TStep)/60000.0);
                $DryerE=$DryerE+(($Dryer[$k]*$TStep)/60000.0);
                $OtherE=$OtherE+(($Other[$k]*$TStep)/60000.0);
                
                $line++;
                $k++;
            };
            last CHECK_LINES;
        } else {
            $line++;
        };
    };
    
    $StoveE=sprintf("%.2f",$StoveE);
    $DryerE=sprintf("%.2f",$DryerE);
    $OtherE=sprintf("%.2f",$OtherE);
    

	return($StoveE,$DryerE,$OtherE);
};
# ====================================================================
#  LOCAL SUBROUTINES
# ====================================================================

# ====================================================================
# EffectiveOccupancy
#   This subroutine determines the effective occupancy
# ====================================================================
sub GetEffectiveOccupancy {
    my ($Occ) = @_; # Number of occupants active

    my $EffOcc;
    
    if ($Occ==0) {
        $EffOcc=0;
    } elsif ($Occ==1) {
        $EffOcc=1;
    } elsif ($Occ==2) {
        $EffOcc=1.528;
    } elsif ($Occ==3) {
        $EffOcc=1.694;
    } elsif ($Occ==4) {
        $EffOcc=1.983;
    } elsif ($Occ==5) {
        $EffOcc=2.094;
    } else {
        die "Number of occupants $Occ exceeds model limits";
    };

    return $EffOcc;
};

# ====================================================================
# GetLightDuration
#   Determines the lighting event duration
#   REFERENCE: - Stokes, Rylatt, Lomas "A simple model of domestic lighting
#                demand". Energy and Buildings, 36(2), 2004. 
# ====================================================================
sub GetLightDuration {

    # Decalre the output
    my $Duration;
    
    # Lighting event duration model data
    my $cml;
    $cml->{'1'}->{'lower'}=1;
    $cml->{'1'}->{'upper'}=1;
    $cml->{'1'}->{'cml'}=0.111111111;
    
    $cml->{'2'}->{'lower'}=2;
    $cml->{'2'}->{'upper'}=2;
    $cml->{'2'}->{'cml'}=0.222222222;
    
    $cml->{'3'}->{'lower'}=3;
    $cml->{'3'}->{'upper'}=4;
    $cml->{'3'}->{'cml'}=0.222222222;
    
    $cml->{'4'}->{'lower'}=5;
    $cml->{'4'}->{'upper'}=8;
    $cml->{'4'}->{'cml'}=0.333333333;
    
    $cml->{'5'}->{'lower'}=9;
    $cml->{'5'}->{'upper'}=16;
    $cml->{'5'}->{'cml'}=0.444444444;
    
    $cml->{'6'}->{'lower'}=17;
    $cml->{'6'}->{'upper'}=27;
    $cml->{'6'}->{'cml'}=0.555555556;
    
    $cml->{'7'}->{'lower'}=28;
    $cml->{'7'}->{'upper'}=49;
    $cml->{'7'}->{'cml'}=0.666666667;
    
    $cml->{'8'}->{'lower'}=50;
    $cml->{'8'}->{'upper'}=91;
    $cml->{'8'}->{'cml'}=0.888888889;
    
    $cml->{'8'}->{'lower'}=92;
    $cml->{'8'}->{'upper'}=259;
    $cml->{'8'}->{'cml'}=1.0;
    
    my $r_one = rand();
    
    RANGE: for (my $j=1;$j<=9;$j++) {
        if ($r_one < $cml->{"$j"}->{'cml'}) {
            my $r_two = rand();
            $Duration = ($r_two * ($cml->{"$j"}->{'upper'}-$cml->{"$j"}->{'lower'}))+$cml->{"$j"}->{'lower'};
            $Duration = sprintf "%.0f", $Duration; # Round to nearest integer
            last RANGE;
        };
    }; # END RANGE

    return $Duration;
};

# ====================================================================
# StartAppliance
#   Start a cycle for the current appliance
# ====================================================================
sub StartAppliance {
    
    # Declare inputs
    my $item = shift;
    my $iRatedPower = shift;
    my $iMeanCycleLength = shift;
    my $iRestartDelay=shift;
    my $iStandbyPower=shift;

    # Declare outputs
    my $iCycleTimeLeft = CycleLength($item,$iMeanCycleLength);
    my $iRestartDelayTimeLeft=$iRestartDelay;
    my $iPower = GetPowerUsage($item,$iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    
    $iCycleTimeLeft--;

    return($iCycleTimeLeft,$iRestartDelayTimeLeft,$iPower);
};

# ====================================================================
# CycleLength
#   Determine the cycle length of the appliance
# ====================================================================
sub CycleLength {
    
    # Declare inputs
    my $item = shift;
    my $iMeanCycleLength = shift;

    # Declare outputs
    my $CycleLen=$iMeanCycleLength;
    
    if($item =~ m/TV/) { # If the appliance is a television
        # The cycle length is approximated by the following function
        # Average time Canadians spend watching TV is 2.1 hrs (Stats Can: General 
        # social survey (GSS), average time spent on various activities for the 
        # population aged 15 years and over, by sex and main activity. 2010)
        my $fRando = rand();
        if ($fRando > 0.999) {$fRando=0.995};
        $CycleLen=int($iMeanCycleLength * ((0 - log(1 - $fRando)) ** 1.1));
    } elsif ($item =~ m/Game_Console/) {
        # The cycle length is approximated by the following function
        my $fRando = rand();
        if ($fRando > 0.999) {$fRando=0.995};
        $CycleLen=int($iMeanCycleLength * ((0 - log(1 - $fRando)) ** 1.1));
    # Currently these profiles are fixed. Override user input to length of
    # each static cycle
    } elsif ($item =~ m/Clothes_Washer/) {
        $CycleLen=40;
    } elsif (($item =~ m/Clothes_Dryer/) || ($item =~ m/Clothes_Dryer_CREST/)) {
        $CycleLen=75;
    } elsif ($item =~ m/Dishwasher/) {
        $CycleLen=124;
    };

    return($CycleLen);
};

# ====================================================================
# GetPowerUsage
#   Some appliances have a custom (variable) power profile depending on the time left
# ====================================================================
sub GetPowerUsage {
    
    # Declare inputs
    my $item = shift;
    my $iRatedPower = shift;
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs (Default to rated power)
    my $PowerUsage=$iRatedPower;
    
    if($item =~ m/Clothes_Washer/) { # If the appliance is a washer (peak 500 W)
        $PowerUsage=GetPowerWasher($iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    } elsif(($item =~ m/Clothes_Dryer/) || ($item =~ m/Clothes_Dryer_CREST/)) { # If the appliance is a dryer (peak 5535 W)
        $PowerUsage=GetPowerDryer($iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    } elsif($item =~ m/Dishwasher/) { # If the appliance is a dishwasher (peak 1300 W)
        $PowerUsage=GetPowerDish($iRatedPower,$iCycleTimeLeft,$iStandbyPower);
    };

    return($PowerUsage);
};

# ====================================================================
# GetPowerDryer
#   This subroutine generates the dryer profile. Note that it is a fixed
#   profile. The profile is a 73 minute cycle which consumes 7935 kJ of
#   energy. The profile is taken from H12 from the paper:
# REFERENCES: - Saldanha, Beausoleil-Morrison "Measured end-use electric load
#               profiles for 12 Canadian houses at high temporal resolution."
#               Energy and Buildings, 49, 2012.
#   The model of the dryer is Kenmore 110.C64852301
# ====================================================================
sub GetPowerDryer {
    
    # Declare inputs
    my $iRatedPower = shift; # Peak power demand
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs
    my $PowerUsage;
    
    # Declare local variables
    my @Profile = (0.674796748,0.951219512,0.991869919,0.967479675,0.991869919,1,
    1,1,1,0.991869919,0.991869919,0.983739837,0.975609756,0.975609756,0.528455285,
    0.203252033,0.951219512,0.951219512,0.691056911,0.056910569,0.739837398,
    0.967479675,0.349593496,0.056910569,0.74796748,0.804878049,0.056910569,
    0.056910569,0.341463415,0.333333333,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.048780488,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.06504065,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,0.056910569,
    0.056910569,0.056910569,0.06504065,0.056910569,0.056910569,0.06504065,
    0.056910569,0.056910569,0.056910569,0.06504065,0.056910569,0.032520325); # 1-minute profile for dryer
    my $iTotalCycleTime = scalar @Profile;
    my $index = $iTotalCycleTime - $iCycleTimeLeft;
    
    if (($index<0) || ($index>$#Profile)) {
        $PowerUsage = $iStandbyPower;
    } else {
        $PowerUsage=$iRatedPower*$Profile[$index];
    };
    
    return($PowerUsage);
};

# ====================================================================
# GetPowerWasher
#   This subroutine generates the clothes washer profile. Note that it is a
#   fixed profile. The profile is a 40 minute cycle. This is measured data
#   from a top-loading washing maching of approximately 1990's vintage
#   Data was measured using a WattsUp? Pro at 1-min timesteps
# ====================================================================
sub GetPowerWasher {
    
    # Declare inputs
    my $iRatedPower = shift; # Peak power demand
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs
    my $PowerUsage;
    
    # Declare local variables
    my @Profile = (0.008748413,0.008748413,0.008748413,0.008748413,0.008748413,
    0.956681247,0.916325667,0.892620291,0.853816848,0.853675744,0.860166502,
    0.872865811,0.847608297,0.589247919,0.59136447,0.595174263,0.591646677,
    0.593904332,0.583885988,0.54197827,0.498377311,0.786510512,0.730915761,
    0.008607309,0.008607309,0.008748413,0.008607309,0.008607309,0.838295471,
    0.843798504,0.828418231,0.874276845,0.535487512,0.497954,1,0.761535205,
    0.725836038,0.705658247,0.698603076,0.688725836); # 1-minute profile for washer
    my $iTotalCycleTime = scalar @Profile;
    my $index = $iTotalCycleTime - $iCycleTimeLeft;

    if (($index<0) || ($index>$#Profile)) {
        $PowerUsage = $iStandbyPower;
    } else {
        $PowerUsage=$iRatedPower*$Profile[$index];
    };
    
    return($PowerUsage);
};

# ====================================================================
# GetPowerDish
#   This subroutine generates the dishwasher profile. The profile is a 
#   124 minute cycle which consumes 5900 kJ of energy. The profile is 
#   scaled based on the rated input power. The profile is taken from
#   H12 from the paper:
# REFERENCES: - Saldanha, Beausoleil-Morrison "Measured end-use electric load
#               profiles for 12 Canadian houses at high temporal resolution."
#               Energy and Buildings, 49, 2012.
#   The model of the dishwasher is Kenmore 665.13732K601 
# ====================================================================
sub GetPowerDish {
    
    # Declare inputs
    my $iRatedPower = shift; # Peak power demand
    my $iCycleTimeLeft = shift;
    my $iStandbyPower = shift;

    # Declare outputs
    my $PowerUsage;
    
    # Declare local variables
    my @Profile = (0.153846154,0.153846154,0.153846154,0.153846154,0.153846154,
    0.153846154,0.153846154,0.153846154,0.153846154,0.153846154,0.153846154,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,0.215384615,
    0.215384615,0.215384615); # 1-minute profile for dishwasher
    my $iTotalCycleTime = scalar @Profile;
    my $index = $iTotalCycleTime - $iCycleTimeLeft;
    
    if (($index<0) || ($index>$#Profile)) {
        $PowerUsage = $iStandbyPower;
    } else {
        $PowerUsage=$iRatedPower*$Profile[$index];
    };
    
    return($PowerUsage);
};

# ====================================================================
# ApplianceCalibrationScalar
#   This subroutine determines the appliance calibration scalar
# ====================================================================
sub ApplianceCalibrationScalar {
    
    # Declare inputs
    my $iCyclesPerYear = shift;
    my $iMeanCycleLength = shift;
    my $MeanActOcc = shift;
    my $iRestartDelay = shift;
    my $sOccDepend = shift;
    my $fAvgActProb = shift;
    
    # Declare outputs
    my $fAppCalib;

    # Determine the calibration scalar for this appliance
    my $iTimeRunYr = $iCyclesPerYear*$iMeanCycleLength; # Time spent running per year [min]
    if ($iTimeRunYr>525600) { # Not possible to have this many cycles
        # Warn the user
        print "WARNING: Appliance with $iCyclesPerYear cycles per year and cycle length $iMeanCycleLength min\n";
        print "         Computed running time exceeds time in year. Setting time spent running to 70% of year.\n";
        $iCyclesPerYear = floor((525600*0.7)/$iMeanCycleLength);
        $iTimeRunYr = $iCyclesPerYear*$iMeanCycleLength;
    };
    my $iMinutesCanStart; # Minutes in a year when an event can start
    if($sOccDepend =~ m/YES/) { # Appliance is active occupant dependent
        $iMinutesCanStart = (525600*$MeanActOcc)-($iTimeRunYr+($iCyclesPerYear*$iRestartDelay));
    } else { # Appliance is not active occupant dependent
        $iMinutesCanStart = 525600-($iTimeRunYr+($iCyclesPerYear*$iRestartDelay));
    };
    if ($iMinutesCanStart<=0) { # There is no minutes when this appliance can start
        print "WARNING: Appliance has $iMinutesCanStart min in the year which it can start\n";
        print "         Setting mean start time between events to 1 min\n";
        $iMinutesCanStart=$iCyclesPerYear;
    };
    my $fMeanCanStart=$iMinutesCanStart/$iCyclesPerYear; # Mean time between start events given occupancy [min]
    my $fLambda = 1/$fMeanCanStart;
    $fAppCalib = $fLambda/$fAvgActProb; # Calibration scalar
    
    return($fAppCalib);
};

sub GetDHWData {
    # INPUTS
    my $DataFile = shift; # Path to the DHW data file
    my $source = shift; # Source of the measured DHW data
    my $shift = shift; # indicate if data is to be moved ahead a week or not
    
    # OUTPUTS
    my @DHW_Draw; # DHW draw [L/hr]
    my $DataTstep; # Measured data timestep [min]
    
    # Intermediates
    my $iTsteps; # Number of timestep of the measured data
    my $sFullPath = "../bcd" . $DataFile; # Relative path to the data
    
    if($source =~ m/^(WEL)/) { # Data from Dalhousie
        $DataTstep = 1;
        open my $fid, $sFullPath or die "GetDHWData: Could not find $sFullPath\n";
        my @FileLines = <$fid>; # slurp the file
        close $fid;
        
        # Grab the file header
        my $sHeader = shift @FileLines;
        
        foreach my $data (@FileLines) {
            $data  =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $data = $data*60.0; # Convert L/min to L/hr
            push(@DHW_Draw,$data);
        };
        
        $iTsteps = scalar @DHW_Draw;
        if($iTsteps != 525600) {die "GetDHWData: $iTsteps instead of 525600 timesteps were found for George data\n";}
        
    } elsif($source =~ m/^(H)/) { # Data from SBES
        $DataTstep = 5;
        open my $fid, $sFullPath or die "GetDHWData: Could not find $sFullPath\n";
        my @FileLines = <$fid>; # slurp the file
        close $fid;
        
        foreach my $data (@FileLines) {
            $data  =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $data = ($data/5.0)*60.0; # Determine the average flowrate over the 5 minute interval. Convert L/min to L/hr
            push(@DHW_Draw,$data);
        };
        
        $iTsteps = scalar @DHW_Draw;
        if($iTsteps != 105120) {die "GetDHWData: $iTsteps instead of 105120 timesteps were found for George data\n";}
        
    } else {die "GetDHWData: $source is not from a valid DHW data source\n";}
    
    # Shift the profile
    if(($shift==1) || ($shift==2)) {
        my @Top;
        my @Bottom;
        
        if($shift==1) { # Advance a week
            @Top = @DHW_Draw[(10080/$DataTstep)..$#DHW_Draw];
            @Bottom = @DHW_Draw[0..((10080/$DataTstep)-1)];
        } else { # Rewind a week
            @Top = @DHW_Draw[($#DHW_Draw-(10080/$DataTstep))..$#DHW_Draw];
            @Bottom = @DHW_Draw[0..(($#DHW_Draw-(10080/$DataTstep))-1)];
        };
        # Clear and update the draw profile
        @DHW_Draw=();
        push(@DHW_Draw,@Top);
        push(@DHW_Draw,@Bottom);
    };
    
    
    return(\@DHW_Draw,$DataTstep);
}; # END GetDHWData

# ====================================================================
# StretchProfile
#   Power or flow rates. Assumes constant flowrate across the new 
#   profile segments 
# ====================================================================
sub StretchProfile {
    # INPUTS
    my $ref_DHW = shift;
    my $MeasTstep = shift; 
    my $time_step = shift;
    my @Profile = @$ref_DHW;
    
    # OUTPUTS
    my @New=();
    
    if($MeasTstep<$time_step){
        return(\@Profile,0);
    } elsif($MeasTstep % $time_step) { # Does not divide cleanly
        return(\@Profile,0);
    };
    
    foreach my $item (@Profile) {
        for(my $i=0;$i<($MeasTstep/$time_step);$i++) {
            push(@New,$item);
        };
    };
    
    return(\@New,1); 
};

# ====================================================================
# FindAnnualALandDHW
#   Randomly select an integer between two defined integers
# ====================================================================
sub FindAnnualALandDHW {	# subroutine to perform a simple element replace (house file to read/write, keyword to identify row, rows below keyword to replace, replacement text)
	my $Stove_ref = shift (@_);	# Stove power profile [W]
    my $Dryer_ref = shift (@_);	# Dryer power profile [W]
	my $Other_ref = shift (@_);	# Other AL power profile [W]
    my $DHW_ref = shift (@_);	# DHW draw profile [L/hr]
    my $TStep = shift (@_);	# timestep of the simulation [min]
    my @Stove = @$Stove_ref;
    my @Dryer = @$Dryer_ref;
    my @Other = @$Other_ref;
    my @DHW = @$DHW_ref;
    
    if(($#Stove != $#Dryer) && ($#Dryer != $#Other)) {
        die "FindAnnualALandDHW: Electric profiles different lengths\n";
    } elsif($#Stove != $#DHW) {
        die "FindAnnualALandDHW: Electric and DHW profiles different lengths\n";
    };
    
    # Declare outputs
    my $StoveE=0.0; # Stove energy [kWh/yr]
    my $DryerE=0.0; # Dryer energy [kWh/yr]
    my $OtherE=0.0; # Other energy [kWh/yr]
    my $DhwYrL=0.0; # DHW consumption [L/yr]
    
    for(my $k=0;$k<=$#Stove;$k++) {

        # Update the energy counts
        $StoveE=$StoveE+(($Stove[$k]*$TStep)/60000.0);
        $DryerE=$DryerE+(($Dryer[$k]*$TStep)/60000.0);
        $OtherE=$OtherE+(($Other[$k]*$TStep)/60000.0);
        $DhwYrL=$DhwYrL+(($DHW[$k]*$TStep)/60.0);

    };
    
    $StoveE=sprintf("%.2f",$StoveE);
    $DryerE=sprintf("%.2f",$DryerE);
    $OtherE=sprintf("%.2f",$OtherE);
    $DhwYrL=sprintf("%.2f",$DhwYrL);
    

	return($StoveE,$DryerE,$OtherE,$DhwYrL);
};
# ====================================================================
# SetApplianceProfile
#   Load in the appliance inputs for sItem, and generate annual profile
# ====================================================================
sub SetApplianceProfile { 
    # INPUTS
    my $ref_Occ = shift @_; 
    my @Occ = @$ref_Occ; # Occupancy profile
    my $MeanActOcc = shift @_; # Mean active occupancy
    my $sItem = shift @_; # Appliance name
    my $hApp = shift @_; # Appliance input hash
    my $Activity = shift @_;
    my $AppCalib = shift @_; # Calibration scalar for appliances
    my $DayWeekStart = shift @_; # Day of the 
    
    # OUTPUTS
    my @ThisApp;
    
    # INTERMEDIATES
    my $sUseProfile=$hApp->{'Types_Other'}->{$sItem}->{'Use_Profile'}; # Type of usage profile
    my $iMeanCycleLength=$hApp->{'Types_Other'}->{$sItem}->{'Mean_cycle_L'}; # Mean length of cycle [min]
    my $iCyclesPerYear=$hApp->{'Types_Other'}->{$sItem}->{'Base_cycles'}*$AppCalib; # Calibrated number of cycles per year
    my $iStandbyPower=$hApp->{'Types_Other'}->{$sItem}->{'Standby'}; # Standby power [W]
    my $iRatedPower=$hApp->{'Types_Other'}->{$sItem}->{'Mean_Pow_Cyc'}; # Mean power per cycle [W]
    my $iRestartDelay=$hApp->{'Types_Other'}->{$sItem}->{'Restart_Delay'}; # Delay restart after cycle [min]
    my $fAvgActProb=$hApp->{'Types_Other'}->{$sItem}->{'Avg_Act_Prob'}; # Average activity probability [-]
    my $sOccDepend=$hApp->{'Types_Other'}->{$sItem}->{'Act_Occ_Dep'}; # Active occupant dependent
    
    # Call the appliance simulation
    my $ThisApp_ref = &GetApplianceProfile(\@Occ,$sItem,$sUseProfile,$iMeanCycleLength,$iCyclesPerYear,$iStandbyPower,$iRatedPower,$iRestartDelay,$fAvgActProb,$Activity,$MeanActOcc,$sOccDepend,$DayWeekStart);
    @ThisApp = @$ThisApp_ref;

	return(\@ThisApp);
};

# ====================================================================
sub GetStoveAppliances {

    # Outputs
    my @CookStock=();
    
    # Divide the stove into separate components
    push(@CookStock,'Large_Element_1');
    push(@CookStock,'Large_Element_2');
    push(@CookStock,'Small_Element_1');
    push(@CookStock,'Small_Element_2');
    
    return(\@CookStock);
};
# ====================================================================
# getTVstock
#       Determines the different types of TVs in the dwellings
#
# INPUT     iTVs: Integer number of TVs
#           AppRegion: Has holding distribution of TVs
# OUTPUT    sTVStock: Array of strings containing all the TV types
# ====================================================================
sub getTVstock {
    # INPUTS
    my $iTVs = shift @_;
    my $AppRegion = shift @_;
    
    # OUTPUTS
    my @sTVStock=();
    
    # INTERMEDIATES
    my @sNames=();
    my $U = rand();
    my $j=0;

    # Loop through each TV
    for my $i (1..$iTVs) {
        TUBE: foreach my $sType (keys (%{$AppRegion->{'TV'}})) {
            $j+=$AppRegion->{'TV'}->{"$sType"}->{'Portion'};
            if ($j > $U) {
                push(@sNames,$sType);
                $j=0;
                last TUBE;
            };
        };
    };
    
    return(\@sTVStock);
};
# ====================================================================
  
# Final return value of one to indicate that the perl module is successful
1;