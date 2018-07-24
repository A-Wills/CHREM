# ====================================================================
# AL_Profile_Gen.pm
# Author: Adam Wills
# Date: June 2016
# Copyright: Carleton University
# ====================================================================
# The following subroutines are included in the perl module:
# ====================================================================

# Declare the package name of this perl module
package UpgradeCity;

# Declare packages used by this perl module
use strict;
use warnings;
use CSV;	# CSV-2 (for CSV split and join, this works best)
use Cwd;
use Data::Dumper;
use Switch;

use lib qw(./modules);
use PV;
use General qw(replace insert);

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(getGEOdata upgradeCeilIns setBCDpath upgradeBsmtIns setVentilation upgradeDHsystem upgradeGLZ setNewInfil getDwellingVentilationRate getVentType setVNTfile upgradeWallIns getVentFlowRate);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# getGEOdata
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getGEOdata {
    # get list of dwellings
    my ($list_ref, $path) = @_;
    my @list = @$list_ref;
    
    # Outputs
    my $Surf;
    
    # Intermediates
    
    
    Go_list: foreach my $rec (@list) { # For each record
        # Get the paths for all the geo files in this model
        my $recPath = $path . "$rec";
        my @geofiles = glob "$recPath/*.geo";
        my $VertsList;
        
        # Determine the zone ordering
        $Surf = getZoneDataCFG($rec,$path,$Surf);

        # Load each geo file
        foreach my $zone (@geofiles) {
            my $iSurfNum=1;
            my $RelPath = $zone;
            # Determine the zone name
            $zone =~ s/\.geo$//;
            $zone =~ s/.*\.//;
            my @ZoneAreas=(); # Array to hold the zone surface areas [m2]
            my @SufNames=();
            
            # Crack open the geo file 
            my $GeoFID;
            open $GeoFID, $RelPath or die "Could not open $RelPath\n";
            my @lines = <$GeoFID>; # Pull entire file into an array
            
            # Load in the vertices
            my $DataLine=0;
            my $FileLine=0;
            until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine>2)) {
                $FileLine++;
                if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
            };
            my $nVerts=1; # Number of vertices in this zone
            until($lines[$FileLine] =~ m/^(#)/i) {
                my $thisVert = "v$nVerts";
                $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                my @LineDat = split ' ', $lines[$FileLine];
                $VertsList->{$thisVert}->{'x'} = $LineDat[0];
                $VertsList->{$thisVert}->{'y'} = $LineDat[1];
                $VertsList->{$thisVert}->{'z'} = $LineDat[2];
                $nVerts++;
                $FileLine++;
            };
            $nVerts--;

            # Begin looping through surface data
            #====================================================================
            until($lines[$FileLine] =~ m/^(#END_SURFACES)/) {
                my @VertSurflist=(); # Array holding all the vertices in order
                if($lines[$FileLine] =~ m/^(#)/i) {
                    $FileLine++;
                } else {
                    my @AoA=(); # Array of array holding the coordinate data for the surface
                    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                    my @LineDat = split /[,\s]+/, $lines[$FileLine];
                    my $surfVerts = shift @LineDat; # Number of vertices defining this surface

                    for (my $i=0;$i<$surfVerts;$i++) { # Get the vertex listing
                        push(@VertSurflist,$LineDat[$i]);
                    };

                    # Populate AoA with the coordinates of each vertex of the surface
                    foreach my $point (@VertSurflist) {
                        my @thisCoord=();
                        push(@thisCoord,$VertsList->{"v$point"}->{'x'});
                        push(@thisCoord,$VertsList->{"v$point"}->{'y'});
                        push(@thisCoord,$VertsList->{"v$point"}->{'z'});
                        push @AoA, [@thisCoord];
                    };
                    my $thisArea = &area3D_Polygon(\@AoA);
                    
                    push(@ZoneAreas, $thisArea);
                    $FileLine++;
                };
            }; # End of surface-vertex data
            
            # Get the surface attributes
            until($lines[$FileLine] =~ m/^(#SURFACE_ATTRIBUTES)/) {$FileLine++;} # FFWD to surface attributes
            until($lines[$FileLine] !~ m/^(#)/i) {$FileLine++;} # Skip past any preliminary comments
            until($lines[$FileLine] =~ m/^(#)/i) { # Read in the surface attributes
                $lines[$FileLine] =~ s/^\s+|\s+$//g; # Trim leading and lagging whitespace
                my @LineDat = split /[,\s]+/, $lines[$FileLine];
                $Surf->{"_$rec"}->{$zone}->{'Surfaces'}->{"$LineDat[1]"}->{'area'} = shift(@ZoneAreas);
                $Surf->{"_$rec"}->{$zone}->{'Surfaces'}->{"$LineDat[1]"}->{'surf_num'} = $iSurfNum;
                
                $iSurfNum++;
                $FileLine++;
            };

        };
        
        # Get the links 
        $Surf->{"_$rec"} = getCNN($rec,$path,$Surf->{"_$rec"});

    }; # End of record
    
    return $Surf;
};
# ====================================================================
# upgradeCeilIns
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeCeilIns {
    # Inputs
    # Name of dwelling, Maximum ceiling insulation (RSI), path to the set, HASH holding upgrade data
    my ($house_name,$UpgradesCeil,$thisHouse,$setPath,$UPGrecords) = @_;
    
    # Intermediates
    my $strRoofType; # String holding the roof type (attic|flat)
    my $strAdj;     # Name of the zone adjacent to the attic
    
    # Determine the roof type
    foreach my $zones (keys (%{$thisHouse})) {
        if ($zones =~ m/attic/) {
            $strRoofType=$zones;
            last;
        };
        if ($zones =~ m/roof/) {
            $strRoofType=$zones;
            last;
        };
    };
    if (not defined($strRoofType)) {die"$house_name: Could not find attic or roof\n";}
    
    if ($strRoofType =~ m/attic/) {
        # Gather and update the attic construction data
        my $recPath = $setPath . "$house_name/";
        
        $UPGrecords = UpdateCONdataCEILING($UpgradesCeil,$house_name,$recPath,$thisHouse,$strRoofType,'floor',$UPGrecords);
        
        # Update the upgrade record

    } else { # This is a flat roof
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"roof"}->{"floor"}->{'new_RSI'} = 0.0;
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"roof"}->{"floor"}->{'original_RSI'} = 0.0;
    };
    
    return $UPGrecords;

}; # END upgradeCeilIns
# ====================================================================
# setBCDpath
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setBCDpath {
    my ($ref_hse,$BCDPath,$setPath) = @_;
    my @houses_desired = @$ref_hse;
    
    ECH_HSE: foreach my $hse (@houses_desired) {
        # Load the cfg
        my $ThisCFGpath = $setPath . "$hse/$hse.cfg";
        my $CfgFID;
        open $CfgFID, $ThisCFGpath or die "Could not open $ThisCFGpath\n";
        my @lines = <$CfgFID>; # Pull entire file into an array
        close $CfgFID;
        
        # Update the bcd entry
        my $FileLine = 0;
        until (($lines[$FileLine] =~ /^(\*bcd)/) || ($FileLine==$#lines)) {$FileLine++};
        $lines[$FileLine] = "*bcd ../../$BCDPath/$hse.bcd\n";
        
        # Write the new cfg file
        open my $out, '>', $ThisCFGpath or die "Can't write $ThisCFGpath: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    
    }; # END ECH_HSE
};
# ====================================================================
# upgradeBsmtIns
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeBsmtIns {
    # Inputs
    # Name of dwelling, Maximum basement insulation (RSI), path to the set, HASH holding upgrade data
    my ($house_name,$UpgradesBsmt,$thisHouse,$setPath,$UPGrecords) = @_;
    
    # Intermediates
    my $strFdnType; # String holding the foundation type
    my $recPath = $setPath . "$house_name/";
    my $newBSMtype;
    
    # Determine the foundation type
    foreach my $zones (keys (%{$thisHouse})) {
        if ($zones =~ m/bsmt/) {
            $strFdnType=$zones;
            last;
        };
        if ($zones =~ m/crawl/) {
            $strFdnType=$zones;
            last;
        };
    };
    if (not defined($strFdnType)) {$strFdnType="slab";}
    
    # Determine what kind of BASESIMP configuration is being used
    my $BsmtIndex = getBSMTType($house_name,$recPath);
    # Store the original BASESIMP type
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'orig_basesimp_code'} = $BsmtIndex;
        
    # Only apply insulation to foundation type `bsmt' and `crawl'
    if($strFdnType =~ m/bsmt/) {
        # Update the bsm file
        ($UPGrecords,$newBSMtype) = setBSMfile($house_name,$recPath,$BsmtIndex,$UpgradesBsmt,$UPGrecords);
        # Update the connections file if the foundation type has changed
        if($newBSMtype>0){setBsmCNN($house_name,$recPath,$newBSMtype);}
        # Store the foundation type
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    } elsif($strFdnType =~ m/crawl/) { # Foundation crawlspace
        $UPGrecords = UpdateCONdataCRAWL($UpgradesBsmt,$house_name,$recPath,$thisHouse,$strFdnType,$UPGrecords);
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    } else { # Foundation is slab
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'foundation_type'} = $strFdnType;
    };

    return $UPGrecords;

}; # END upgradeCeilIns
# ====================================================================
# upgradeDHsystem
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeDHsystem {
    # INPUTS
    my ($house_name,$UpgradesDH,$ThisSurfaces,$set_name,$setPath,$UPGrecords) = @_;
    
    # OUTPUTS
    my $bPrintDHW=0;  # Boolean to indicate if the DHW loads are to be printed
    
    # Interrogate this dwellings HVAC file
    $UPGrecords = getHVACdata($house_name,$setPath,$UPGrecords);
    
    # Interrogate this dwelling's DHW system
    $UPGrecords = getDHWdata($house_name,$setPath,$UPGrecords);
    
    # Remove the heating system from dwelling
    setHVACfileDH($house_name,$setPath,$UPGrecords);
    
    # Determine if the DHW loads have previously been determined
    my $possible_set_names = {map {$_, 1} grep(s/.+Aggregate_DHW(.+).csv/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
    if (defined($possible_set_names->{$set_name})) { # DHW loads have been calculated previously
		setCFGnoDHW($house_name,$setPath);
	} else { # Generate the DHW loads using ESP-r
		setDHWfileDH($house_name,$setPath,$UPGrecords);
        $bPrintDHW=1; # Indicate that the DHW loads need to be printed
	};
    
    return ($UPGrecords,$bPrintDHW);
};
# ====================================================================
# upgradeGLZ
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeGLZ {
    # Inputs: Name of dwelling, Maximum ceiling insulation (RSI), path to the set, HASH holding upgrade data
    my ($house_name,$UpgradesWindow,$thisHouse,$setPath,$UPGrecords) = @_;
    
    # Intermediates
    my @ZonesWithGlz;
    my $ZonesGlz; # HASH of arrays to hold names of all glazing surfaces

    # Store the surface index for each glazing surface and associated frame surface
    SCANSURF: foreach my $zones (keys (%{$thisHouse})) {
        if($zones =~ m/(PV)$/) {next SCANSURF;} # Ignore PV zones
        foreach my $surfs (keys (%{$thisHouse->{$zones}->{'Surfaces'}})) {
            if($surfs =~ m/aper$/) {
                push(@ZonesWithGlz,$zones);
                next SCANSURF;
                
            } elsif($surfs =~ m/frame$/) {
                push(@ZonesWithGlz,$zones);
                next SCANSURF;
            };
        };
    };

    # Gather the window codes
    $ZonesGlz = getWindowCodes($house_name,$setPath,\@ZonesWithGlz);
    
    # Determine eligible windows for upgrades
    FIND_ELIGIBLE: foreach my $zones (keys (%{$ZonesGlz})) {
        foreach my $parent (keys (%{$ZonesGlz->{$zones}})) {
            if($ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'glaze_type'} <= $UpgradesWindow->{'glaze_type'}){
                if($ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'coating'} < 1){ # This is a clear glass system
                    # This glazing system is eligible for upgrade
                    $UPGrecords->{'GLZ'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'original'}->{'glaze_type'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'glaze_type'};
                    $UPGrecords->{'GLZ'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'original'}->{'coating'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'coating'};
                    $UPGrecords->{'GLZ'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'original'}->{'fill_gas'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'fill_gas'};
                    $UPGrecords->{'GLZ'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'original'}->{'gap_width_code'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'gap_width_code'};

                    # Get the construction file coordinates for the glazing and frame
                    $UPGrecords->{'GLZ'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'surf_num'} = $thisHouse->{$zones}->{'Surfaces'}->{"$parent"."-aper"}->{'surf_num'};
                    $UPGrecords->{'GLZ'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'surf_num_frame'} = $thisHouse->{$zones}->{'Surfaces'}->{"$parent"."-frame"}->{'surf_num'};
                    
                    # Clear this key
                    delete $ZonesGlz->{$zones}->{"$parent"};
                };
            };
        };
    }; # END FIND_ELIGIBLE
    
    # Store the un-upgraded glazing
    foreach my $zones (keys (%{$ZonesGlz})) {
        foreach my $parent (keys (%{$ZonesGlz->{$zones}})) {
            $UPGrecords->{'GLZ'}->{'not_upgraded'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'glaze_type'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'glaze_type'};
            $UPGrecords->{'GLZ'}->{'not_upgraded'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'coating'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'coating'};
            $UPGrecords->{'GLZ'}->{'not_upgraded'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'fill_gas'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'fill_gas'};
            $UPGrecords->{'GLZ'}->{'not_upgraded'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'gap_width_code'} = $ZonesGlz->{$zones}->{"$parent"}->{'aper'}->{'gap_width_code'};
            
            # Get the construction file coordinates for the glazing and frame
            $UPGrecords->{'GLZ'}->{'not_upgraded'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'surf_num'} = $thisHouse->{$zones}->{'Surfaces'}->{"$parent"."-aper"}->{'surf_num'};
            $UPGrecords->{'GLZ'}->{'not_upgraded'}->{"$house_name"}->{"$zones"}->{"$parent"."-aper"}->{'surf_num_frame'} = $thisHouse->{$zones}->{'Surfaces'}->{"$parent"."-frame"}->{'surf_num'};
        };
    };

    # Update the construction files with the new glazing (if any new glazing is to be applies)
    if(exists($UPGrecords->{'GLZ'}->{"$house_name"})) {
        setNewWindows($house_name,$setPath,$UpgradesWindow,$UPGrecords->{'GLZ'});
    };
    
    return $UPGrecords;
};
# ====================================================================
# upgradeWallIns
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub upgradeWallIns {
    # Inputs
    # Name of dwelling, Wall upgrade HASH, Surface HASH ,path to the set, HASH holding upgrade data
    my ($house_name,$UpgradesWall,$thisHouse,$setPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $fCurrentRSI; # Current main wall insulation RSI
    my $sCurrentClad; # Current cladding on the main wall
    my $iSys = $UpgradesWall->{'RSI_goal'}; # Integer indicating which RSI value to achieve in the inputs
    my $sRSI_key = "goal_$iSys"; # Key pointing to value of RSI
    my $fGoalRSI = $UpgradesWall->{$sRSI_key};
    my $fIncreaseRSI;
    my $fInsThick=0; # Total thickness of insulation added [m]
    
    my $iIns = $UpgradesWall->{'ins'}; # Integer indicating which insulation to use in the inputs
    my $sInsKey = "ins_$iIns";
    
    my $iClad = $UpgradesWall->{'clad'}; # Integer indicating which cladding system to use in the inputs
    my $sCladKey = "clad_$iClad";
    
    # Determine the cladding and insulation RSI for this house
    $UPGrecords = getWallCladdingIns($house_name,$setPath,$UPGrecords);
    $fCurrentRSI = $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_RSI'};
    $sCurrentClad = $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_Cladding'};
    
    # Determine the increase in RSI required to meet input
    $fIncreaseRSI = $fGoalRSI-$fCurrentRSI;
    
    # Add general upgrade data if required
    if(not defined $UPGrecords->{'WALL_INS'}->{'Info'}) {
        $UPGrecords->{'WALL_INS'}->{'Info'}->{'ins_k'}->{'value'}=$UpgradesWall->{$sInsKey}->{'ins_k'};
        $UPGrecords->{'WALL_INS'}->{'Info'}->{'ins_k'}->{'units'}="W/mK";
        $UPGrecords->{'WALL_INS'}->{'Info'}->{'thick'}->{'n_t'} = $UpgradesWall->{$sInsKey}->{'n_t'};
        for(my $i=1;$i<=$UpgradesWall->{$sInsKey}->{'n_t'};$i++) {
            $UPGrecords->{'WALL_INS'}->{'Info'}->{'thick'}->{"t_$i"}=$UpgradesWall->{$sInsKey}->{"t_$i"};
        };
    };
    
    if($fIncreaseRSI>0) { # The insulation needs to be increased
        
        # Load the thicknesses of the material
        my @fBoards=();
        
        my $iThick = $UpgradesWall->{$sInsKey}->{'n_t'};
        for(my $i=1;$i<=$iThick;$i++) {
            push(@fBoards,$UpgradesWall->{$sInsKey}->{"t_$i"});
        };
        $iThick--; # Reduce for indexing in PERL
        
        # Determine how many boards are required to meet the goal
        for(my $i=$iThick;$i>=0;$i--) {
            my $ThisRSI=$fBoards[$i]/$UpgradesWall->{$sInsKey}->{'ins_k'};
            my $iThisBoards=0;
            until($fIncreaseRSI<=0) {
                $fIncreaseRSI-=$ThisRSI;
                $iThisBoards++;
            };
            $fIncreaseRSI+=$ThisRSI;
            $iThisBoards--;
            my $j = $i+1;
            $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'Layers'}->{"t_$j"}=$iThisBoards;
            $fInsThick = $fInsThick+($iThisBoards*$fBoards[$i]);
        };
        
        # Record the new wall RSI
        #$UPGrecords->{'WALL_INS'}->{"$house_name"}->{'new_Wall_RSI'}=($fInsThick/$UpgradesWall->{$sInsKey}->{'ins_k'})+$UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_RSI'};
        
        $UPGrecords = setWallCladding($house_name,$fInsThick,$UpgradesWall,$sCurrentClad,$thisHouse,$setPath,$sCladKey,$sInsKey,$UPGrecords);

    };
    
    return $UPGrecords;

};
# ====================================================================
# setNewInfil
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setNewInfil {
    # INPUTS
    # Name of dwelling, % decrease of ACH50, path to the set, HASH holding upgrade data
    my ($house_name,$fThisDecreaseAch,$setPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $OldACH;
    my $NewACH; # The new ACH to achieve at 50 delta_P
    my $OldELA;
    my $NewELA;
    my $OldData1;
    my $OldData2;
    my $OldDeltaPela;
    my $OldCd;
    my $DataLines=0;
    my $FileLine=0;
    my $ThisLine;
    my $recPath = $setPath . "$house_name/";
    
    # Load the aim2 file
    my $AimFile = $recPath . "$house_name.aim";
    my $fid;
    open $fid, $AimFile or die "Could not open $AimFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Determine the blower door data
    while($FileLine<=$#lines) {
        if($lines[$FileLine] !~ m/^(#)/) {$DataLines++;}
        if($DataLines==2) {last;}
        $FileLine++;
    };
    if($FileLine>=$#lines){die "Could not load AIM-2 data\n";}
    $ThisLine = $lines[$FileLine];
    $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split /[,\s]+/, $ThisLine;
    $OldACH = $LineDat[2];
    if((not defined($LineDat[2])) || $OldACH<=0) {die "There was an error reading the AIM-2 blower door data\n";}
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'orig_ACH50'} = $OldACH;
    $OldELA = $LineDat[4];
    if((not defined($LineDat[4])) || $OldELA<=0) {die "There was an error reading the AIM-2 blower door data\n";}
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'orig_ELA'} = $OldELA;
    
    # Determine the new ACH50 and ELA
    $NewACH = $OldACH*(1.0-$fThisDecreaseAch);
    $NewELA = $OldELA*(1.0-$fThisDecreaseAch);
    if($NewACH<0) {
        print "setNewInfil: Warning, $house_name has new ACH50 below 0. Setting to 10% old ACH50\n";
        $NewACH=0.1*$OldACH;
    };
    if($NewELA<0) {
        print "setNewInfil: Warning, $house_name has new ELA below 0. Setting to 10% old ELA\n";
        $NewELA=0.1*$OldELA;
    };
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'new_ACH50'} = $NewACH;
    $UPGrecords->{'AIM_2'}->{"$house_name"}->{'new_ELA'} = $NewELA;
    
    # Get the DeltaPela and Cd
    $OldData1 = $LineDat[0];
    $OldData2 = $LineDat[1];
    $OldDeltaPela = $LineDat[3];
    $OldCd = $LineDat[5];
    
    # Define the line of new data
    my $sNewData = sprintf("%d %d %.2f %d %.2f %.3f\n", $OldData1,$OldData2,$NewACH,$OldDeltaPela,$NewELA,$OldCd);
    $lines[$FileLine] = $sNewData;
    
    # Print the updated AIM-2 file
    open my $out, '>', $AimFile or die "Can't write $AimFile: $!";
    foreach my $ThatData (@lines) {
        print $out $ThatData;
    };
    close $out;

    return $UPGrecords;
};
# ====================================================================
# getDwellingVentilationRate
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getDwellingVentilationRate {
    # INPUT
    my ($house_name,$recPath) = @_;
    
    # OUTPUT
    my $fVentFlow;
    
    # INTERMEDIATES
    my $climate;
    my $swf;
    my $iAdults;
    my $iKids;
    my $fFloor;
    my $ELA;
    my $Height;
    my $fAnnInfil;
    my $fNominalVent;
    
    # Determine the weather and shielding factor
    $climate = getDwellingClimate($house_name,$recPath);
    $swf = getWeatherShieldingFactor($climate);
    
    # Determine the conditioned floor area and occupancy
    ($iAdults,$iKids,$fFloor) = getOccupantsFloorArea($house_name);
    
    # Determine the height and ELA of the dwelling
    ($Height,$ELA) = getDwellingHeightELA($house_name,$recPath);
    
    # Estimate the nominal ventilation rate required
    $fNominalVent = getNominalVentilation($iAdults,$iKids,$fFloor);
    
    # Determine the annual average infiltration
    $fAnnInfil = getAnnualAverageInfil($Height,$ELA,$swf,$fFloor);
    if($fAnnInfil>(($fNominalVent*2.0)/3.0)){$fAnnInfil=(($fNominalVent*2.0)/3.0);} # According to the standard
    
    # The total mechanical ventilation required
    $fVentFlow = $fNominalVent - $fAnnInfil; # Assume Aext = 1 (single-family detached home)
    $fVentFlow = sprintf("%.2f",$fVentFlow);
    
    return $fVentFlow;
};
# ====================================================================
# getVentType
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getVentType {
    # INPUTS
    my ($house_name,$recPath) = @_;
    
    # OUTPUT
    my $iVentType;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    
    # Load the mvnt file
    my $MvntFile = $recPath . "$house_name.mvnt";
    my $fid;
    open $fid, $MvntFile or die "Could not open $MvntFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Load the ventilation data from the file (first item)
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $iVentType = $lines[$FileLine];
    $iVentType =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace

    return $iVentType;
};
# ====================================================================
# setVNTfile
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setVNTfile {
    # INPUTS
    my ($house_name,$recPath,$iVentTypeUPG,$sVentType,$fVentFlowRequired,$UpgradesAIM2,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0;
    my $RVData; # HASH hold the HRV or ERV data
    my $FanPow;

    # Load the mvnt template file
    my $TmpFile = "../templates/template.mvnt";
    my $fid;
    open $fid, $TmpFile or die "Could not open $TmpFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;

    if ($iVentTypeUPG == 2 || $iVentTypeUPG == 4) {	# Upgrade to HRV or ERV
        # Determine which device to use for this house
        my $sDeviceIndex;
        # Load the device data
        $RVData = $UpgradesAIM2->{"$sVentType"};
        # Load the available supply flow rates
        my @FlowRates = @{$RVData->{'flowrate'}};
        @FlowRates = sort { $a <=> $b } @FlowRates; # Sort the flowrates from high to low
        # Find a device that meets the ventilation requirements
        my $i=0;
        until(($FlowRates[$i]>=$fVentFlowRequired) || ($i==$#FlowRates)){$i++;}
        $sDeviceIndex = 'Supply_' . "$FlowRates[$i]";
        $fVentFlowRequired = $FlowRates[$i];

        # Set the CVS system type 
        &replace (\@lines, "#CVS_SYSTEM", 1, 1, "%s\n", "$iVentTypeUPG");	# list CSV as HRV
        
        # Load the device data
        my $hsp_T = $RVData->{"$sDeviceIndex"}->{'hsp_T'};
        my $hsp_SRE = $RVData->{"$sDeviceIndex"}->{'hsp_SRE'};
        my $hsp_P = $RVData->{"$sDeviceIndex"}->{'hsp_P'};
        my $vltt_T = $RVData->{"$sDeviceIndex"}->{'vltt_T'};
        my $vltt_SRE = $RVData->{"$sDeviceIndex"}->{'vltt_SRE'};
        my $vltt_P = $RVData->{"$sDeviceIndex"}->{'vltt_P'};
        my $tre = $RVData->{"$sDeviceIndex"}->{'tre'};
        my $Preheat_P = $RVData->{"$sDeviceIndex"}->{'Preheat_P'};
        my $hsp_LRMT;
        my $vltt_LRMT;
        if($iVentTypeUPG == 4){ # additional ERV data
            $hsp_LRMT = $RVData->{"$sDeviceIndex"}->{'hsp_LRMT'};
            $vltt_LRMT = $RVData->{"$sDeviceIndex"}->{'vltt_LRMT'};
            &insert (\@lines, "#HRV_DATA", 1, 1, 0, "%s\n%s\n", "$hsp_T $hsp_SRE $hsp_LRMT $hsp_P", "$vltt_T $vltt_SRE $vltt_LRMT $vltt_P");	# list efficiency and fan power (W) at cool (0C) and cold (-25C) temperatures. NOTE: Fan power is set to zero as electrical casual gains are accounted for in the elec and opr files. If this was set to a value then it would add it to the incoming air stream and report it to SiteUtilities
        } else {
            &insert (\@lines, "#HRV_DATA", 1, 1, 0, "%s\n%s\n", "$hsp_T $hsp_SRE $hsp_P", "$vltt_T $vltt_SRE $vltt_P");	# list efficiency and fan power (W) at cool (0C) and cold (-25C) temperatures. NOTE: Fan power is set to zero as electrical casual gains are accounted for in the elec and opr files. If this was set to a value then it would add it to the incoming air stream and report it to SiteUtilities
        };
        &insert (\@lines, "#HRV_FLOW_RATE", 1, 1, 0, "%s\n", $fVentFlowRequired);	# supply flow rate
        &insert (\@lines, "#HRV_COOL_DATA", 1, 1, 0, "%s\n", "$tre");	# cool efficiency
        &insert (\@lines, "#HRV_PRE_HEAT", 1, 1, 0, "%s\n", "$Preheat_P");	# preheat watts
        &insert (\@lines, "#HRV_TEMP_CTL", 1, 1, 0, "%s\n", "7 0 0");	# this is presently not used (7) but can make for controlled HRV by temp
        &insert (\@lines, "#HRV_DUCT", 1, 1, 0, "%s\n%s\n", "1 1 2 2 152 0.1", "1 1 2 2 152 0.1");	# use the typical duct values
    }
    elsif ($iVentTypeUPG == 3) {	# fan only ventilation
        # Round flowrate up to nearest multiple of 5
        my $iIncreasingFloe=5;
        until($iIncreasingFloe>$fVentFlowRequired){$iIncreasingFloe+=5;}

        $FanPow = (0.7316*$iIncreasingFloe)+6.6853; # The fan power required. Correlation derived from HVI [W] (inline fans, utility fans, remote fans)
        $FanPow = sprintf("%.2f",$FanPow);
        &replace (\@lines, "#CVS_SYSTEM", 1, 1, "%s\n", "$iVentTypeUPG");	# list CSV as fan ventilation
        &insert (\@lines, "#VENT_FLOW_RATE", 1, 1, 0, "%s\n", "$iIncreasingFloe $iIncreasingFloe $FanPow");	# supply and exhaust flow rate (L/s) and fan power (W) NOTE: Fan power is set to zero as electrical casual gains are accounted for in the elec and opr files. If this was set to a value then it would add it to the incoming air stream and report it to SiteUtilities
        &insert (\@lines, "#VENT_TEMP_CTL", 1, 1, 0, "%s\n", "7 0 0");	# no temp control
        $fVentFlowRequired = $iIncreasingFloe;
    };	# no need for an else
    
    # Print the new mvnt file
    my $MvntFile = $recPath . "$house_name.mvnt";
    unlink $MvntFile; # Clear the old file
    open my $out, '>', $MvntFile or die "Can't write $MvntFile: $!";
    foreach my $ThatData (@lines) {
        print $out $ThatData;
    };
    close $out;
    
    $UPGrecords->{'VNT'}->{"$house_name"}->{'new_CVS'} = $iVentTypeUPG;
    $UPGrecords->{'VNT'}->{"$house_name"}->{'new_Vent_Ls'} = $fVentFlowRequired;
    if($iVentTypeUPG == 3) { $UPGrecords->{'VNT'}->{"$house_name"}->{'new_Vent_Power'} = $FanPow;}

    return $UPGrecords;
};

# ====================================================================
# *********** PRIVATE METHODS ***************
# ====================================================================

# ====================================================================
# *********** CEILING INSULATION SUBROUTINES ***************
# ====================================================================

# ====================================================================
# UpdateCONdata
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub UpdateCONdataCEILING{
    my ($UpgradesSurf,$house_name,$recPath,$thisHouse,$zone,$surfname,$UPGrecords) = @_;
    
    # Intermediates
    my $IndexLayerGaps; # Holds the line index in con file for number of layers and gaps
    my $iMatLayrs;
    #my $iGaps;
    my $surfNum = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'surf_num'};
    #my @GapsData; # Array to hold the air gap data
    my @LayerCon;
    my @LayerThick;
    my @NewCons;
    my $conPath = $recPath . "$house_name" . ".$zone" . ".con";
    my @strNewLayer=(); # String to hold the new layer data
    
    # Outputs
    my $OrigRSI=0;
    my $NewRSI;
    
    # Load this zone's construction file
    my $ConFID;
    open $ConFID, $conPath or die "Could not open $conPath\n";
    my @lines = <$ConFID>; # Pull entire file into an array
    close $ConFID;
    
    # Find the number of layers and gaps for surface
    my $DataLine=0;
    my $FileLine=0;
    until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine==$surfNum)) {
        $FileLine++;
        if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
    };
    $IndexLayerGaps = $FileLine; # Store index to surface number of layers and gaps
    my $ThisLine=$lines[$FileLine]; 
    $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split /[,\s]+/, $ThisLine;
    $iMatLayrs = $LineDat[0];
    #$iGaps = $LineDat[1];

    # If there are air gaps, get the data
    #if($iGaps>0) { 
    #    $DataLine = 0;
    #    until ($lines[$FileLine] =~ m/^(#GAP_POS_AND_RSI)/i) {
    #        $FileLine++;
    #    };
    #    while ($DataLine < $surfNum) {
    #        $DataLine++;
    #        $FileLine++;
    #    };
    #    $ThisLine=$lines[$FileLine]; 
    #    $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    #    @LineDat = split /[,\s]+/, $ThisLine;
    #    for(my $i=0;$i<($iGaps*2);$i++) {
    #        push(@GapsData,$LineDat[$i]);
    #    };
    #    
    # };
    
    # Load the conductivity and thickness of the layer
    $DataLine=0;
    until ($DataLine==$surfNum) {
        if($lines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {$DataLine++;}
        $FileLine++;
    };
    for(my $i=1;$i<=$iMatLayrs;$i++) {
        $ThisLine=$lines[$FileLine]; 
        $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        @LineDat = split /[,\s]+/, $ThisLine;
        push(@LayerCon,$LineDat[0]);
        push(@LayerThick,$LineDat[3]);
        $FileLine++;
    };
    
    # Calculate the RSI of construction
    for (my $i=0;$i<=$#LayerCon;$i++) {
        $OrigRSI+=$LayerThick[$i]/$LayerCon[$i];
    };
    # Store the original RSI value
    $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'original_RSI'} = $OrigRSI;
    
    # Upgrade the insulation if needed
    if($OrigRSI<$UpgradesSurf->{'max_RSI'}) {
        # Determine the amount of insulation to add
        my $AddedRSI = $UpgradesSurf->{'max_RSI'} - $OrigRSI;
        my $Thickness = $UpgradesSurf->{'ins_k'}*$AddedRSI; # Thickness of insulation needed [m]
        
        # Check to see that the thickness is within numerical bounds
        if($Thickness<=0.005) { # TODO: Refine lower bound
            # Required thickness is insignificantly small, skip
            $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'new_RSI'}=$OrigRSI;
            return $UPGrecords;
        };
        # Store the upgrade data for post-processing and record keeping
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'new_RSI'} = $UpgradesSurf->{'max_RSI'};
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'ins_thickness'} = $Thickness; # Thickness of insulation added [m]
        if($Thickness<0.2) {
            my $sStringData = sprintf("%.3f %.1f %.1f %.3f 0 0 0 0 # Added blown in insulation (UPGRADE to RSI %.1f)\n",$UpgradesSurf->{'ins_k'},$UpgradesSurf->{'ins_rho'},$UpgradesSurf->{'ins_Cp'},$Thickness,$UpgradesSurf->{'max_RSI'} );
            push(@strNewLayer,$sStringData);
        } else {
            until($Thickness<=0.2) {
                my $sStringData = sprintf("%.3f %.1f %.1f 0.200 0 0 0 0 # Added blown in insulation (UPGRADE to RSI %.1f)\n",$UpgradesSurf->{'ins_k'},$UpgradesSurf->{'ins_rho'},$UpgradesSurf->{'ins_Cp'},$UpgradesSurf->{'max_RSI'} );
                push(@strNewLayer,$sStringData);
                $Thickness-=0.2;
            };
            if($Thickness>0){
                $Thickness=sprintf("%.4f",$Thickness);
                my $sStringData = sprintf("%.3f %.1f %.1f %.3f 0 0 0 0 # Added blown in insulation (UPGRADE to RSI %.1f)\n",$UpgradesSurf->{'ins_k'},$UpgradesSurf->{'ins_rho'},$UpgradesSurf->{'ins_Cp'},$Thickness,$UpgradesSurf->{'max_RSI'} );
                push(@strNewLayer,$sStringData);
            };
        };

        # Add the new layer to the construction (inside face)
        @NewCons = @lines[0..($FileLine-1)];
        my $iMoreLayers=0;
        foreach my $sThisStringData (@strNewLayer) {
            push(@NewCons,$sThisStringData);
            $iMoreLayers++;
        };
        push(@NewCons,@lines[$FileLine..$#lines]);
        
        # Update number of layers
        $ThisLine=$lines[$IndexLayerGaps];
        $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        @LineDat = split /[,\s]+/, $ThisLine;
        $LineDat[0]+=$iMoreLayers;
        my $NewLayers="";
        foreach my $ThatData (@LineDat) {
            $NewLayers = $NewLayers . "$ThatData ";
        };
        $NewLayers = $NewLayers."\n";
        $NewCons[$IndexLayerGaps] = $NewLayers;
        
        # Write the new construction file
        open my $out, '>', $conPath or die "Can't write $conPath: $!";
        foreach my $ThatData (@NewCons) {
            print $out $ThatData;
        };
        close $out;
        
        # If this surface has boundary condition "ANOTHER", update that con file as well
        if(defined($thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'boundary'})) {
            # Get other zone and surface names
            my $OtherZone = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'boundary'}->{'zone'};
            my $OtherSurf = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfname"}->{'boundary'}->{'surf'};
            
            # Construct path to other con file
            $conPath = $recPath . "$house_name" . ".$OtherZone" . ".con";
            
            # Load the other con file data
            open $ConFID, $conPath or die "Could not open $conPath\n";
            @lines = <$ConFID>; # Pull entire file into an array
            close $ConFID;
            
            # Get the surface number in this zone
            $surfNum = $thisHouse->{"$OtherZone"}->{'Surfaces'}->{"$OtherSurf"}->{'surf_num'};
            
            # Find the index to the layer info
            $DataLine=0;
            $FileLine=0;
            until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine==$surfNum)) {
                $FileLine++;
                if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
            };
            $IndexLayerGaps = $FileLine; # Store index to surface number of layers and gaps
            my $ThisLine=$lines[$FileLine]; 
            $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split /[,\s]+/, $ThisLine;
            $iMatLayrs = $LineDat[0];
            
            # Find the constructions data
            $DataLine=0;
            until ($DataLine==$surfNum) {
                if($lines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {$DataLine++;}
                $FileLine++;
            };
            
            # Reset the NewCon array
            @NewCons=@lines[0..($FileLine-1)];
            @strNewLayer = reverse @strNewLayer;
            foreach my $sThisStringData (@strNewLayer) {
                push(@NewCons,$sThisStringData);
            };
            push(@NewCons,@lines[$FileLine..$#lines]);
            
            # Update the layer info
            $ThisLine=$lines[$IndexLayerGaps];
            $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split /[,\s]+/, $ThisLine;
            $LineDat[0]+=$iMoreLayers;
            $NewLayers="";
            foreach my $ThatData (@LineDat) {
                $NewLayers = $NewLayers . "$ThatData ";
            };
            $NewLayers = $NewLayers."\n";
            $NewCons[$IndexLayerGaps] = $NewLayers;
            
            # Write the new construction file
            open my $out, '>', $conPath or die "Can't write $conPath: $!";
            foreach my $ThatData (@NewCons) {
                print $out $ThatData;
            };
            close $out;
        };
    } else { # Insulation is sufficient already
        $UPGrecords->{'CEIL_INS'}->{"$house_name"}->{"$zone"}->{"$surfname"}->{'new_RSI'}=$OrigRSI;
    };
    
    return $UPGrecords;

}; # END UpdateCONdata
# ====================================================================
# getZoneDataCFG
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
sub getZoneDataCFG {
    my ($rec,$path,$Surf) = @_;
    
    # Intermediates
    my $FileLine=0;
    my $ZoneCount=1;
    
    my $CFGpath = $path . "$rec/$rec.cfg";
    
    # Crack open the cfg file 
    my $cfgFID;
    open $cfgFID, $CFGpath or die "Could not open $CFGpath\n";
    my @lines = <$cfgFID>; # Pull entire file into an array
    close $cfgFID;
    
    ZONE_NUM: while($FileLine<=$#lines){
        until($lines[$FileLine] =~ m/^(\*zon\s)/) {
            $FileLine++;
            if ($FileLine>$#lines) {last ZONE_NUM;}
        };
        $FileLine++;
        my ($zone) = $lines[$FileLine] =~ /$rec\.([^.]+)/;
        $Surf->{"_$rec"}->{$zone}->{'zone_number'} = $ZoneCount;
        $ZoneCount++;
    }; # END ZONE_NUM

    return $Surf;

}; # END getZoneDataCFG
# ====================================================================
# getCNN
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
sub getCNN {
    my ($rec,$path,$SurfRec) = @_;
    
    # Intermediates
    my $FileLine=0;
    my $CurZone = 0;
    my $ThisZone = "";
    
    my $CFGpath = $path . "$rec/$rec.cnn";
    
    # Crack open the cfg file 
    my $cfgFID;
    open $cfgFID, $CFGpath or die "Could not open $CFGpath\n";
    my @lines = <$cfgFID>; # Pull entire file into an array
    close $cfgFID;
    
    SRT_CNN: until($lines[$FileLine] =~ m/^(#CONNECTIONS)/) {
        $FileLine++;
        if ($FileLine>$#lines) {last SRT_CNN;}
    };
    if ($FileLine>$#lines) {die "Could not file connections data in $CFGpath\n";}
    $FileLine++;
    EACH_CNN: until($lines[$FileLine] =~ m/^(#END_CONNECTIONS)/) {
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $lines[$FileLine];
        if($LineDat[0] > $CurZone) { # Connections for new zone
            $CurZone = $LineDat[0];
            foreach my $zonRec (keys (%{$SurfRec})) {
                if($SurfRec->{$zonRec}->{'zone_number'} == $LineDat[0]) {
                    $ThisZone = $zonRec;
                    last;
                };
            };
        };
        
        # Get the name of the current surface connection
        my $CurSurf; #  The name of the current surface
        foreach my $surfs (keys (%{$SurfRec->{"$ThisZone"}->{'Surfaces'}})) { # Find surface key
            if($SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$surfs"}->{'surf_num'} == $LineDat[1]) {
                $CurSurf = $surfs;
                last;
            };
        };
        if (not defined($CurSurf)) {die "Could not find surface name for current surface\n";}

        if($LineDat[2] == 3) { # This surface boundary condition is other
            foreach my $zonRec (keys (%{$SurfRec})) {
                if($SurfRec->{$zonRec}->{'zone_number'} == $LineDat[3]) {
                    foreach my $surfs (keys (%{$SurfRec->{"$zonRec"}->{'Surfaces'}})) {
                        if($SurfRec->{"$zonRec"}->{'Surfaces'}->{"$surfs"}->{'surf_num'} == $LineDat[4]) {
                            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'}->{'zone'} = $zonRec;
                            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'}->{'surf'} = $surfs;
                            last;
                        };
                    };
                    
                    last;
                };
            };
            
        } elsif($LineDat[2] == 0) { # Boundary is exterior
            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'} = 'exterior';
        } elsif($LineDat[2] == 6) { # Boundary is BASESIMP
            $SurfRec->{"$ThisZone"}->{'Surfaces'}->{"$CurSurf"}->{'boundary'} = 'basesimp';
        };
        $FileLine++;
    };


    return $SurfRec;

}; # END getZoneDataCFG
# ====================================================================
# *********** BASEMENT INSULATION SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getBSMTType
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getBSMTType {
    
    my ($house_name,$recPath) = @_;
    
    # Intermediates
    my $FileLine=0;
    
    # Outputs
    my $BsmtIndex;
    
    # Load the cnn file
    my $cnnFile = $recPath . "$house_name.cnn";
    my $cnnfid;
    open $cnnfid, $cnnFile or die "Could not open $cnnFile\n";
    my @lines = <$cnnfid>; # Pull entire file into an array
    close $cnnfid;

    # Navigate to the connections
    SRT_CNN: until($lines[$FileLine] =~ m/^(#CONNECTIONS)/) {
        $FileLine++;
        if ($FileLine>$#lines) {last SRT_CNN;}
    };
    $FileLine++;
    while($FileLine<$#lines) {
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $lines[$FileLine];
        if(($LineDat[2]/1) == 6) { # BASESIMP connection, get the basesimp type
            $BsmtIndex = $LineDat[3];
            last;
        };
        $FileLine++;
    };

    return $BsmtIndex;
}; # END UpdateBSMfile
# ====================================================================
# setBSMfile
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setBSMfile {
    my ($house_name,$recPath,$BsmtIndex,$UpgradesBsmt,$UPGrecords) = @_;
    
    # Intermediates
    my @BSMdata=();
    my $FileLine=0;
    my $OldRSI;
    my $effRSI;
    my $newRSI;
    my $sInsFacing;

    # Outputs
    my $newBSMtype;
    
    # Determine the "new" foundation type
    $newBSMtype = getNewBsmType($BsmtIndex);
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'new_basesimp_code'} = $newBSMtype;
    
    # Load the bsm file
    my $cnnFile = $recPath . "$house_name.bsmt.bsm";
    my $cnnfid;
    open $cnnfid, $cnnFile or die "Could not open $cnnFile\n";
    my @lines = <$cnnfid>; # Pull entire file into an array
    close $cnnfid;
    
    # Scan the bsm file, pull the data
    while ($FileLine<=$#lines) { 
        if(($lines[$FileLine] !~ m/^(#)/) && ($lines[$FileLine] !~ m/^(\*)/)) {
            my $Retrieve = $lines[$FileLine];
            $Retrieve =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            push(@BSMdata,$Retrieve);
        };
        $FileLine++;
    };

    # Get the RSI value
    $OldRSI = $BSMdata[5];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'orig_RSI'} = $OldRSI;
    
    # Get effective wall RSI
    $sInsFacing = getBsmtWallInsLocation($BsmtIndex); # First, determine if the walls are insulated on the inside and outside
    if($sInsFacing =~ m/both/) {
        $effRSI = $OldRSI*2.0;
    } elsif ($sInsFacing =~ m/none/) {
        $effRSI = 0.0;
    } else {
        $effRSI = $OldRSI;
    };
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'orig_eff_RSI'} = $effRSI;
    
    # Store other relevant data for post-processing
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'height'} = $BSMdata[0];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'depth'} = $BSMdata[1];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'length'} = $BSMdata[2];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'width'} = $BSMdata[3];
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'overlap'} = $BSMdata[4];
    
    # Initialize the area of insulation added to basement
    $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'area_ins_added'} = 0.0;
    
    if ($effRSI<$UpgradesBsmt->{'bsmt'}->{'max_RSI'}) { # Increase the insulation
        my $Overlap;
        my $Newdata;
        my $NewEffRSI;
        my $BsmtWallArea;
        $FileLine = 0;
        if(($BsmtIndex == 8) && ($newBSMtype == 12)) { # Need to specify an overlap
            # Assume 0.2 m gap on inside insulation
            $Overlap = $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'depth'} - 0.2;
            until($lines[$FileLine] =~ m/(OVERLAP)/) {$FileLine++;}
            $FileLine++;
            $Newdata = sprintf("%.2f\n",$Overlap);
            $lines[$FileLine] = $Newdata;
        };
        
        # Determine the new RSI input to BASESIMP
        $newRSI = getNewRSIBsmt($BsmtIndex,$newBSMtype,$OldRSI,$UpgradesBsmt->{'bsmt'}->{'max_RSI'});
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'new_RSI'} = $newRSI;
        $sInsFacing = getBsmtWallInsLocation($newBSMtype);
        if($sInsFacing =~ m/both/) {
            $NewEffRSI = $newRSI*2.0;
        } elsif ($sInsFacing =~ m/none/) {
            $NewEffRSI = 0.0;
        } else {
            $NewEffRSI = $newRSI;
        };
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'new_eff_RSI'} = $NewEffRSI;
        
        # Record the area of insulation added
        $BsmtWallArea = (2*($UPGrecords->{'BASE_INS'}->{"$house_name"}->{'width'}+$UPGrecords->{'BASE_INS'}->{"$house_name"}->{'length'}))*$UPGrecords->{'BASE_INS'}->{"$house_name"}->{'height'};
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'area_ins_added'} = $BsmtWallArea;
        
        until($lines[$FileLine] =~ m/(#RSI)/) {$FileLine++;}
        $FileLine++;
        
        $Newdata = sprintf("%.2f\n",$newRSI);
        $lines[$FileLine] = $Newdata;

        # Print the new basesimp file
        open my $out, '>', $cnnFile or die "Can't write $cnnFile: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;

    };
    
    if ($BsmtIndex == $newBSMtype) {$newBSMtype=-1;}
    return ($UPGrecords,$newBSMtype);
};
# ====================================================================
# getNewBsmType
#       This subroutine assigns a new BASESIMP foundation type for insulation 
#       retrofits. It is assumed that any new insulation will be applied to
#       interior foundation walls, and be the full length.
#
# INPUT     The original BASESIMP foundation code (integer)
# OUTPUT    The new BASESIMP foundation code (integer)
# ====================================================================
sub getNewBsmType {
    my $OldIndex = shift @_;
    
    # Outputs
    my $NewIndex;
    
    switch ($OldIndex) {
		case 2		{$NewIndex = 1;}
		case 4	    {$NewIndex = 1;}
		case 6	    {$NewIndex = 96;}
		case 8	    {$NewIndex = 12;}
		case 10	    {$NewIndex = 1;}
		case 15	    {$NewIndex = 14;}
		#case 18	 {$NewIndex = 14;}
        case 71     {$NewIndex = 94;}
        #case 89     {$NewIndex = 111;}
        case 98     {$NewIndex = 93;}
        #case 99     {$NewIndex = ???}
		case 110	{$NewIndex = 69;}
        case 119    {$NewIndex = 22;}
		else		{$NewIndex=$OldIndex;}
	}
    
    return $NewIndex;
};
# ====================================================================
# UpdateCONdataCRAWL
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub UpdateCONdataCRAWL{
    my ($UpgradesSurf,$house_name,$recPath,$thisHouse,$zone,$UPGrecords) = @_;
    
    # Intermediates
    my $IndexLayerGaps; # Holds the line index in con file for number of layers and gaps
    my $iMatLayrs;
    
    my $conPath = $recPath . "$house_name" . ".$zone" . ".con";
    my $strNewLayer; # String to hold the new layer data
    my $bIsConModified = 0;
    my $Thickness = $UpgradesSurf->{'crawl'}->{'max_RSI'}*$UpgradesSurf->{'crawl'}->{'ins_k'}; # Thickness of insulation needed [m]
    
    # Outputs
    my $OrigRSI=0;
    my $NewRSI;
    
    # Load this zone's construction file
    my $ConFID;
    open $ConFID, $conPath or die "Could not open $conPath\n";
    my @lines = <$ConFID>; # Pull entire file into an array
    close $ConFID;
    
    CRAWL_WALL: foreach my $surfs (keys (%{$thisHouse->{"$zone"}->{'Surfaces'}})){
        if(($surfs =~ m/floor/) || ($surfs =~ m/ceiling/)) {next;} # Only upgrade the walls of the crawlspace
        my @LayerCon=();
        my @LayerThick=();
        my @NewCons=();
        my $iInsLayer=0;
        
        # Get the surface number
        my $surfNum = $thisHouse->{"$zone"}->{'Surfaces'}->{"$surfs"}->{'surf_num'};
         # Find the number of layers and gaps for surface
        my $DataLine=0;
        my $FileLine=0;
        until (($lines[$FileLine] !~ m/^(#)/i) && ($DataLine==$surfNum)) {
            $FileLine++;
            if($lines[$FileLine] !~ m/^(#)/i){$DataLine++};
        };
        $IndexLayerGaps = $FileLine; # Store index to surface number of layers and gaps
        my $ThisLine=$lines[$FileLine]; 
        $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $ThisLine;
        $iMatLayrs = $LineDat[0];
        
        # Load the conductivity and thickness of the layer
        $DataLine=0;
        until ($DataLine==$surfNum) {
            if($lines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {$DataLine++;}
            $FileLine++;
        };
        for(my $i=1;$i<=$iMatLayrs;$i++) {
            $ThisLine=$lines[$FileLine]; 
            $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            if($ThisLine =~ m/(insulation)/) {$iInsLayer=$FileLine}; # Locate the layer with insulation, store the line number
            @LineDat = split /[,\s]+/, $ThisLine;
            push(@LayerCon,$LineDat[0]);
            push(@LayerThick,$LineDat[3]);
            $FileLine++;
        };
        
        # Calculate the RSI of construction
        for (my $i=0;$i<=$#LayerCon;$i++) {
            $OrigRSI+=$LayerThick[$i]/$LayerCon[$i];
        };
        # Store the original RSI value
        $UPGrecords->{'BASE_INS'}->{"$house_name"}->{"$zone"}->{"$surfs"}->{'original_RSI'} = $OrigRSI;
        
        # Upgrade the insulation if needed
        if($OrigRSI<$UpgradesSurf->{'crawl'}->{'max_RSI'}) {
            $bIsConModified = 1; # Record that a change to the construction is being made
           
            # Format the new insulation layer
            $strNewLayer = sprintf("%.3f %.1f %.1f %.3f 0 0 0 0 # New crawlspace insulation (UPGRADE to RSI %.1f)\n",$UpgradesSurf->{'crawl'}->{'ins_k'},$UpgradesSurf->{'crawl'}->{'ins_rho'},$UpgradesSurf->{'crawl'}->{'ins_Cp'},$Thickness,$UpgradesSurf->{'crawl'}->{'max_RSI'} );
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{"$zone"}->{"$surfs"}->{'new_RSI'} = $UpgradesSurf->{'crawl'}->{'max_RSI'};
            
            # Add the new layer to the construction (inside face)
            if($iInsLayer==0) { # An additional layer must be added (inside face)
                @NewCons = @lines[0..($FileLine-1)];
                push(@NewCons,$strNewLayer);
                push(@NewCons,@lines[$FileLine..$#lines]);
            
                # Update number of layers
                $ThisLine=$lines[$IndexLayerGaps];
                $ThisLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                @LineDat = split /[,\s]+/, $ThisLine;
                $LineDat[0]++;
                my $NewLayers="";
                foreach my $ThatData (@LineDat) {
                    $NewLayers = $NewLayers . "$ThatData ";
                };
                $NewLayers = $NewLayers."\n";
                $NewCons[$IndexLayerGaps] = $NewLayers;
            } else { # Replace the insulation layer
                @NewCons = @lines;
                $NewCons[$iInsLayer] = $strNewLayer;
            };
            
            # Save changes to the con file
            @lines = @NewCons;

        } else { # Insulation is sufficient already
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'left'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'right'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'front'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            $UPGrecords->{'BASE_INS'}->{"$house_name"}->{'back'}->{"$surfs"}->{'new_RSI'}=$OrigRSI;
            last CRAWL_WALL;
        };
    }; # END CRAWL_WALL

    # Write the new construction file
    if($bIsConModified){
        open my $out, '>', $conPath or die "Can't write $conPath: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    };

    return $UPGrecords;

}; # END UpdateCONdataCRAWL
# ====================================================================
# getBsmtWallInsLocation
#       Determines if the foundation walls are insulated on both-sides 
#       (1) or only on the interior/exterior (0)
#
# INPUT     BsmtIndex: BASESIMP foundation code
# OUTPUT    bInsBothSides: Boolean to indicate if both sides of the 
#                          foundation wall are insulated
# ====================================================================
sub getBsmtWallInsLocation {
    # INPUTS
    my $BsmtIndex = @_;
    
    # OUTPUTS
    my $sWallIns;
    
    switch ($BsmtIndex) {
		case [1,2,4,14,15,19,20,72,73,103,108,111,112,113,119,121,133]	{ $sWallIns = 'inside'; }
		case [6,8,18,71,89,98,99,110,129]	{ $sWallIns = 'outside'; }
        case 10	{ $sWallIns = 'none'; }
		else    { $sWallIns = 'both'; }
	}
    
    return $sWallIns;
};
# ====================================================================
# getEffectiveBsmtRSI
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub setBsmCNN {
    my ($house_name,$recPath,$NewBSM) = @_;
    # TODO: TEST SUBROUTINE
    # Intermediates
    my $FileLine=0;
    
    # Outputs
    my $BsmtIndex;
    
    # Load the cnn file
    my $cnnFile = $recPath . "$house_name.cnn";
    my $cnnfid;
    open $cnnfid, $cnnFile or die "Could not open $cnnFile\n";
    my @lines = <$cnnfid>; # Pull entire file into an array
    close $cnnfid;

    # Navigate to the connections
    SRT_CNN: until($lines[$FileLine] =~ m/^(#CONNECTIONS)/) {
        $FileLine++;
        if ($FileLine>$#lines) {last SRT_CNN;}
    };
    $FileLine++;
    while($FileLine<$#lines) {
        my $Retrieve = $lines[$FileLine];
        $Retrieve =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split /[,\s]+/, $Retrieve;
        if(($LineDat[2]/1) == 6) { # BASESIMP connection, get the basesimp type
            my $NewData="";
            for (my $i=0;$i<=$#LineDat;$i++) {
                if($i != 3) {
                    $NewData = $NewData . "$LineDat[$i] ";
                } else {
                    $NewData = $NewData . "$NewBSM ";
                };
            };
            $NewData = $NewData . "\n";
            $lines[$FileLine] = $NewData;
        };
        $FileLine++;
    };
    
    # Print the new basesimp file
    open my $out, '>', $cnnFile or die "Can't write $cnnFile: $!";
    foreach my $ThatData (@lines) {
        print $out $ThatData;
    };
    close $out;
    
    return;
};
# ====================================================================
# getNewRSIBsmt
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
#           pdf: probability distribution function HASH (refen
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getNewRSIBsmt {
    # INPUTS
    my ($BsmtIndex,$newBSMtype,$OldRSI,$NewRSI) = @_;
    
    # OUTPUTS
    my $EquivRSI = $NewRSI;
    
    # INTERMEDIATES
    my $sOldFacing;
    my $sNewFacing;
    
    $sOldFacing = getBsmtWallInsLocation($BsmtIndex);
    $sNewFacing = getBsmtWallInsLocation($newBSMtype);
    
    if (($sNewFacing =~ m/both/) && (($sOldFacing =~ m/outside/) || ($sOldFacing =~ m/both/))) {
        $EquivRSI = ($OldRSI+$NewRSI)/2.0;
    };

    return $EquivRSI;
};
# ====================================================================
# *********** AIRTIGHTNESS SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getDefaultACH
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getDefaultACH {
    # INPUT
    my $Aim2Type = shift @_;

    # OUTPUT
    my $DefaultACH;
    
    switch ($Aim2Type) {
		case 3		{ $DefaultACH = 10.35; }
        case 4		{ $DefaultACH = 4.55; }
        case 5		{ $DefaultACH = 3.57; }
        case 6		{ $DefaultACH = 1.50; }
		else		{ die "Invalid default AIM-2 type $Aim2Type\n"; }
	}
    
    return $DefaultACH;
};
# ====================================================================
# getDwellingClimate
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getDwellingClimate {
    # INPUT
    my ($house_name,$recPath) = @_;
    
    # OUTPUT
    my $climate;
    
    # INTERMEDIATES
    my $FileLine=0;
    
    # Load the cfg file
    my $CFGFile = $recPath . "$house_name.cfg";
    my $fid;
    open $fid, $CFGFile or die "Could not open $CFGFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Find the climate data
    until($lines[$FileLine] =~ m/^(\*clm)/) {$FileLine++;}
    
    # Parse out the climate zone
    $climate  = $lines[$FileLine];
    $climate =~ s/^\s+|\s+$//g;
    $climate =~ s/^.*[\/\\]//;
    $climate =~ s/\.[^.]+$//;

    return $climate;
};
# ====================================================================
# getWeatherShieldingFactor
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getWeatherShieldingFactor {
    # INPUT
    my ($climate) = @_;
    
    # OUTPUT
    my $swf;
    
    switch ($climate) {
		case "can_calgary"	    { $swf = 0.73; }
		case "can_montreal"	    { $swf = 0.60; }
        case "can_vancouver"	{ $swf = 0.57; }
        case "can_halifax"	    { $swf = 0.63; }
        case "can_toronto"	    { $swf = 0.58; }
		else		{ die "Sorry. Shielding and weather factor could not be found for $climate\nConsider adding value to subroutine getWeatherShieldingFactor in the UpgradeCity module.\n"; }
	}

    return $swf;
};
# ====================================================================
# getOccupantsFloorArea
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getOccupantsFloorArea {
    # INPUTS
    my ($house_name) = @_;
    
    # OUTPUTS
    my $iAdults;
    my $iKids;
    my $fFloor;
    
    # INTERMEDIATES
    my $FileLine=0;
    my $sHeader;
    my $iIndAdult;
    my $iIndKids;
    my $iIndArea;
    
    # Load in CHREM NN data
    my $NNinPath = '../NN/NN_model/ALC-Inputs-V2.csv';
    my $fid;
    open $fid, $NNinPath or die "Could not open $NNinPath\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Process the header
    $sHeader = $lines[0];
    my @sHead = split /[,]+/, $sHeader;
    for(my $i=0;$i<=$#sHead;$i++) {
        if($sHead[$i] =~ m/(Num_of_Adults)/) {
            $iIndAdult=$i;
        } elsif($sHead[$i] =~ m/(Num_of_Children)/) {
            $iIndKids=$i;
        } elsif($sHead[$i] =~ m/^(Area)/) {
            $iIndArea=$i;
        };
        if((defined $iIndAdult) && (defined $iIndKids) && (defined $iIndArea)) {last;}
    };
    if((not defined $iIndAdult) || (not defined $iIndKids) || (not defined $iIndArea)) {
        die "getOccupantsFloorArea: Could not index headers for $house_name\n";
    };
    
    
    until($lines[$FileLine] =~ m/($house_name)/) {
        $FileLine++;
        if($FileLine>$#lines){die "Could not load the NN data for $house_name\n";}
    };
    
    # Parse the data
    $lines[$FileLine] =~ s/^\s+|\s+$//g;
    my @Parsed = split /[,]+/, $lines[$FileLine];
    
    # Get the data of interest
    $iAdults = $Parsed[$iIndAdult];
    $iKids   = $Parsed[$iIndKids];
    $fFloor  = $Parsed[$iIndArea];

    return($iAdults,$iKids,$fFloor);
};
# ====================================================================
# getDwellingHeightELA
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     house_name: Dwelling record code
#           recPath: path to the record folder
# OUTPUT    iVentType: CVS_SYSTEM: Central Ventilation System (CVS) type (1=None, 2=HRV, 3=Fans with no heat recovery, 4=ERV)
# ====================================================================
sub getDwellingHeightELA {
    # INPUTS
    my ($house_name,$recPath) = @_;
    
    # OUTPUTS
    my $Height;
    my $ELA;
    
    # INTERMEDIATES
    my $DataLine=0;
    my $FileLine=0;
    my $iAirType;
    my $sAirType;
    
    # Load the AIM-2 file
    my $Aim2File = $recPath . "$house_name.aim";
    my $fid;
    open $fid, $Aim2File or die "Could not open $Aim2File\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Determine the airtightness type
    until($DataLine == 2){
        if($lines[$FileLine] !~ m/^(#)/){$DataLine++;}
        $FileLine++;
    }
    $FileLine--;
    $sAirType = $lines[$FileLine];
    $FileLine++;
    $sAirType =~ s/^\s+|\s+$//g;
    ($iAirType) = split(/\s+/, $sAirType); 
    
    
    # Determine the ELA
    if($iAirType>2){ # Default leakage. Get the default ELA
        $ELA = getDefaultELA($iAirType);
    } else { # Read the ELA from the input file
        my @LineDat = split /[,\s]+/, $sAirType;
        $ELA = $LineDat[4]/10000.0;
    };
    
    # Get the height of the eaves
    until($DataLine == 5){
        if($lines[$FileLine] !~ m/^(#)/){$DataLine++;}
        $FileLine++;
    }
    $FileLine--;
    $Height = $lines[$FileLine];
    $Height =~ s/^\s+|\s+$//g;
    
    return($Height,$ELA);
};
# ====================================================================
# getDefaultELA
#       This subroutine randomly assigns an occupancy start state for the 
#       dwelling.
#
# INPUT     numOcc: number of occupants in the house
# OUTPUT    StartActive: number of active occupants 
# ====================================================================
sub getDefaultELA {
    # INPUT
    my $Aim2Type = shift @_;

    # OUTPUT
    my $DefaultELA;
    
    switch ($Aim2Type) {
		case 3		{ $DefaultELA = 0.11086; }
        case 4		{ $DefaultELA = 0.07292; }
        case 5		{ $DefaultELA = 0.06310; }
        case 6		{ $DefaultELA = 0.03423; }
		else		{ die "Invalid default AIM-2 type $Aim2Type\n"; }
	}
    
    return $DefaultELA;
};
# ====================================================================
# getNominalVentilation
#       This subroutine estimates the nominal ventilation requirement
#       of the dwelling based on number of adults and children. 
#       The required ventilation rate is calculated using ASHRAE 
#       Standard 62.2-2016.
#
# INPUT     iAdults: number of adults in the house
#           iKids: number of children in the house
#           fFloor: Heated floor area [m2]
# OUTPUT    fNominalVent: Total ventilation required for dwelling [L/s]
# ====================================================================
sub getNominalVentilation {
    # INPUTS
    my ($iAdults,$iKids,$fFloor) = @_;
    
    # OUTPUT
    my $fNominalVent;
    
    # INTERMEDIATES
    my $iBedrooms;
    
    # Estimate the number of bedrooms in the dwelling based on occupancy
    # First, assume one bedroom per occupants
    $iBedrooms = $iAdults+$iKids;
    # If there are at least 2 adults, assume one couple shares a room
    if($iAdults>1){$iBedrooms--};
    
    # Calculate the required nominal ventilation
    $fNominalVent = (0.15*$fFloor) +(3.5*($iBedrooms+1));
    
    return $fNominalVent;
}
# ====================================================================
# getAnnualAverageInfil
#       This subroutine estimates the average annual infiltration rate
#       This rate is calculated using ASHRAE Standard 62.2-2016.
#
# INPUT     Height: Vertical distance between the lowest and highest
#                   point in the pressure boundary above grade [m]
#           ELA: Effective leakage area [m2]
#           swf: weather and sheilding factor
#           fFloor: Heated floor area [m2]
# OUTPUT    fAnnInfil: Annual average infiltration rate [L/s]
# ====================================================================
sub getAnnualAverageInfil {
    # INPUTS
    my ($Height,$ELA,$swf,$fFloor) = @_;
    
    # OUTPUT
    my $fAnnInfil;
    
    # INTERMEDIATES
    my $NL;
    
    # Calculate the normalized leakage
    $NL = (1000.0*($ELA/$fFloor))*(($Height/2.5)**0.4);
    
    # Calculate the average annual infiltration rate
    $fAnnInfil = ($NL*$swf*$fFloor)/1.44;
    
    return $fAnnInfil;
};
# ====================================================================
# getVentFlowRate
#       This subroutine estimates the average annual infiltration rate
#       This rate is calculated using ASHRAE Standard 62.2-2016.
#
# INPUT     Height: Vertical distance between the lowest and highest
#                   point in the pressure boundary above grade [m]
#           ELA: Effective leakage area [m2]
#           swf: weather and sheilding factor
#           fFloor: Heated floor area [m2]
# OUTPUT    fAnnInfil: Annual average infiltration rate [L/s]
# ====================================================================
sub getVentFlowRate {
    # INPUTS
    my ($house_name,$recPath,$iVentTypeORG) = @_;
    
    # OUT
    my $fVentFlow;
    
    # INTERMEDIATES
    my $FileLine=0;
    my $DataLine=0;
    my $StopLine;
    
    # Open the mvnt file (again likely...)
    my $MvntFile = $recPath . "$house_name.mvnt";
    my $fid;
    open $fid, $MvntFile or die "Could not open $MvntFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Index the location of the ventilation flowrate
    if(($iVentTypeORG == 2) || ($iVentTypeORG == 4)) {
        $StopLine = 4;
    } elsif($iVentTypeORG == 3) {
        $StopLine = 2;
    } else {die"getVentFlowRate: Invalid ventilation system type $iVentTypeORG\n";}
    until($DataLine == $StopLine) {
        if($lines[$FileLine] !~ m/^(#)/) {$DataLine++;}
        $FileLine++;
    };
    $FileLine--;
    
    # Read the ventilation rate (L/s)
    $lines[$FileLine] =~ s/^\s+|\s+$//g;
    my @LineDat = split /[,\s]+/, $lines[$FileLine];
    $fVentFlow = $LineDat[0];
    
    return $fVentFlow;
};

# ====================================================================
# *********** DH SYSTEM SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getHVACdata
#       This subroutine opens the dwelling HVAC file, determines the
#       current system type, and store the data in the upgrade HASH
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub getHVACdata {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $iSystems; # Integer holding number of HVAC systems
    my $fAltitude; # Altitude of system [m]

    # Load the mvnt file
    my $HVACFile = $recPath . "$house_name/$house_name.hvac";
    my $fid;
    open $fid, $HVACFile or die "getHVACdata: Could not open $HVACFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Get the number of HVAC systems present
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split ' ', $lines[$FileLine];
    $iSystems = $LineDat[0];
    $fAltitude = $LineDat[1];
    $FileLine++;
    # Store number of HVAC systems
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'Num_HVAC_Sys'} = $iSystems;
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'altitude'} = $fAltitude;
    
    # Get the HVAC system data
    for(my $i=1;$i<=$iSystems;$i++) {
        my $sSysType; # HVAC system type
        my $iNumZones;   # Number of zones serviced
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split ' ', $lines[$FileLine];
        $FileLine++;
        
        # What type of system this is
        if($LineDat[0] == 1) {
            $sSysType = 'furnace';
        } elsif($LineDat[0] == 2) {
            $sSysType = 'boiler';
        } elsif($LineDat[0] == 7) {
            $sSysType = 'AC_HP';
        } elsif($LineDat[0] == 3) {
            $sSysType = 'baseboards';
        } elsif($LineDat[0] == 8) {
            $sSysType = 'GSHP';
            print "getHVACdata: Record $house_name, warning record has GSHP system. This type is not handled by Upgrade script\n";
        } elsif($LineDat[0] == 9) {
            $sSysType = 'GCEP';
             print "getHVACdata: Record $house_name, warning record has GCEP system. This type is not handled by Upgrade script\n";
        } else {
            die "getHVACdata: Record $house_name, Unrecognized HVAC system $LineDat[0]. Should be 1,3 or 7,8,9\n";
        };
        #if($LineDat[1] != 1) {die "Record $house_name: HVAC has secondary system $LineDat[1]\n";}
        if($LineDat[1] == 1) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'priority'} = 'primary';
        } elsif ($LineDat[1] == 2) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'priority'} = 'secondary';
        } else {
            die "getHVACdata: Record $house_name, unrecognized system priority $LineDat[1]\n";
        };
        
        # How many zones are serviced
        $iNumZones = $LineDat[2];
        $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'Num_Zones_Served'} = $iNumZones;
        
        # Get the system data
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        @LineDat = split ' ', $lines[$FileLine];
        $FileLine++;
        
        if(($sSysType =~ m/furnace/) || ($sSysType =~ m/boiler/)) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'Type'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'energy_src'} = $LineDat[1];
            my $iData = 2;
            for(my $j=1;$j<=$iNumZones;$j++){
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'Zone_num'} = $LineDat[$iData];
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'distribution'} = $LineDat[$iData+1];
                $iData = $iData+2;
            };
            $iData--;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'heating_capacity_W'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'efficiency'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'auto_circulation_fan'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'estimate_fan_power'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'draft_fan_power'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'pilot_power'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'duct_system_flag'} = $LineDat[$iData];

        } elsif(($sSysType =~ m/AC_HP/) || ($sSysType =~ m/GSHP/) || ($sSysType =~ m/GCEP/)) {
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'heating_or_cooling'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'Type'} = $LineDat[1];
            my $iData = 2;
            for(my $j=1;$j<=$iNumZones;$j++){
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'Zone_num'} = $LineDat[$iData];
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'distribution'} = $LineDat[$iData+1];
                $iData = $iData+2;
            };
            
            # Get the capacity and COP
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            my @LineDat = split ' ', $lines[$FileLine];
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'capacity_W'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'COP'} = $LineDat[1];
            
            # Get fan info
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $lines[$FileLine];
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'flow_rate'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'flow_at_rated'} = $LineDat[1];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_mode'} = $LineDat[2];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_position'} = $LineDat[3];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_power'} = $LineDat[4];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'outdoor_fan_power'} = $LineDat[5];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_power_auto_mode'} = $LineDat[6];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_pos_at_rated'} = $LineDat[7];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'circ_fan_power_at_rated'} = $LineDat[8];
            
            # Get sensible heat ratio and economizer type
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $lines[$FileLine];
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'sensible_heat_ratio'} = $LineDat[0];
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'economizer_type'} = $LineDat[1];

        } elsif($sSysType =~ m/baseboards/) {
            my $iData = 0;
            for(my $j=1;$j<=$iNumZones;$j++){
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'Zone_num'} = $LineDat[$iData];
                $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{"Zone_$j"}->{'distribution'} = $LineDat[$iData+1];
                $iData = $iData+2;
            };
            $iData--;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'heating_capacity_W'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'efficiency'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'auto_circulation_fan'} = $LineDat[$iData];
            $iData++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{"$sSysType"}->{'estimate_fan_power'} = $LineDat[$iData];
        };

    };

    return $UPGrecords;
};
# ====================================================================
# getDHWdata
#       This subroutine opens the dwelling DHW file, determines the
#       current system type, and store the data in the upgrade HASH
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub getDHWdata {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $DataLine = 0; # Number of lines with data read
    my $iTanks; # Integer holding number of tanks
    my $BDCmult; # BCD multiplier

    # Load the dhw file
    my $DHWFile = $recPath . "$house_name/$house_name.dhw";
    my $fid;
    open $fid, $DHWFile or die "Could not open $DHWFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Get the number of tanks present
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $FileLine++;
    $DataLine++; # Skip file version
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    my @LineDat = split ' ', $lines[$FileLine];
    $iTanks = $LineDat[0];
    $FileLine++;
    $DataLine++;
    # Store number of tanks
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'Num_Tanks'} = $iTanks;
    
    # Get the BCD multiplier
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $FileLine++;
    $DataLine++; # Skip the number of occupants
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    @LineDat = split ' ', $lines[$FileLine];
    $BDCmult = $LineDat[0];
    $FileLine++;
    $DataLine++;
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'BCD_Mult'} = $BDCmult;
    
    # Supply temperature (The supply temperature is hard coded to 60oC in ESP-r)
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $FileLine++;
    $DataLine++;
    $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'T_supply'} = 60.0;

    
    # Get the tank data
    my @sDHWKeys = qw(DHW_zone energy_src tank_type fDOEEF fHeatInjectorPower fPilotEnergyRate fTankSize fTemperatureBand fBlanketRSI);
    for(my $i=1;$i<=$iTanks;$i++) { # For each tank
        foreach my $dataa (@sDHWKeys) {
            my $ThisDHWdata;
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $lines[$FileLine];
            $ThisDHWdata = $LineDat[0];
            $DataLine++;
            $FileLine++;
            $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{"$dataa"}->{'DHW_zone'} = $ThisDHWdata;
        };
    };

    return $UPGrecords;
};
# ====================================================================
# setHVACfileDH
#       This subroutine removes the heating system from the .hvac
#       file
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub setHVACfileDH {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $iSystems; # Integer holding number of HVAC systems
    my $fAltitude; # Altitude of system [m]
    my $iLineTop; # Marks the upper boundary of data to be retained
    my $iNewSystems;
    my @sNewHVAC;

    # Load the hvac file
    my $HVACFile = $recPath . "$house_name/$house_name.hvac";
    my $fid;
    open $fid, $HVACFile or die "Could not open $HVACFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Load number of HVAC systems
    $iSystems = $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'Num_HVAC_Sys'};
    $fAltitude = $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'altitude'};
    $iNewSystems = $iSystems;
    
    # Get the top of the hvac file
    until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
    $iLineTop = $FileLine;
    $FileLine++;
    @sNewHVAC = @lines[0..$iLineTop]; # Store the top of the hvac file
    
    # Begin cycling through the hvac systems, removing heating
    for(my $i=1;$i<=$iSystems;$i++) {
        my $iSysType;
        my $ThisHVACstart = $FileLine; # marks the start of this HVAC system data
        my $iTHisData = 0; # Data lines read in for this HVAC system
        my $iThisNumData = 0; # Number of data lines for this hvac type
        # Get the info for this system
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
        $lines[$FileLine] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
        my @LineDat = split ' ', $lines[$FileLine];
        $FileLine++;
        $iTHisData++;
        $iSysType = $LineDat[0];

        if (($iSysType == 1) || ($iSysType == 2) || ($iSysType == 3)) { # Furnace or baseboard. Remove
            $iThisNumData = 2; # Both furnaces and baseboards have only 2 data lines
            until($iTHisData == $iThisNumData) {
                if ($lines[$FileLine] !~ m/^(#)/) {$iTHisData++;}
                $FileLine++;
            };

            # Decrement the number of HVAC systems
            $iNewSystems--;
            
        } elsif ($iSysType == 7) { # air-source heat pump
            my $iUnitFunction;
        
            # Determine if this heating or cooling
            until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;}
            my $DummyLine = $lines[$FileLine];
            $DummyLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @LineDat = split ' ', $DummyLine;
            $iUnitFunction = $LineDat[0];
            
            if($iUnitFunction == 2) { # Cooling
                $iThisNumData = 9;
                my $ThisHVACstop;
                until($iTHisData == $iThisNumData) {
                    if ($lines[$FileLine] !~ m/^(#)/) {$iTHisData++;}
                    $FileLine++;
                };
                
                # Grab the control data
                $DummyLine = $lines[$FileLine-1];
                $DummyLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                @LineDat = split ' ', $DummyLine;
                my $iCoolCtrl = $LineDat[1];
                $lines[$FileLine-1] = sprintf("0 %d # heating_control_function cooling_control_function (in CTL file)\n", $iCoolCtrl);
                
                # Add this system to the new hvac file
                $ThisHVACstop = $FileLine;
                push(@sNewHVAC,@lines[$ThisHVACstart..$ThisHVACstop]); # Add the cooling system to the new hvac file
                
            } elsif($iUnitFunction == 1) { # Heating
                $iThisNumData = 5;
                until(($lines[$FileLine] !~ m/^(#)/) || ($iTHisData == $iThisNumData)) {
                    if ($lines[$FileLine] !~ m/^(#)/) {$iTHisData++;}
                    $FileLine++;
                };
                # Decrement the number of HVAC systems
                $iNewSystems--;
            } else {
                die "setHVACfileDH: Record $house_name, unknown heat pump unit function $iUnitFunction\n";
            }; 

        } else {
            die "setHVACfileDH: Unrecognized HVAC system $iSysType. Should be 1,3 or 7\n";
        };

    
    }; # End of HVAC systems loop
    
    # Update the number of hvac systems
    $sNewHVAC[$iLineTop] = sprintf("%d %.2f # number of systems and altitude (m)\n", $iNewSystems, $fAltitude);
    push(@sNewHVAC,"\n");

    # Print the new hvac file
    PRINT_HVAC: {
        unlink $HVACFile; # Clear old file
        open my $out, '>', $HVACFile or die "Can't write $HVACFile: $!";
        foreach my $ThatData (@sNewHVAC) {
            print $out $ThatData;
        };
        close $out;
    };

    return 1;
};
# ====================================================================
# setDHWfileDH
#       This subroutine removes the dhw system from the .dhw
#       file
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub setDHWfileDH {
    # INPUTS
    my ($house_name,$recPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine=0; # Index the file line
    my $DataLine=0;
    my $iTanks; # Integer holding number of tanks

    # Load the dhw file
    my $DHWFile = $recPath . "$house_name/$house_name.dhw";
    my $fid;
    open $fid, $DHWFile or die "Could not open $DHWFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Load the number of tanks
    $iTanks = $UPGrecords->{'DH_SYSTEM'}->{"$house_name"}->{'DHW'}->{'Num_Tanks'};
    
    # FFWD over the header data
    until($DataLine == 5) {
        if ($lines[$FileLine] !~ m/^(#)/) {$DataLine++;}
        $FileLine++;
    };

    # Loop through each tank and update the fuel and tank type
    for (my $i=1;$i<=$iTanks;$i++) {
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;} # Zone with tank
        $FileLine++;
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;} # Energy source
        $lines[$FileLine] = sprintf("7 # Fictitious fuel\n");
        $FileLine++;
        until($lines[$FileLine] !~ m/^(#)/) {$FileLine++;} # Tank type
        $lines[$FileLine] = sprintf("21 # Fictitious tank\n");
        $FileLine++;
        
        my $iSkip = 0;
        
        until(($iSkip == 6) || ($FileLine == ($#lines-1))) {
            if($lines[$FileLine] !~ m/^(#)/) {$iSkip++;}
            $FileLine++;
        };
    };

    # Print the new hvac file
    PRINT_DHW: {
        unlink $DHWFile; # Clear old file
        open my $out, '>', $DHWFile or die "Can't write $DHWFile: $!";
        foreach my $ThatData (@lines) {
            print $out $ThatData;
        };
        close $out;
    };

    return 1;
};
# ====================================================================
# setCFGnoDHW
#       This subroutine removes the dhw system from the .cfg
#       file
#
# INPUT     house_name: name of the dwelling of interest
#           setPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub setCFGnoDHW {
    # INPUTS
    my $house_name = shift;
    my $setPath = shift;
    
    # INTERMEDIATES
    my $FileLine = 0; # File indexer
    my @NewLines=();
    
    # Load the cfg file
    my $CFGFile = $setPath . "$house_name/$house_name.cfg";
    my $fid;
    open $fid, $CFGFile or die "setCFGnoDHW: Could not open $CFGFile\n";
    my @lines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # Delete the old cfg file
    unlink $CFGFile;
    
    # Scan the cfg file and remove the DHW reference
    until ($lines[$FileLine] =~ m/^(\*dhw)/) { # FFWD to the DHW line
        $FileLine++;
        if($FileLine>$#lines) {die "setCFGnoDHW: Could not find *dhw for $house_name.cfg\n";}
    };
    
    # Store the top half of the cfg file
    @NewLines = @lines[0..($FileLine-1)];
    if($NewLines[$#NewLines] =~ m/^(#DHW)/) {pop @NewLines;} # Remove the comment for DHW if it is there
    
    # Append the rest of the file
    $FileLine++;
    push(@NewLines,@lines[$FileLine..$#lines]);
    
    # Print the new cfg file
    DHWCFG: {
        open my $out, '>', $CFGFile or die "setCFGnoDHW: Can't write $CFGFile: $!";
        foreach my $ThatData (@NewLines) {
            print $out $ThatData;
        };
        close $out;
    };
    
    # Remove the dhw file
    my $OldDHW = $setPath . "$house_name/$house_name.dhw";
    unlink $OldDHW;

    return 1;
}

# ====================================================================
# *********** GLAZING SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getWindowCodes
#       Retrieves the CHREM 3-digit window codes for each glazing
#       surface
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub getWindowCodes {
    # Inputs
    my ($house_name,$setPath,$Zones_ref) = @_;
    my @ZonesWithGlz = @$Zones_ref;
    
    # Output
    my $ZonesGlz;

    # Interrogate the con file for zones with glazing
    foreach my $zones (@ZonesWithGlz) {
        # Set the path to the constructions file
        my $thisCONpath = $setPath . "$house_name/$house_name." . "$zones.con";
        
        # File indexers
        my $DataLine=0;
        my $FileLine=0;
        
        # Open and slurp the file
        my $ConFID;
        open $ConFID, $thisCONpath or die "Could not open $thisCONpath\n";
        my @CONlines = <$ConFID>; # Pull entire file into an array
        close $ConFID;
    
        # Get layer and gap data
        until ($CONlines[$FileLine] !~ m/^(#)/i) { # FFWD past header comments
            $FileLine++;
        };
        while ($CONlines[$FileLine] !~ m/^(#)/i) { # Scan the first block of data
            $DataLine++;
            if($CONlines[$FileLine] =~ m/aper{1}/) {
                my $thisdata = $CONlines[$FileLine];
                $thisdata =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
                my @LineDat = split /[(#)\s]+/, $thisdata;
                
                # Get surface type and parent. Record number of gaps and layers
                my @Dat2 = split /[-]+/, $LineDat[2];
                my $parent = "$Dat2[0]";
                
                # Determine the 3-digit window code
                @Dat2 = split /[_]+/, $LineDat[3];
                $ZonesGlz->{$zones}->{$parent}->{'aper'}->{'glaze_type'}=substr $Dat2[1], 0,1;
                $ZonesGlz->{$zones}->{$parent}->{'aper'}->{'coating'}=substr $Dat2[1], 1,1;
                my $gap_fill = substr $Dat2[1], 2,1;
                my($GasFill,$GapWidthCode) = getGasFillWidth($gap_fill);
                $ZonesGlz->{$zones}->{$parent}->{'aper'}->{'fill_gas'}=$GasFill;
                $ZonesGlz->{$zones}->{$parent}->{'aper'}->{'gap_width_code'}=$GapWidthCode;
            };
            $FileLine++;
            if($FileLine>$#CONlines) {die "upgradeGLZ: Record $house_name, could not find end of layer and gaps data\n";}
        };
    };
    
    return $ZonesGlz;
};
# ====================================================================
# getGasFillWidth
#       Converts from CSDDRD 3-digit window code to Nikoofard's
#       4-digit code
#
# INPUT     gap_fill: The gap thickness and fill gas code
# OUTPUT    GasFill: The gas fill code (0=air, 1=argon)
#           GapWidth: Gap width code (0=13mm, 1=9mm, 2=6mm)
# ====================================================================
sub getGasFillWidth {
    # Inputs
    my $gap_fill = shift @_;
    
    # Outputs
    my $GasFill;
    my $GapWidth;
    
    switch ($gap_fill) {
    
        case 0 {
            $GasFill=0;
            $GapWidth=0;
        }
        case 1 {
            $GasFill=0;
            $GapWidth=1;
        }
        case 2 {
            $GasFill=0;
            $GapWidth=2;
        }
        case 3 {
            $GasFill=1;
            $GapWidth=0;
        }
        case 4 {
            $GasFill=1;
            $GapWidth=1;
        }
        else {die "getGasFillWidth: $gap_fill is not a valide gap_fill code in the CSDDRD\n";}
    };
    return($GasFill,$GapWidth);
}
# ====================================================================
# setNewWindows
#       Applies the window upgrades to the ESP-r input files
#
# INPUT     gap_fill: The gap thickness and fill gas code
# OUTPUT    GasFill: The gas fill code (0=air, 1=argon)
#           GapWidth: Gap width code (0=13mm, 1=9mm, 2=6mm)
# ====================================================================
sub setNewWindows {
    # Inputs
    my ($house_name,$setPath,$UpgradesWindow,$UPGglaze) = @_;
    
    # Intermediates
    # Glazing data
    my $NewGlzLayers = $UpgradesWindow->{'numLayers'};
    my $NewGlzGaps = $UpgradesWindow->{'numGaps'};
    my $NewGlzDesc = $UpgradesWindow->{'description'};

    my $NewGlzEMin = $UpgradesWindow->{'EMIS'}->{'inside'};
    my $NewGlzEMout = $UpgradesWindow->{'EMIS'}->{'outside'};
    my $NewGlzSLRin = $UpgradesWindow->{'SLR_ASB'}->{'inside'};
    my $NewGlzSLRout = $UpgradesWindow->{'SLR_ASB'}->{'outside'};
    
    # Frame data
    my $NewFrmLayers = $UpgradesWindow->{'frame'}->{'numLayers'};
    my $NewFrmGaps = $UpgradesWindow->{'frame'}->{'numGaps'};
    my $NewFrmDesc = $UpgradesWindow->{'frame'}->{'description'};
    
    my $NewFrmEMin = $UpgradesWindow->{'frame'}->{'EMIS'}->{'inside'};
    my $NewFrmEMout = $UpgradesWindow->{'frame'}->{'EMIS'}->{'outside'};
    my $NewFrmSLRin = $UpgradesWindow->{'frame'}->{'SLR_ASB'}->{'inside'};
    my $NewFrmSLRout = $UpgradesWindow->{'frame'}->{'SLR_ASB'}->{'outside'};
    
    # For each zone with new glazing
    ZONAL: foreach my $zones (keys (%{$UPGglaze->{"$house_name"}})) {
        # Set the path to the constructions file
        my $thisCONpath = $setPath . "$house_name/$house_name." . "$zones.con";
        
        # Set the path to the transparent material constructions file
        my $thisTMCpath = $setPath . "$house_name/$house_name." . "$zones.tmc";
        
        #### Updating the Construction File ####
        #=======================================
        ########################################
        # Open and slurp the construction file
        my $ConFID;
        open $ConFID, $thisCONpath or die "Could not open $thisCONpath\n";
        my @CONlines = <$ConFID>; # Pull entire file into an array
        close $ConFID;
        
        # File indexers
        my $FileLine=0;
        my $StartHere=0;
        
        # Emissivity and absorptivity
        my @EMinside;
        my @EMoutside;
        my @SLRinside;
        my @SLRoutside;
        
        # Gaps Data
        my $sGapsPosition;
        my $sGapsInfo;

        # Update the GAPS
        #=======================================
        NUM_GAPS: foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
            my $bIsNoGap = 0;

            until ($CONlines[$FileLine] =~ m/$GlazeName/i) { # Find the aperture gaps
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find aperture gap data $house_name $zones\n";}
            };
            # Update the gap data for the window
            $CONlines[$FileLine] = "$NewGlzLayers $NewGlzGaps # $GlazeName $NewGlzDesc\n";
            
            # Enter the frame data
            my @ParentData = split '-', $GlazeName;
            my $FrameName = $ParentData[0];
            $FrameName = $FrameName . "-frame"; # Set the name of the frame surface
            
            $FileLine=0; # RWD file
            until ($CONlines[$FileLine] =~ m/$FrameName/i) { # Find the aperture gaps
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find frame gap data $house_name $zones\n";}
            };
            # Update the gap data for the frame
            $CONlines[$FileLine] = "$NewFrmLayers $NewFrmGaps # $FrameName $NewFrmDesc\n";
            $FileLine=0; # RWD file
        }; # END NUM_GAPS
        
        # Find and store the constructions with gaps
        #=======================================
        until ($CONlines[$FileLine] =~ m/^(#LAYERS_GAPS)/i) { # Get to start of layers gaps section
            $FileLine++;
            if ($FileLine>$#CONlines){die "NUM_GAPS: Could not get to top of LAYERS_GAPS $house_name\n";}
        };
        $FileLine++;
        
        my $iNumGapLayers = 0;
        GET_NUM_GAPS: until ($CONlines[$FileLine] =~ m/^(#END_LAYERS_GAPS)/i) { # determine layers with gaps
            my $sLine = $CONlines[$FileLine];
            $sLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            my @sLineData = split /[, ]/, $sLine;
            if($sLineData[1]>0) {
                $iNumGapLayers++;
                $sGapsPosition->{"$iNumGapLayers"}=$sLineData[3];
            };
            $FileLine++;
            if ($FileLine>$#CONlines){die "GET_NUM_GAPS: Ran to EOF $house_name\n";}
        };
        $FileLine=0; # RWD file
        
        # Find and store old gap data
        #=======================================
        $FileLine=0; # RWD file
        until ($CONlines[$FileLine] =~ m/^(#GAP_POS_AND_RSI)/i) { # FWD to gap section
            $FileLine++;
            if ($FileLine>$#CONlines){die "setNewWindows: Could not find gap info data $house_name\n";}
        };
        $StartHere=$FileLine;
        
        $FileLine++;
        until ($CONlines[$FileLine] =~ m/^(#END_GAP_POS_AND_RSI)/i) {
            my $sLine = $CONlines[$FileLine];
            $sLine =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            my @sLineData = split /#/, $sLine;
            $sLineData[1] =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @sLineData = split /[, ]/, $sLineData[1];
            $sGapsInfo->{"$sLineData[0]"} = $CONlines[$FileLine];
            
            $FileLine++;
            if ($FileLine>$#CONlines){die "setNewWindows: Could not find gap info data $house_name\n";}
        };

        # Update GAP info
        #=======================================
        GAP_INFO: {
           my @TempCONlines=@CONlines[0..$StartHere];
           
           for (my$k=1;$k<=$iNumGapLayers;$k++) { # For each gap
                my $ThisSurface = $sGapsPosition->{"$k"};
                my @ParentData = split '-', $ThisSurface;
                my $sParent = $ParentData[0];
                my $sChild = $ParentData[1];
                
                if(defined $UPGglaze->{"$house_name"}->{"$zones"}->{"$sParent-aper"}) {
                    # Declare new string for gap data
                    my $NewGapDataLine="";
                    # This surface is being upgraded, determine if its the frame or aperture
                    if($sChild =~ m/aper/) {
                        # Update the gap data for the window
                        for (my $i=1;$i<=$NewGlzGaps;$i++) {
                            my $GappyPos = $UpgradesWindow->{'GAPS'}->{"gapPos_$i"};
                            my $GappyRSI = $UpgradesWindow->{'GAPS'}->{"gapRSI_$i"};
                            $NewGapDataLine = $NewGapDataLine . "$GappyPos $GappyRSI ";
                        };
                        $NewGapDataLine = "$NewGapDataLine # $ThisSurface $NewGlzDesc\n";
                        
                    } elsif($sChild =~ m/frame/) {
                        for (my $i=1;$i<=$NewFrmGaps;$i++) {
                            my $GappyPos = $UpgradesWindow->{'frame'}->{'GAPS'}->{"gapPos_$i"};
                            my $GappyRSI = $UpgradesWindow->{'frame'}->{'GAPS'}->{"gapRSI_$i"};
                            $NewGapDataLine = $NewGapDataLine . "$GappyPos $GappyRSI ";
                        };
                        $NewGapDataLine = "$NewGapDataLine # $ThisSurface $NewFrmDesc\n";
                        
                    } else {
                        die "setNewWindows: Unrecognized child surface $sChild $house_name\n";
                    };
                    
                    # Add the the construction file
                    push(@TempCONlines,$NewGapDataLine);
                    
                } else {
                    # Surface is not being upgraded
                    push(@TempCONlines,$sGapsInfo->{"$ThisSurface"});
                };

           };
           
           # Append the rest of the construction data
           $FileLine=0; # RWD file
           until ($CONlines[$FileLine] =~ m/^(#END_GAP_POS_AND_RSI)/i) {
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find gap info data $house_name\n";}
            };
           push(@TempCONlines,@CONlines[$FileLine..$#CONlines]);
           
           # Update the con file
           @CONlines=@TempCONlines;
           undef @TempCONlines;
           
           $FileLine=$StartHere; # RWD file to start of GAPS data
        }; # END GAP_INFO
        
        # Update the construction data
        #=======================================
        CONS_INFO: {
            until ($CONlines[$FileLine] =~ m/^(# CONSTRUCTION)/i) { # Find the beginning of the constructions
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find start of CONSTRUCTION $house_name $zones\n";}
            };
            $StartHere=$FileLine; # Index the beginning of the construction data
            foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
                until ($CONlines[$FileLine] =~ m/$GlazeName/i) { # Find the aperture gap info
                    $FileLine++;
                    if ($FileLine>$#CONlines){die "setNewWindows: Could not find Construction data gap info lines $house_name $zones $GlazeName\n";}
                };
                # Update the glazing construction header
                $CONlines[$FileLine] = "# CONSTRUCTION: $GlazeName - $NewGlzDesc\n"; # TODO: Add longer description
                my @UpdatedCONlines = @CONlines[0..$FileLine]; # Trim off everything from below
                $FileLine++; # Advance the file to clear the comments
                for (my $i=1;$i<=$NewGlzLayers;$i++) {
                    my $newLine = $UpgradesWindow->{'CONS'}->{"Layer_$i"};
                    $newLine = $newLine . "\n";
                    push(@UpdatedCONlines,$newLine);
                };
                until ($CONlines[$FileLine] =~ m/^(#)/i) { # FFWD to end of old glazing constructions in 
                    $FileLine++;
                    if ($FileLine>$#CONlines){die "setNewWindows: Could not end of constgruction data $house_name $zones $GlazeName\n";}
                };
                push(@UpdatedCONlines,@CONlines[$FileLine..$#CONlines]); # Attach the rest of the file
                @CONlines = @UpdatedCONlines; # Reset the construction lines
                undef @UpdatedCONlines;
                
                # Update the associated frame
                my @ParentData = split '-', $GlazeName;
                my $FrameName = $ParentData[0];
                $FrameName = $FrameName . "-frame"; # Set the name of the frame surface
                
                $FileLine = $StartHere; # RWD file to beginning of construction data
                until ($CONlines[$FileLine] =~ m/$FrameName/i) { # Find the aperture gap info
                    $FileLine++;
                    if ($FileLine>$#CONlines){die "setNewWindows: Could not find Construction data gap info lines $house_name $zones $FrameName\n";}
                };
                # Update the frame construction header
                $CONlines[$FileLine] = "# CONSTRUCTION: $FrameName - $NewFrmDesc\n"; # TODO: Add longer description
                @UpdatedCONlines = @CONlines[0..$FileLine]; # Trim off everything from below
                $FileLine++; # Advance the file to clear the comments
                for (my $i=1;$i<=$NewFrmLayers;$i++) {
                    my $newLine = $UpgradesWindow->{'frame'}->{'CONS'}->{"Layer_$i"};
                    $newLine = $newLine . "\n";
                    push(@UpdatedCONlines,$newLine);
                };
                until ($CONlines[$FileLine] =~ m/^(#)/i) { # FFWD to end of old glazing constructions in 
                    $FileLine++;
                    if ($FileLine>$#CONlines){die "setNewWindows: Could not end of constgruction data $house_name $zones $FrameName\n";}
                };
                push(@UpdatedCONlines,@CONlines[$FileLine..$#CONlines]); # Attach the rest of the file
                @CONlines = @UpdatedCONlines; # Reset the construction lines
                undef @UpdatedCONlines;
                
                # RWD to the top of the construction for next iteration
                $FileLine = $StartHere;
            };
        }; # END CONS_INFO
        
        # Update the emissivity
        #=======================================
        EMIS: {
            ###### INSIDE ######
            until ($CONlines[$FileLine] =~ m/^(#EM_INSIDE)/i) { # Find the beginning of the inside emissivity data
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find inside emissivity $house_name $zones\n";}
            };
            $FileLine++;
            my $LineData = $CONlines[$FileLine]; # Grab the emissivity data
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @EMinside = split / /, $LineData;
            foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
                # Retrieve the aperture surface number and update inside emissivity
                my $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num'};
                $EMinside[$ThisSurfNum-1] = $NewGlzEMin;
                
                # Retrieve the frame surface number and update inside emissivity
                $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num_frame'};
                $EMinside[$ThisSurfNum-1] = $NewFrmEMin;
            };
            $LineData = ""; # Clear the line data
            for (my $i=0;$i<=$#EMinside;$i++) {
                $LineData = $LineData . " $EMinside[$i]";
            };
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $LineData = $LineData . "\n";
            # Update the construction file
            $CONlines[$FileLine] = $LineData;
            
            ###### OUTSIDE ######
            until ($CONlines[$FileLine] =~ m/^(#EM_OUTSIDE)/i) { # Find the beginning of the inside emissivity data
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find outside emissivity $house_name $zones\n";}
            };
            $FileLine++;
            $LineData = $CONlines[$FileLine]; # Grab the emissivity data
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @EMoutside = split / /, $LineData;
            foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
                # Retrieve the aperture surface number and update inside emissivity
                my $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num'};
                $EMoutside[$ThisSurfNum-1] = $NewGlzEMout;
                
                # Retrieve the frame surface number and update inside emissivity
                $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num_frame'};
                $EMoutside[$ThisSurfNum-1] = $NewFrmEMout;
            };
            $LineData = ""; # Clear the line data
            for (my $i=0;$i<=$#EMoutside;$i++) {
                $LineData = $LineData . " $EMoutside[$i]";
            };
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $LineData = $LineData . "\n";
            # Update the construction file
            $CONlines[$FileLine] = $LineData;
        }; # END EMIS
        
        # Update the solar absorptivity
        #=======================================
        SLR_ABS: {
            ###### INSIDE ######
            until ($CONlines[$FileLine] =~ m/^(#SLR_ABS_INSIDE)/i) { # Find the beginning of the inside solar absorptivity data
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find inside solar absorptivity $house_name $zones\n";}
            };
            $FileLine++;
            my $LineData = $CONlines[$FileLine]; # Grab the solar absorptivity data
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @SLRinside = split / /, $LineData;
            foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
                # Retrieve the aperture surface number and update inside solar absorptivity
                my $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num'};
                $SLRinside[$ThisSurfNum-1] = $NewGlzSLRin;
                
                # Retrieve the frame surface number and update inside solar absorptivity
                $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num_frame'};
                $SLRinside[$ThisSurfNum-1] = $NewFrmSLRin;
            };
            $LineData = ""; # Clear the line data
            for (my $i=0;$i<=$#SLRinside;$i++) {
                $LineData = $LineData . " $SLRinside[$i]";
            };
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $LineData = $LineData . "\n";
            # Update the construction file
            $CONlines[$FileLine] = $LineData;
            
            ###### OUTSIDE ######
            until ($CONlines[$FileLine] =~ m/^(#SLR_ABS_OUTSIDE)/i) { # Find the beginning of the outside solar absorptivity data
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find outside solar absorptivity $house_name $zones\n";}
            };
            $FileLine++;
            $LineData = $CONlines[$FileLine]; # Grab the solar absorptivity data
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @SLRoutside = split / /, $LineData;
            foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
                # Retrieve the aperture surface number and update outside solar absorptivity
                my $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num'};
                $SLRoutside[$ThisSurfNum-1] = $NewGlzSLRout;
                
                # Retrieve the frame surface number and update outside solar absorptivity
                $ThisSurfNum = $UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num_frame'};
                $SLRoutside[$ThisSurfNum-1] = $NewFrmSLRout;
            };
            $LineData = ""; # Clear the line data
            for (my $i=0;$i<=$#SLRoutside;$i++) {
                $LineData = $LineData . " $SLRoutside[$i]";
            };
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $LineData = $LineData . "\n";
            # Update the construction file
            $CONlines[$FileLine] = $LineData;
        }; # END SLR_ABS
        
        # Print the new con file for this zone
        unlink $thisCONpath; # Clear the old file
        open my $out, '>', $thisCONpath or die "Can't write $thisCONpath: $!";
        foreach my $ThatData (@CONlines) {
            print $out $ThatData;
        };
        close $out;
        undef @CONlines; # Clear the CONlines array
        
            #### Updating the TMC File ####
        #=======================================
        ########################################
        UPG_TMC: {
            # Locals
            my @TMCindices;
            my @TMCUpdate; # TMC indices that are to be updated
            my @TMCkeep; # TMC indices that are to be kept
            
            my @bSurfUpdate; # Index of array corresponds to surface number, boolean indicates if surface is updated
            
            my $TMCkeepData; # Hash of arrays to hold the TMC data that is to be kept
            
            # Open and slurp the construction file
            my $tmcFID;
            open $tmcFID, $thisTMCpath or die "Could not open $thisTMCpath\n";
            @CONlines = <$tmcFID>; # Pull entire file into an array
            close $tmcFID;
            
            # Reset the indexers
            $FileLine=0;
            $StartHere=0;
            my $TMCindex=0;

            # Load the TMC surface indices
            until ($CONlines[$FileLine] =~ m/^(#TMC_INDEX)/i) {
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find TMC indices $house_name $zones\n";}
            };
            $FileLine++;
            my $LineData = $CONlines[$FileLine];
            $LineData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            @TMCindices = split / /, $LineData;
            $TMCindex = $FileLine; # Store the line number the TMC indexes are held on
            
            @bSurfUpdate = (0) x (scalar @TMCindices); # Initialize array to 0
            
            # Determine if any of the glass types are being kept
            INDX_LOOP: for(my $i=0;$i<=$#TMCindices;$i++) {
                if($TMCindices[$i]<1){next INDX_LOOP;} # a zero, go to the next index
                my $CurrentSurf = $i+1;
                # Determine if this surface has been upgraded
                FIND_SURF: foreach my $GlazeName (keys (%{$UPGglaze->{"$house_name"}->{"$zones"}})) {
                    if($UPGglaze->{"$house_name"}->{"$zones"}->{"$GlazeName"}->{'surf_num'} == $CurrentSurf) { 
                        # This surface is being updated
                        $bSurfUpdate[$i] = 1;
                        
                        # Determine if we've already encountered this index
                        if(not @TMCUpdate) {
                            push(@TMCUpdate,$TMCindices[$i]); # Store the TMC index
                            next INDX_LOOP;
                        } else { # Check if we've already flagged this index
                            foreach my $index (@TMCUpdate) {
                                if($index==$TMCindices[$i]) {
                                    # Already have this index flagged for update
                                    next INDX_LOOP;
                                };
                            };
                            push(@TMCUpdate,$TMCindices[$i]); # New index, store
                            next INDX_LOOP;
                        };
                    };
                }; # END FIND_SURF
                
                # If we get here, that means there is no upgraded surface associated with the glass type
                if(not @TMCkeep) {
                    push(@TMCkeep,$TMCindices[$i]);
                } else {
                    foreach my $index (@TMCkeep) {
                        if($index==$TMCindices[$i]) {
                            # Already have this index flagged to keep
                            next INDX_LOOP;
                        }
                    };
                    push(@TMCkeep,$TMCindices[$i]);
                };
            }; # END INDX_LOOP
            
            # FFWD to the start of the detailed TMC Data
            until ($CONlines[$FileLine] =~ m/^(# optical)/i) { # Find the beginning of the optical data
                $FileLine++;
                if ($FileLine>$#CONlines){die "setNewWindows: Could not find outside solar absorptivity $house_name $zones\n";}
            };
            $StartHere=$FileLine; # Store header data of 

            # Store the data for the TMCs that are being retained
            my $iOldTMCdata=0; # Number of old glazing systems to be saved
            STORE_OLD: foreach my $index (@TMCkeep) {
                my @StringStuff=();
                $FileLine = $StartHere+1; # RWD to start of TMC data

                # Locate the data to save
                my $DataGroup=1; # First set of data
                until ($DataGroup==$index) {
                    $FileLine++;
                    if ($FileLine>$#CONlines){die "setNewWindows: Could not TMC data to keep $house_name $zones\n";}
                    if($CONlines[$FileLine] =~ m/[a-zA-Z]/) {$DataGroup++;} # The start of each data group has characters in the line
                };
                # Store the first line of this data
                push(@StringStuff,$CONlines[$FileLine]);
                $FileLine++;
                
                # Store the rest of the TMC data to be saved
                until ($CONlines[$FileLine] =~ m/[a-zA-Z]/) { # Find the beginning of the optical data
                    push(@StringStuff,$CONlines[$FileLine]);
                    $FileLine++;
                    if ($FileLine>$#CONlines){die "setNewWindows: Could not find outside solar absorptivity $house_name $zones\n";}
                };
                $iOldTMCdata++;
                
                # Store data in the HASH
                $TMCkeepData->{"$iOldTMCdata"}->{'orig_index'} = $index;
                $TMCkeepData->{"$iOldTMCdata"}->{'data'} = \@StringStuff;
            };
            
            # Trim out the old TMC data
            @CONlines = @CONlines[0..$StartHere];
            
            # Add the new TMC data (will become glazing index 1)
            push(@CONlines, "$NewGlzLayers Optic_UPG\n");
            push(@CONlines,($UpgradesWindow->{'TMC'}->{"trans"} . "\n"));
            for(my $i=1;$i<=$NewGlzLayers;$i++) {
                push(@CONlines,($UpgradesWindow->{'TMC'}->{"Layer_$i"} . "\n"));
            };
            push(@CONlines, "0\n");
            
            # Add the old TMC data
            my $ReorderGlazeIndex=2; # New index for the old TMC data
            for(my $i=1;$i<=$iOldTMCdata;$i++) {
                my @LocalData = @{$TMCkeepData->{"$i"}->{'data'}};
                foreach my $LocalLine (@LocalData) {
                    push(@CONlines,$LocalLine);
                };
                $TMCkeepData->{"$i"}->{'new_index'} = $ReorderGlazeIndex;
                $ReorderGlazeIndex++;
            };
            
            # Finish off the file
            push(@CONlines,"#END_TMC_DATA\n");
            
            # Update the TMC index
            UPDATE_INDEX: for(my $i=0;$i<=$#TMCindices;$i++) { # Update 
                if($TMCindices[$i]<1){next UPDATE_INDEX;}
                
                # Determine if this surface is being updated
                if($bSurfUpdate[$i]>0) {
                    $TMCindices[$i] = 1; # New glazing is always first
                    next UPDATE_INDEX;
                } else { # Glaze is old system, update index
                    foreach my $CrossReff (keys (%{$TMCkeepData})) {
                        if($TMCkeepData->{"$CrossReff"}->{'orig_index'} == $TMCindices[$i]) {
                            $TMCindices[$i] = $TMCkeepData->{"$CrossReff"}->{'new_index'};
                            next UPDATE_INDEX;
                        };
                    };
                    die "setNewWindows: Unable to update index $TMCindices[$i], $house_name $zones\n";
                };
            }; # END UPDATE_INDEX
            
            # Print the updated indices
            my $NewIndexStrings="";
            foreach my $ind (@TMCindices) {
                $NewIndexStrings = $NewIndexStrings . "$ind ";
            };
            $NewIndexStrings =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
            $NewIndexStrings = $NewIndexStrings . "\n";
            $CONlines[$TMCindex] = $NewIndexStrings;
            
            # Print the new tmc file for this zone
            unlink $thisTMCpath; # Clear the old file
            open my $fidout, '>', $thisTMCpath or die "Can't write $thisTMCpath: $!";
            foreach my $ThatData (@CONlines) {
                print $fidout $ThatData;
            };
            close $fidout;
        }; # END UPG_TMC
    }; # END ZONAL
   return 1; 
};

# ====================================================================
# *********** WALL SUBROUTINES ***************
# ====================================================================

# ====================================================================
# getWallCladdingIns
#       This subroutine opens the dwelling HVAC file, determines the
#       current system type, and store the data in the upgrade HASH
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub getWallCladdingIns {
    # INPUTS
    my ($house_name,$setPath,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $sMainZone = 'main_1'; # Every CHREM dwelling has a main zone
    my $FileLine = 0;
    my $sStringData;
    my $fRSI;
    my $sCladding;
    
    # Load the mvnt file
    my $sPathToCon = $setPath . $house_name. "/$house_name.$sMainZone.con";
    my $fid;
    open $fid, $sPathToCon or die "getWallCladdingIns: Could not open $sPathToCon\n";
    my @CONlines = <$fid>; # Pull entire file into an array
    close $fid;
    
    # FWD to surface properties
    until ($CONlines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {
        $FileLine++;
    };
    
    # Find the main wall construction
    until ($CONlines[$FileLine] =~ m/(M_wall)/i) {
        $FileLine++;
    };
    $sStringData = $CONlines[$FileLine];
    $sStringData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace

    # Get the RSI value of the wall assembly
    ($fRSI) = $sStringData =~ m/U Value final (.*) \(/;
    $fRSI=1/$fRSI; # Convert U-value to RSI (m2K/W)
    $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_Asmbly_RSI'} = sprintf("%.2f",$fRSI);
    
    # Get the cladding type
    $FileLine++;
    $sStringData = $CONlines[$FileLine];
    $sStringData =~ s/^\s+|\s+$//g; # Remove leading and trailing whitespace
    #($sCladding) = $sStringData =~ m/# siding - (.*); RSI/;
    ($sCladding) = $sStringData =~ m/- (.*); RSI/;
    $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_Cladding'} = $sCladding;
    
    # Get the RSI value of the wall insulation
    $FileLine++;
    $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_RSI'} = 0.0;
    until (($CONlines[$FileLine] =~ m/^(# CONSTRUCTION)/i) || ($CONlines[$FileLine] =~ m/^(#END_PROPERTIES)/i)) {
        if($CONlines[$FileLine] =~ m/(insulation)/) {
            # Insulation layer, determine the RSI
            my @sData = split /[,\s]+/, $CONlines[$FileLine];
            my $fThisRSI = $sData[3]/$sData[0]; # RSI [m2K/W]
            $UPGrecords->{'WALL_INS'}->{"$house_name"}->{'orig_Wall_RSI'} += $fThisRSI;
        };
        $FileLine++;
    };

    # Set Output
    return $UPGrecords;
};
# ====================================================================
# setWallCladding
#       This subroutine opens the dwelling HVAC file, determines the
#       current system type, and store the data in the upgrade HASH
#
# INPUT     house_name: name of the dwelling of interest
#           recPath: path to this project being upgraded
#           UPGrecords: HASH holding all the upgrade info 
# ====================================================================
sub setWallCladding {
    # INPUTS
    my ($house_name,$fInsThick,$UpgradesWall,$sCurrentClad,$thisHouse,$setPath,$sCladKey,$sInsKey,$UPGrecords) = @_;
    
    # INTERMEDIATES
    my $FileLine = 0;
    my @sZones; # Array of strings holding names of main zones
    #my $bIsGabled=0; # Boolean indicating if the roof is gabled or not
    my $sNewCladding; # String holding construction layer info for cladding
    my @sNewIns=(); # Array of string holding construction layer info for insulation
    my $iNewLayers=0; # Number of new layers added (minimum is 2)
    
    # Prepare the new layer info
    NEW_CLAD: { # Cladding
        $iNewLayers++;
        my $fCladRSI = "0.0";
        my $fCladUvalue = $UpgradesWall->{$sCladKey}->{'cld_k'}/$UpgradesWall->{$sCladKey}->{'cld_t'};
        $fCladUvalue = sprintf("%.3f",$fCladUvalue);
        my $fCladCond = $UpgradesWall->{$sCladKey}->{'cld_k'};
        my $fCladRho = $UpgradesWall->{$sCladKey}->{'cld_rho'};
        my $fCladCp = $UpgradesWall->{$sCladKey}->{'cld_Cp'};
        my $fCladThick = $UpgradesWall->{$sCladKey}->{'cld_t'};
        my $sCladDescrip = $UpgradesWall->{$sCladKey}->{'description'};
        $sNewCladding = sprintf("%s %s %s %s 0 0 0 0 # %s; RSI = %s; U value = %s (W/m^2K)\n",$fCladCond,$fCladRho,$fCladCp,$fCladThick,$sCladDescrip,$fCladRSI,$fCladUvalue);
    };

    NEW_INS: {# Insulation
        my $fCond = $UpgradesWall->{$sInsKey}->{'ins_k'};
        my $fRho = $UpgradesWall->{$sInsKey}->{'ins_rho'};
        my $fCp = $UpgradesWall->{$sInsKey}->{'ins_Cp'};
        my $sDescrip = $UpgradesWall->{$sInsKey}->{'description'};
        if($fInsThick>0.2) { # Need to discretize insulation layer more
            until($fInsThick<0.2) {
                my $fThisThick = 0.200;
                my $fRSI = $fThisThick/$UpgradesWall->{$sInsKey}->{'ins_k'};
                $fRSI = sprintf("%.2f",$fRSI);
                my $fUvalue = 1/$fRSI;
                $fUvalue = sprintf("%.3f",$fUvalue);
                my $sInfo = sprintf("%s %s %s %s 0 0 0 0 # %s; RSI = %s; U value = %s (W/m^2K)\n",$fCond,$fRho,$fCp,$fThisThick,$sDescrip,$fRSI,$fUvalue);
                push(@sNewIns,$sInfo);
                $iNewLayers++;
                $fInsThick-=0.2;
            };
            if($fInsThick>0) {
                my $fRSI = $fInsThick/$UpgradesWall->{$sInsKey}->{'ins_k'};
                $fRSI = sprintf("%.2f",$fRSI);
                my $fUvalue = 1/$fRSI;
                $fUvalue = sprintf("%.3f",$fUvalue);
                $fInsThick=sprintf("%.5f",$fInsThick);
                my $sInfo = sprintf("%s %s %s %s 0 0 0 0 # %s; RSI = %s; U value = %s (W/m^2K)\n",$fCond,$fRho,$fCp,$fInsThick,$sDescrip,$fRSI,$fUvalue);
                push(@sNewIns,$sInfo);
                $iNewLayers++;
            };

        } elsif($fInsThick>0.0) { # Only need only layer for insulation
            my $fRSI = $fInsThick/$UpgradesWall->{$sInsKey}->{'ins_k'};
            $fRSI = sprintf("%.2f",$fRSI);
            my $fUvalue = 1/$fRSI;
            $fUvalue = sprintf("%.3f",$fUvalue);
            $fInsThick=sprintf("%.5f",$fInsThick);
            my $sInfo = sprintf("%s %s %s %s 0 0 0 0 # %s; RSI = %s; U value = %s (W/m^2K)\n",$fCond,$fRho,$fCp,$fInsThick,$sDescrip,$fRSI,$fUvalue);
            push(@sNewIns,$sInfo);
            $iNewLayers++;
        };
    };
    
    # Determine how many main zones there are
    foreach my $zones (keys (%{$thisHouse})) {
        if($zones =~ m/^(main)/i) {push(@sZones,$zones);}
    };

    # Update the construction file
    foreach my $zones (@sZones) {
        my $iThisLayers = $iNewLayers;
        my $FileLine=0;
        my $sConPath = $setPath . $house_name. "/$house_name.$zones.con";
        my $fid;
        open $fid, $sConPath or die "setWallCladdingVinyl: Could not open $sConPath\n";
        my @CONlines = <$fid>; # Pull entire file into an array
        close $fid;
        
        # FWD to LAYERS_GAPS
        until ($CONlines[$FileLine] =~ m/^(#LAYERS_GAPS)/i) {
            $FileLine++;
            if($FileLine>$#CONlines) {die "setWallCladding: $house_name unable to locate LAYERS_GAPS\n";}
        };
        
        # Update the main wall number of layers
        if($sCurrentClad =~ m/(Vinyl)/) {
            # Old cladding is removed, insulation is installed, then new cladding
            $iThisLayers--;
        };
        until ($CONlines[$FileLine] =~ m/^(#END_LAYERS_GAPS)/i) {
            if($CONlines[$FileLine] =~ m/(M_wall)/i) { # This is a main wall, update it
                my @sData = split /[,\s]+/, $CONlines[$FileLine];
                my $iNew = $sData[0]+$iThisLayers;
                $iNew="$iNew";
                my $sGapData = sprintf("%s %s %s %s %s\n",$iNew,$sData[1],$sData[2],$sData[3],$sData[4]);
                $CONlines[$FileLine]=$sGapData;
            };
            $FileLine++;
            if($FileLine>$#CONlines) {die "setWallCladding: $house_name unable to locate end of LAYERS_GAPS\n";}
        };
        
        # FWD to GAPS_POS_AND_RSI
        until ($CONlines[$FileLine] =~ m/^(#GAP_POS_AND_RSI)/i) {
            $FileLine++;
            if($FileLine>$#CONlines) {die "setWallCladding: $house_name unable to locate GAP_POS_AND_RSI\n";}
        };
        # Update gap positions
        until ($CONlines[$FileLine] =~ m/^(#END_GAP_POS_AND_RSI)/i) {
            if($CONlines[$FileLine] =~ m/(M_wall)/i) { # This is a main wall, update it
                (my $sOnlyData = $CONlines[$FileLine]) =~ s/\s#[^.]+$//;
                my @sData = split /[,\s]+/, $sOnlyData;
                for (my $i=0;$i<$#sData;$i=$i+2) {
                    $sData[$i]+=$iThisLayers;
                };
                (my $sComment = $CONlines[$FileLine]) =~ s/^.+#\s//;
                my $NewString="";
                for(my $i=0;$i<=$#sData;$i++) {
                    $NewString=$NewString . "$sData[$i] ";
                };
                $NewString=$NewString . "# $sComment";
                $CONlines[$FileLine]=$NewString;
            };
            $FileLine++;
            if($FileLine>$#CONlines) {die "setWallCladding: $house_name unable to locate END_GAP_POS_AND_RSI\n";}
        };
        
        # FWD to surface properties
        until ($CONlines[$FileLine] =~ m/^(# CONSTRUCTION)/i) {
            $FileLine++;
            if($FileLine>$#CONlines) {die "setWallCladding: $house_name unable to locate CONSTRUCTIONS\n";}
        };
        
        # Find and modify the main wall constructions
        while ($FileLine<=$#CONlines) {
            if($CONlines[$FileLine] =~ m/(M_wall)/i) { # This is a main wall, update it
                # Store the top half of the construction file
                my @Top=@CONlines[0..$FileLine];
                # Add the new cladding and external insulation
                push(@Top,$sNewCladding); # Cladding data
                foreach my $sNewInsData (@sNewIns) { # All the insulation layers
                    push(@Top,$sNewInsData);
                };
                
                # External main wall upgrade is dependent on existing cladding
                if($sCurrentClad =~ m/(Vinyl)/) {
                    # Old cladding is removed, insulation is installed, then new cladding
                    push(@Top,@CONlines[($FileLine+2)..$#CONlines]);
                } elsif($sCurrentClad =~ m/(Brick|Concrete|Stone|SPF|Plywood)/) {
                    # Insulation and new cladding is placed on top of the existing wall
                    push(@Top,@CONlines[($FileLine+1)..$#CONlines]);
                } else {
                    print "setWallCladding: Unknown cladding type $sCurrentClad in house $house_name\nInsulation and new cladding added on top of existing\n";
                    push(@Top,@CONlines[($FileLine+1)..$#CONlines]);
                };
                @CONlines = @Top;
            
            };
            $FileLine++;
        };
        
        # Print out new construction file
        unlink $sConPath; # Clear the old file
        open my $out, '>', $sConPath or die "Can't write $sConPath: $!";
        foreach my $ThatData (@CONlines) {
            print $out $ThatData;
        };
        close $out;
            
    }; # END ZONE LOOP

    return $UPGrecords;
};
   
# Final return value of one to indicate that the perl module is successful
1;