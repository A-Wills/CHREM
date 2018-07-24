#!/usr/bin/perl

# ====================================================================
# Upgrade_City.pl
# Author: Adam Wills
# Date: Jun 2016

# BASED UPON Hse_Gen.pl
# Author: Lukas Swan
# Date: Oct 2009
# Copyright: Dalhousie University

# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name] [simulation timestep in minutes] [House_list]

# DESCRIPTION:
# This script generates the esp-r house files for each house of the CSDDRD.
# It uses a multithreading approach based on the house type (SD or DR) and 
# region (AT, QC, OT, PR, BC). Which types and regions are generated is 
# specified at the beginning of the script to allow for partial generation.

# The script builds a directory structure for the houses which begins with 
# the house type as top level directories, regions as second level directories 
# and the house name (10 digit w/o ".HDF") inclusing the set_name for each house directory. It places 
# all house files within that directory (all house files in the same directory). 

# The script reads a set of input files:
# 1) CSDDRD type and region database (csv)
# 2) esp-r file templates (template.xxx)
# 3) weather station cross reference list

# The script copies the template files for each house of the CSDDRD and replaces
# and inserts within the templates based on the values of the CSDDRD house. Each 
# template file is explicitly dealt with in the main code (actually a sub) and 
# utilizes insert and replace subroutines to administer the specific house 
# information.

# The script is easily extendable to addtional CSDDRD files and template files.
# Care must be taken that the appropriate lines of the template file are defined 
# and that any required changes in other template files are completed.

# ===================================================================

# --------------------------------------------------------------------
# Declare modules which are used
# --------------------------------------------------------------------

use warnings;
use strict;

use CSV;	# CSV-2 (for CSV split and join, this works best)
# use Array::Compare;	# Array-Compare-1.15
use threads;	# threads-1.89 (to multithread the program)
use threads::shared;
use File::Path qw(make_path remove_tree);	# File-Path-2.04 (to create directory trees)
use File::Copy;	# (to copy the input.xml file)
use File::Copy::Recursive qw(fcopy rcopy dircopy fmove rmove dirmove);
use XML::Simple qw(:strict);	# to parse the XML databases for esp-r and for Hse_Gen
use Data::Dumper;	# to dump info to the terminal for debugging purposes
use Switch;
use Storable  qw(dclone);
use Hash::Merge qw(merge);
use POSIX;

use lib qw(./modules);
use General;
use Cross_reference;
use Database;
use Constructions;
use Control;
use Zoning;
use Air_flow;
use BASESIMP;
use Upgrade;
use UpgradeCity;

$Data::Dumper::Sortkeys = \&order;

Hash::Merge::specify_behavior(
	{
		'SCALAR' => {
			'SCALAR' => sub {$_[0] + $_[1]},
			'ARRAY'  => sub {[$_[0], @{$_[1]}]},
			'HASH'   => sub {$_[1]->{$_[0]} = undef},
		},
		'ARRAY' => {
			'SCALAR' => sub {[@{$_[0]}, $_[1]]},
			'ARRAY'  => sub {[@{$_[0]}, @{$_[1]}]},
			'HASH'   => sub {[@{$_[0]}, $_[1]]},
		},
		'HASH' => {
			'SCALAR' => sub {$_[0]->{$_[1]} = undef},
			'ARRAY'  => sub {[@{$_[1]}, $_[0]]},
			'HASH'   => sub {Hash::Merge::_merge_hashes($_[0], $_[1])},
		},
	}, 
	'Merge where scalars are added, and items are (pre)|(ap)pended to arrays', 
);

# --------------------------------------------------------------------
# Declare the global variables
# --------------------------------------------------------------------
my $hse_type;	# String to hold the house type to be processed
my $region;	    # String to hold the region to be simulated
my $hse_type_num;   # String holding the user input for house types
my $region_num; # String holding the user input for regions
my $set_name;   # Name of the new set
my $setPath;    # String holding path to new set
my $BaseSet;    # Name of the base set being copied
my $Upgrades;   # HASH holding all the upgrade info
my $Surface;    # HASH holding all the surface area data for the community [m2]
my $UPGrecords; # HASH to hold upgrade report data
my $isPVupgrade = 0; # Boolean indicating if PV is to be added
my $isDHupgrade = 0; # Boolean indicating if district heating is to be added
my $bPrintDHW = 0; # Boolean indicating if DHW loads are to be reported
my $hDwellChar;     # Hash table holding dwelling characteristics
my $hAirtight;      # Hash table holding air efficacy for different regions, vintages, and upgrades
my @houses_desired = (); # declare an array to store the house names or part of to look
# Determine possible set names by scanning the summary_files folder
my $possible_set_names = {map {$_, 1} grep(s/.+UPG_(.+)_Surfaces.xml/$1/, <../summary_files/*>)}; # Map to hash keys so there are no repeats
# --------------------------------------------------------------------
# Read the command line input arguments
# --------------------------------------------------------------------
COMMAND_LINE: {
    my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
    my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
	if (@ARGV != 3) {die "Three arguments are required: house_types regions set_name \n";};	# check for proper argument count

	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
    $hse_type_num = shift (@ARGV);
    $region_num = shift (@ARGV);
	($hse_types, $regions, $BaseSet) = &hse_types_and_regions_and_set_name($hse_type_num, $region_num, shift (@ARGV));
    # Identify this set as an upgrade
	$set_name = '_UPG_' . $BaseSet;

    my $ikeys = 0;
    foreach my $value (values (%{$hse_types})) {
        $hse_type = $value;
        $ikeys++;
    };
    if($ikeys>1) {die "This script only supports only 1 house type at a time\n"};
    $ikeys = 0;
    foreach my $value (values (%{$regions})) {
        $region = $value;
        $ikeys++;
    };
    if($ikeys>1) {die "This script only supports only 1 region at a time\n"};

    # Store the path to the new set
    $setPath="../$hse_type$set_name/$region/";
    
}; # END COMMAND_LINE

# --------------------------------------------------------------------
# Load the upgrade inputs. If there is no upgrades, die
# --------------------------------------------------------------------
$Upgrades = XMLin("../Input_upgrade/Input_All_UPG.xml", keyattr => [], forcearray => 0);
$hAirtight = XMLin("../Input_upgrade/Input_Airtightness_Efficacy.xml", keyattr => [], forcearray => 0);

# --------------------------------------------------------------------
# Load Dwelling Characteristics
# --------------------------------------------------------------------
LOAD_CHARAC: {
    print "Loading the relevant CSDDRD data\n";
    # Open the appropriate CSDDRD file
    my $CSDDRDfile = '../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_' . $hse_type . '_subset_' . $region.'.csv';
    my $fid;
    open $fid, $CSDDRDfile or die "Could not open $CSDDRDfile\n";
    my @sAllLines = <$fid>;
    close $fid;
    
    # Locate and split the header
    my $i=0;
    until (($sAllLines[$i] =~ m/^(\*header)/) || ($i==$#sAllLines)) {$i++;}
    if($i==$#sAllLines){die "Unable to locate CSDDRD header data\n";}
    my @sHeaders = split /,/, $sAllLines[$i];
    
    # Find the vintage header
    my $iVint;
    for(my $j=0;$j<=$#sHeaders;$j++) {
        if($sHeaders[$j] =~ m/(vintage)/) {
            $iVint=$j;
            last;
        };
    };
    if(not defined $iVint){die "Unable to index vintage header in CSDDRD\n";}
    
    # Load vintage data for all dwellings
    $i++;
    while ($i<=$#sAllLines){
        my @sLineData = split /,/, $sAllLines[$i];
        my $sHseName = $sLineData[2];
        $sHseName =~ s{\.[^.]+$}{}; # Remove HDF extension
        $hDwellChar->{"$sHseName"}->{'vintage'}=$sLineData[$iVint];
        # Determine the dwelling decade
        my $iDecade = $sLineData[$iVint];
        chop $iDecade;
        $iDecade = $iDecade."0";
        $hDwellChar->{"$sHseName"}->{'decade'}=$iDecade;
        $i++;
    };
    
    print "Done\n";
};

# --------------------------------------------------------------------
# Copy over the base model for upgrades
# --------------------------------------------------------------------
COPY_BASE: {

    # Clean up any old results files
    unlink "../summary_files/UPG_$BaseSet" . "_Info.xml";
    
    my $BCDPath = "../$hse_type". "_$BaseSet/$region/BCD"; # Path to the BCD files
    print "Copying over the base files\n";
    # Get all the house names in the base set
    my $SrcModel = "../$hse_type". "_$BaseSet/$region";
    opendir( my $DIR, $SrcModel );
    while ( my $entry = readdir $DIR ) {
        next unless -d $SrcModel . '/' . $entry;
        next if $entry eq '.' or $entry eq '..';
        next if $entry =~ /BCD/; # Don't copy the BCD files, these tend to be large
        push(@houses_desired,$entry);
    }
    closedir $DIR;
    
    # Create new folder for set
    remove_tree("../$hse_type$set_name/"); # Clear the way if an old folder is there
    unlink "../summary_files/Add_PV_UPG_$BaseSet" . '_Houses.csv'; # Clear any PV upgrade data
    make_path($setPath);
    
    foreach my $record (@houses_desired) {
        my $OldPath = "../$hse_type"."_$BaseSet/$region/$record";
        dircopy($OldPath,$setPath . "$record") or die $!;
    };
    
    &setBCDpath(\@houses_desired,$BCDPath,$setPath);
    
    # Sim control requires a house generation issues report to exist in order to run simulations
    # Create a dummy file
    my $DummyFile = "../summary_files/Hse_Gen_UPG_$BaseSet" . "_Issues.txt";
    open (my $DumFID, '>', $DummyFile) or die ("Can't open dummy file: $DummyFile");	# open writeable file
    print $DumFID "\n";
    close $DumFID;
    
    print "Done\n";
}; # END COPY_BASE

# --------------------------------------------------------------------
# Load the surface area data
# --------------------------------------------------------------------
LOAD_SURF: {
    if (defined($possible_set_names->{$BaseSet})) { # Check to see if it is defined in the list
        # Load the surface area data
        my $xmlPath = "../summary_files/UPG_$BaseSet" . "_Surfaces.xml";
        $Surface = XMLin($xmlPath, keyattr => [], forcearray => 0);
        
    }
    else { 
        $Surface = &getGEOdata(\@houses_desired,$setPath);
        my $xmlPath = "../summary_files/UPG_$BaseSet" . "_Surfaces.xml";
        open (my $xmlFID, '>', $xmlPath) or die ("Can't open datafile: $xmlPath");	# open writeable file
        print $xmlFID XMLout($Surface, keyattr => []);	# printout the XML data
        close $xmlFID;
    };
};

# --------------------------------------------------------------------
# Apply upgrade(s) to all eligible dwellings
# --------------------------------------------------------------------
APPL_UPG: foreach my $house_name (@houses_desired) { # Loop through for each record
    # For this dwelling, add all upgrades
    my $fThisDecreaseAch=0.0; # Track the increase of airtightness for this dwelling (% reduction of N50 and ELA)
    
    EACH_UPG: foreach my $upg (keys (%{$Upgrades})){
        switch ($upg) {
            #case "AIM_2" {
            #    my $ins_sys = $Upgrades->{'AIM_2'}->{'vent_sys'};
            #    my $ins_key = "vent_$ins_sys";
            #    if($ins_sys == 0) {
            #        next EACH_UPG;
            #    } elsif(not defined($Upgrades->{'AIM_2'}->{"$ins_key"})) {
            #        print "Warning: Ceiling insulation system $ins_sys undefined, skipping\n";
            #        next EACH_UPG;
            #    } else {
            #        $UPGrecords = &upgradeAirtight($house_name,$Upgrades->{'AIM_2'}->{"$ins_key"},$setPath,$UPGrecords);
            #    };
            #}
            case "INC_AIRTIGHT" {
                next EACH_UPG;
            }
            case "VNT" {
                next EACH_UPG;
            }
            case "CEIL_INS" {
                my $ins_sys = $Upgrades->{'CEIL_INS'}->{'ins_sys'};
                my $ins_key = "sys_$ins_sys";
                if($ins_sys == 0) {
                    next EACH_UPG;
                } elsif(not defined($Upgrades->{'CEIL_INS'}->{"$ins_key"})) {
                    print "Warning: Ceiling insulation system $ins_sys undefined, skipping\n";
                    next EACH_UPG;
                } else {
                    $UPGrecords->{'CEIL_INS'}->{"$ins_key"}->{'max_RSI'}=$Upgrades->{'CEIL_INS'}->{'max_RSI'};
                    $UPGrecords = &upgradeCeilIns($house_name,$Upgrades->{'CEIL_INS'}->{"$ins_key"},$Surface->{"_$house_name"},$setPath,$UPGrecords);
                    # Add the effect on airtightness
                    if($Upgrades->{'INC_AIRTIGHT'}) {
                        if (not defined $hAirtight->{$upg}) {die "There is not airtightness efficacy associated with $upg\n";}
                        my $sThisDecade = $hDwellChar->{"$house_name"}->{'decade'};
                        $fThisDecreaseAch+=$hAirtight->{$upg}->{"_$region"}->{"_$sThisDecade"};
                    };
                    
                };
            }
            case "BASE_INS" {
                my $ins_sys = $Upgrades->{'BASE_INS'}->{'ins_sys'};
                my $ins_key = "sys_$ins_sys";
                if($ins_sys == 0) {
                    next EACH_UPG;
                } elsif(not defined($Upgrades->{'BASE_INS'}->{"$ins_key"})) {
                    print "Warning: Basement insulation system $ins_sys undefined, skipping\n";
                    next EACH_UPG;
                } else {
                    $UPGrecords->{'BASE_INS'}->{'bsmt_max_RSI'}=$Upgrades->{'BASE_INS'}->{'bsmt'}->{'max_RSI'};
                    $UPGrecords->{'BASE_INS'}->{'crawl_max_RSI'}=$Upgrades->{'BASE_INS'}->{'crawl'}->{'max_RSI'};
                    $UPGrecords = &upgradeBsmtIns($house_name,$Upgrades->{'BASE_INS'}->{"$ins_key"},$Surface->{"_$house_name"},$setPath,$UPGrecords);
                    # Add the effect on airtightness
                    if($Upgrades->{'INC_AIRTIGHT'}) {
                        if (not defined $hAirtight->{$upg}) {die "There is not airtightness efficacy associated with $upg\n";}
                        my $sThisDecade = $hDwellChar->{"$house_name"}->{'decade'};
                        $fThisDecreaseAch+=$hAirtight->{$upg}->{"_$region"}->{"_$sThisDecade"};
                    };
                };
            }
            case "WALL_INS" {
                my $ins_sys = $Upgrades->{'WALL_INS'}->{'RSI_goal'};
                my $ins_key = "goal_$ins_sys";
                if($ins_sys == 0) {
                    next EACH_UPG;
                } elsif(not defined($Upgrades->{'WALL_INS'}->{"$ins_key"})) {
                    print "Warning: Wall insulation system $ins_sys undefined, skipping\n";
                    next EACH_UPG;
                } else {
                    $UPGrecords = &upgradeWallIns($house_name,$Upgrades->{'WALL_INS'},$Surface->{"_$house_name"},$setPath,$UPGrecords);
                    if($Upgrades->{'INC_AIRTIGHT'}) {
                        if (not defined $hAirtight->{$upg}) {die "There is not airtightness efficacy associated with $upg\n";}
                        my $sThisDecade = $hDwellChar->{"$house_name"}->{'decade'};
                        $fThisDecreaseAch+=$hAirtight->{$upg}->{"_$region"}->{"_$sThisDecade"};
                    };
                };
            }
            case "GLZ" {
                my $GlazeSystem = $Upgrades->{'GLZ'}->{'GlzSystem'};
                if($GlazeSystem == 0) {
                    next EACH_UPG;
                } elsif(not defined($GlazeSystem)) {
                    print "Warning: Glazing system $GlazeSystem undefined, skipping\n";
                    next EACH_UPG;
                } else {
                    $GlazeSystem = 'GLZ_' . "$GlazeSystem";
                    $UPGrecords = &upgradeGLZ($house_name,$Upgrades->{'GLZ'}->{"$GlazeSystem"},$Surface->{"_$house_name"},$setPath,$UPGrecords);
                    # Add the effect on airtightness
                    if($Upgrades->{'INC_AIRTIGHT'}) {
                        if (not defined $hAirtight->{$upg}) {die "There is not airtightness efficacy associated with $upg\n";}
                        my $sThisDecade = $hDwellChar->{"$house_name"}->{'decade'};
                        $fThisDecreaseAch+=$hAirtight->{$upg}->{"_$region"}->{"_$sThisDecade"};
                    };
                };
            }
            case "PV_ROOF" {
                # Upgrade handled by external script
                if($Upgrades->{'PV_ROOF'}->{'bIsAdd'} == 0) {
                    next EACH_UPG;
                } elsif($Upgrades->{'PV_ROOF'}->{'bIsAdd'} == 1) {
                    $isPVupgrade = 1;
                } else {
                    print "WARNING: PV_ROOF Input upgrade data bIsAdd value of $Upgrades->{'PV_ROOF'}->{'bIsAdd'} invalid. Skipping\n";
                    next EACH_UPG;
                }
            }
            case "DH_SYSTEM" {
                my $DHsysNumber = $Upgrades->{'DH_SYSTEM'}->{'SysNumber'};
                if($DHsysNumber < 1) {
                    next EACH_UPG;
                } else { # There is a district heating system, update the ESP-r files
                    ($UPGrecords,$bPrintDHW) = &upgradeDHsystem($house_name,$Upgrades->{'DH_SYSTEM'},$Surface->{"_$house_name"},$set_name,$setPath,$UPGrecords);
                    $isDHupgrade = 1;
                };
            }
            else {print "$upg is not a recognized upgrade. Skipping\n";}
        
        };
    }; # END EACH_UPG

    # Reduce infiltration due to upgrades
    UPDATE_INF: {
        my $iVentType; # The ventilation system to be upgraded to
        my $sVentType; # The ventilation system to be upgraded to (string)
        my $fVentFlowRequired; # Required ventilation flow rate according to ASHRAE Standard 62.2
        my $iVentTypeORG; # The original dwelling ventilation system type
        my $fCurrentVent; # The original dwelling ventilation flow rate [L/s]
        
        # Update the AIM-2 file if required
        if($fThisDecreaseAch != 0){
            $UPGrecords = &setNewInfil($house_name,$fThisDecreaseAch,$setPath,$UPGrecords);
        };
        
        # Check the ventilation requirements [L/s]
        $fVentFlowRequired = &getDwellingVentilationRate($house_name,"$setPath$house_name/");
        $UPGrecords->{'VNT'}->{"$house_name"}->{'Reqd_Vent_Ls'} = $fVentFlowRequired;
    
        # Determine if there is an existing ventilation system
        $iVentTypeORG = &getVentType($house_name,"$setPath$house_name/");
        $UPGrecords->{'VNT'}->{"$house_name"}->{'orig_CVS'} = $iVentTypeORG;
        
        # If there is a ventilation system, retrieve the flow rate
        if($iVentTypeORG>1) {
            $fCurrentVent = &getVentFlowRate($house_name,"$setPath$house_name/",$iVentTypeORG);
        } else {
            $fCurrentVent = 0.0;
        };
        $UPGrecords->{'VNT'}->{"$house_name"}->{'orig_Vent_Ls'} = $fCurrentVent;
        
        # Add/upgrade ventilation system if required/requested
        if($Upgrades->{'VNT'}->{'vent_sys'} > 0) {

            # Determine the user-prescribed ventilation system type to upgrade to
            my $iUPGvent = $Upgrades->{'VNT'}->{'vent_sys'};
            if($iUPGvent==2) { # Upgrade to HRV
                $iVentType = 2;
                $sVentType = 'HRV';
            } elsif($iUPGvent==3) { # Upgrade to ERV (NOT IMPLEMENTED)
                #$iVentType = 4;
                #$sVentType = 'ERV';
                $iVentType = 2;
                $sVentType = 'HRV';
                print "Warning: ERV is not a valid update type yet. Setting to HRV\n";
            } elsif($iUPGvent==1) { # Fans with no heat recovery
                $iVentType = 3;
                $sVentType = 'FAN';
            } else {
                die "VNT: vent_sys type $iUPGvent not supported.\n";
            };

            # Determine if an upgrade needs to occur
            if(($fCurrentVent<$fVentFlowRequired) || ($iVentTypeORG!=2)) {
                $UPGrecords = &setVNTfile($house_name,"$setPath$house_name/",$iVentType,$sVentType,$fVentFlowRequired,$Upgrades->{'VNT'},$UPGrecords);
            };
        };
    }; # END UPDATE_INF
    
}; # END APPL_UPG

# --------------------------------------------------------------------
# Apply PV upgrade to all eligible dwellings (if requested)
# --------------------------------------------------------------------
ADD_PV: if ($isPVupgrade) {
    print "Calling PV upgrade script\n";
    # Clear any summary files
    unlink "../summary_files/Add_PV_UPG_$BaseSet" . '_Houses.csv';
    
    # Call script to add PV upgrade
    my $PVset = $set_name;
    $PVset =~s/^_//;
    my @PVargs = ("Add_PV.pl", "$hse_type_num", "$region_num","UPG_$BaseSet","0");
    system($^X, @PVargs);
};


# If required, update the input.xml
UPDATE_XML: {
    my $XMLTemplate;
    if ((($isPVupgrade) && ($bPrintDHW)) || $bPrintDHW){
        $XMLTemplate =  'h3k_DH_PV.xml';
    #} elsif($Upgrades->{'PV_ROOF'}->{'bIsAdd'} == 1) { # THIS IS DONE IN THE Add_PV.pl script
    #    $XMLTemplate =  'h3k_PV.xml';
    } elsif($isDHupgrade) { # Just space heating and electrical demands
        $XMLTemplate =  'h3k_SH_PV.xml';
    } else { # Just electrical community demands
        $XMLTemplate =  'h3k_PV.xml';
    };
    foreach my $house_name (@houses_desired){
        my $ThisXMLPath = "$setPath" . "$house_name" . "/input.xml";
        rename $ThisXMLPath, "$ThisXMLPath.orig";
        unlink $ThisXMLPath;
        copy("../Input_upgrade/$XMLTemplate",$ThisXMLPath) or die "Copy of $XMLTemplate failed: $!";
    };
};

# --------------------------------------------------------------------
# Save the upgrades info
# --------------------------------------------------------------------
UPG_OUT: {
    my $xmlOut = "../summary_files/UPG_$BaseSet" . "_Info.xml";
    open (my $outFID, '>', $xmlOut) or die ("Can't open datafile: $xmlOut");	# open writeable file
    print $outFID XMLout($UPGrecords, keyattr => []);	# printout the XML data
    close $outFID;
    #print Dumper $UPGrecords;
};