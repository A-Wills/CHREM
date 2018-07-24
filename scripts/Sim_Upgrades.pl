#!/usr/bin/perl

# ====================================================================
# Sim_Upgrades.pl
# Author: Adam Wills
# Date: Jun 2016

# BASED UPON Sim_Control.pl
# Author: Lukas Swan
# Date: Oct 2009
# Copyright: Dalhousie University

# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all] [set_name]

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

use Data::Dumper;
use Parallel::ForkManager;
use XML::Simple;	# to parse the XML databases
use List::MoreUtils qw( minmax );
use Statistics::Descriptive;

# CHREM modules
use lib ('./modules');
use General;

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my $hse_types;	# declare an hash array to store the house types to be modeled (e.g. 1 -> 1-SD)
my $regions;	# declare an hash array to store the regions to be modeled (e.g. 1 -> 1-AT)
my $set_name;
my $InputSet;
my $cores;	# store the input core info
my @houses_desired; # declare an array to store the house names or part of to look
my @folders;	#declare an array to store the path to each hse which will be simulated
my $interval; # Number of houses to simulate on each core
my $Upgrades;   # HASH holding all the upgrade info
my $CurrentOS = $^O; # String naming the current 

my $hse_type_num;
my $region_num;
my $bRunTRNSYS = 0; # boolean to signal to run TRNSYS

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 4) {die "A minimum Four arguments are required: house_types regions set_name core_information\n";};
    
	$hse_type_num = shift (@ARGV);
    $region_num = shift (@ARGV);
	# Pass the input arguments of desired house types and regions to setup the $hse_types and $regions hash references
	($hse_types, $regions, $set_name) = &hse_types_and_regions_and_set_name($hse_type_num, $region_num, shift (@ARGV));

	# Check the cores arguement which should be three numeric values seperated by a forward-slash
	unless (shift(@ARGV) =~ /^([1-9]?[0-9])\/([1-9]?[0-9])\/([1-9]?[0-9])$/) {
		die ("CORE argument requires three Positive numeric values seperated by a \"/\": #_of_cores/low_core_#/high_core_#\n");
	};
	
	# set the core information
	# 'num' is total number of cores (if only using a single QC (quad-core) then 8, if using two QCs then 16
	# 'low' is starting core, if using two QCs then the first QC has a 1 and the second QC has a 9
	# 'high' is ending core, value is 8 or 16 depending on machine
	@{$cores}{'num', 'low', 'high'} = ($1, $2, $3);
	
	# check the core infomration for validity
	unless (
		$cores->{'num'} >= 1 &&
		($cores->{'high'} - $cores->{'low'}) >= 0 &&
		($cores->{'high'} - $cores->{'low'}) <= $cores->{'num'} &&
		$cores->{'low'} >= 1 &&
		$cores->{'high'} <= $cores->{'num'}
		) {
		die ("CORE argument numeric values are inappropriate (e.g. high_core > #_of_cores)\n");
	};

	# In case no houses were provided, match everything
	@houses_desired = '.';
    
    # Update the set name
    $InputSet = $set_name;
    $set_name = "_UPG_$set_name";
};

# --------------------------------------------------------------------
# Load the upgrade inputs. If there is no upgrades, die
# --------------------------------------------------------------------
$Upgrades = XMLin("../Input_upgrade/Input_All_UPG.xml", keyattr => [], forcearray => 0);

#--------------------------------------------------------------------
# Apply the upgrades to the set
#--------------------------------------------------------------------
APPL_UP:{
    print "  =====        Calling Upgrades Script       =====\n\n";
    my @PVargs = ("Upgrade_City.pl", "$hse_type_num", "$region_num","$InputSet");
    system($^X, @PVargs);
    print "\n  =====                  Done                =====\n\n";
};

#--------------------------------------------------------------------
# Identify the house folders for simulation
#--------------------------------------------------------------------
FIND_FOLDERS: foreach my $hse_type (&array_order(values %{$hse_types})) {		#each house type
	foreach my $region (&array_order(values %{$regions})) {		#each region
		push (my @dirs, <../$hse_type$set_name/$region/*>);	#read all hse directories and store them in the array
 		#print Dumper @dirs;
		CHECK_FOLDER: foreach my $dir (@dirs) {
			# cycle through the desired house names to see if this house matches. If so continue the house build
			foreach my $desired (@houses_desired) {
				# it matches, so set the flag
				if ($dir =~ /\/$desired/) {
					push (@folders, $dir);
					next CHECK_FOLDER;
				};
			};
		};
	};
}; # END FIND_FOLDERS

#--------------------------------------------------------------------
# Determine how many houses go to each core for core usage balancing
#--------------------------------------------------------------------
$interval = int(@folders/$cores->{'num'});	#round up to the nearest integer

#--------------------------------------------------------------------
# Delete old simulation summary files
#--------------------------------------------------------------------
foreach my $file (<../summary_files/*>) { # Loop over the files
	my $check = 'Sim' . $set_name . '_';
	if ($file =~ /$check/) {unlink $file;};
};

#--------------------------------------------------------------------
# Generate and print lists of directory paths for each core to simulate
#--------------------------------------------------------------------
SIMULATION_LIST: {
	foreach my $core (1..$cores->{'num'}) {
		my $low_element = ($core - 1) * $interval;	#hse to start this particular core at
		my $high_element = $core * $interval - 1;	#hse to end this particular core at
		if ($core == $cores->{'num'}) { $high_element = $#folders};	#if the final core then adjust to end of array to account for rounding process
		my $file = '../summary_files/Sim' . $set_name . '_House-List_Core-' . $core . '.csv';
		open (HSE_LIST, '>', $file) or die ("can't open $file");	#open the file to print the list for the core
		foreach my $element ($low_element..$high_element) {
			if (defined($folders[$element])) {
				print HSE_LIST "$folders[$element]\n";	#print the hse path to the list
			};
		}
		close HSE_LIST;		#close the particular core list
	};
};

#--------------------------------------------------------------------
# Call the simulations.
#--------------------------------------------------------------------
SIMULATION: {
    print "  ===== Multithreading the ESP-r simulations =====\n\n";
    my $sCoreSim;
    # Determine which simulation core script to use based on OS
    if($CurrentOS =~ m/MSWin32/) { # Windows
        $sCoreSim = "perl Core_Sim.pl";
    } else { # linux
        $sCoreSim = "./Core_Sim.pl";
    };
    
    my $n_processes = $cores->{'num'};
    my $pm = Parallel::ForkManager->new( $n_processes );
	foreach my $core ($cores->{'low'}..$cores->{'high'}) {	#simulate the appropriate list (i.e. QC2 goes from 9 to 16)
		my $file = '../summary_files/Sim' . $set_name . '_Core-Output_Core-' . $core . '.txt';
        $pm->start and next;
		system ("$sCoreSim $core $set_name > $file");	#pass the argument $core so the program knows which set to simulate
        $pm->finish;
	}
    $pm->wait_all_children;
	print "     - THE SIMULATION OUTPUTS FOR EACH CORE ARE LOCATED IN ../summary_files/\n";
    print "\n  =====                  Done                =====\n\n";
};

#--------------------------------------------------------------------
# Aggregate the electrical and thermal demands
#--------------------------------------------------------------------
AGGREGATE: if(($Upgrades->{'DH_SYSTEM'}->{'SysNumber'} > 0) || ($Upgrades->{'PV_ROOF'}->{'bIsAdd'} == 1)) {
     print "  =====          Aggregating the loads       =====\n\n";
     setAggregateLoads(\@folders,$set_name);
     print "\n  =====                  Done                =====\n\n";
};

#--------------------------------------------------------------------
# Post-process and save the data
#--------------------------------------------------------------------
#ESPrPost: {
#    # Run the base CHREM results
#    print "  =====    Running CHREM Results Processor   =====\n";
#    my @RESargs = ("Results.pl", "$hse_type_num", "$region_num","UPG_$InputSet", "1/1/1");
#    system($^X, @RESargs);
#    print "  =====                  Done                =====\n\n";
#};


#--------------------------------------------------------------------
# Call TRNSYS simulation (if required)
#--------------------------------------------------------------------
#TRNSYS: {
#    # Check if we need to run TRNSYS
#    if ($Upgrades->{'DH_SYSTEM'}->{'bIsAdd'} == 1) {
#        $bRunTRNSYS = 1;
#    };
#    if($bRunTRNSYS){};
#};
#--------------------------------------------------------------------
# TODO: Post-process and report performance metrics
#--------------------------------------------------------------------
#--------------------------------------------------------------------
# SUBROUTINES
#--------------------------------------------------------------------
SUBROUTINES: {
    sub setAggregateLoads{
        # INPUTS
        
        my $ref_Folder = shift;
        my $setName = shift;
        my @folders = @$ref_Folder;
        
        # INTERMEDIATES
        my @Time; # Present day of the year
        my @DHW; # Community aggregated DHW demand [W]
        my @DHWcall; # How many dwellings are calling for DHW at each timestep [-]
        my @Heat; # Community-aggregated heating demand [W]
        my @HeatCall; # How many dwellings are calling for space heating at each timestep [-]
        my @Elec; # Community-aggregated electrical demand [W] (Negative=import, Positive=export)
        my $bStoreTime=1;
        
        # Loop through each record
        foreach my $record (@folders) {
            my $hse_name = $record;
            $hse_name =~ s{.*/}{};
            
            if($hse_name =~ m/(BCD)/) {next;} 
            
            my $sThisOut = $record . "/$hse_name.csv";
            
            # Open the timestep data
            open my $fid, $sThisOut or print "setAggregateLoads: Could not open $sThisOut\n";
            my @lines = <$fid>; # Pull entire file into an array
            close $fid;
            
            # Process the header
            my $HeaderString = shift @lines;
            my $iTime;
            my $iDHW;
            my @iHeat;
            my $iImport;
            my $iExport;
            
            my @Headers = split ',', $HeaderString;
            for(my $i=0; $i<=$#Headers;$i++) {
                if($Headers[$i] =~ m/(present)/) {
                    $iTime = $i;
                } elsif($Headers[$i] =~ m/(water)/) {
                    $iDHW = $i;
                } elsif($Headers[$i] =~ m/(GN Heat)/) {
                    push(@iHeat,$i);
                } elsif($Headers[$i] =~ m/(net import)/) {
                    $iImport = $i;
                } elsif($Headers[$i] =~ m/(net export)/) {
                    $iExport = $i;
                };
            };

            # Initialize arrays (if first pass)
            if($bStoreTime) {
                my $iNumRows = scalar @lines;
                if(defined $iDHW) {
                    @DHW = (0) x $iNumRows;
                    @DHWcall = (0) x $iNumRows;
                };
                if(@iHeat) {
                    @Heat = (0) x $iNumRows;
                    @HeatCall = (0) x $iNumRows;
                };
                if((defined $iExport) && (defined $iExport)){@Elec = (0) x $iNumRows;}
            };
            
            # Loop through all the data
            for(my $i=0; $i<=$#lines;$i++) {
                my @LineData = split ',', $lines[$i];
                
                # Store the time data (if first pass)
                if($bStoreTime) {push(@Time, $LineData[$iTime]);}
                
                # Update the DHW load of the community (W)
                if(defined $iDHW) {
                    $DHW[$i] += $LineData[$iDHW];
                    if($LineData[$iDHW]>0) {$DHWcall[$i]++;}
                };
                
                # Update community electrical consumption (W)
                if((defined $iExport) && (defined $iExport)){$Elec[$i] = $Elec[$i] + $LineData[$iExport] - $LineData[$iImport];}
                
                # Update community heating demand (W)
                if(@iHeat) {
                    my $ThisHeat = 0;
                    foreach my $zone (@iHeat) {
                        $ThisHeat += $LineData[$zone];
                    };
                    $Heat[$i] += $ThisHeat;
                    if($ThisHeat>0) {$HeatCall[$i]++;}
                };
            };
            
            $bStoreTime = 0; # Signal that at least one pass of the loop has occurred 
        };
        
        #Peak and min load data
        my @PeakMin;
        
        # Save the aggregated  electrical load
        PRINT_AGG_ELEC: if(@Elec) {
            my $sAggPath = "../summary_files/Aggregate_Electrical$setName.csv";
            unlink $sAggPath;
            open my $out, '>', $sAggPath or die "Can't write $sAggPath: $!";
            
            # Determine the timestep
            my $fTStep = ($Time[1]-$Time[0])*1440; # Timestep [min]
            $fTStep = sprintf "%.0f", $fTStep;
            print $out "timestep [min],$fTStep\n";
            
            # Print the headers
            print $out "present day,Electric Export [W]\n";
            for(my $i=0; $i<=$#Time;$i++) {
                print $out "$Time[$i],$Elec[$i]\n";
            };
            close $out;
            
            # Print the headers
            #print $out "present day,DHW Demand [W],Heating Demand [W],Electric Export [W]\n";
            #for(my $i=0; $i<$#Time;$i++) {
            #    print $out "$Time[$i],$DHW[$i],$Heat[$i],$Elec[$i]\n";
            #};
            #close $out;
            
            # Determine peak and minimum aggregate load
            my ($min, $max) = minmax @Elec;
            my $FindBase = Statistics::Descriptive::Full->new();
                $FindBase->add_data(\@Elec);
                my $Baseld=$FindBase->percentile(5);
                my $this95=$FindBase->percentile(95);
                my $mean = $FindBase->mean();
                my $median = $FindBase->median();
                my $StdDev = $FindBase->standard_deviation();
            $FindBase->clear();
            push(@PeakMin,"Max. Electrical Demand: $max W\n");
            push(@PeakMin,"Min. Electrical Demand: $min W\n");
            push(@PeakMin,"Mean Electrical Demand: $mean W\n");
            push(@PeakMin,"Median Electrical Demand: $median W\n");
            push(@PeakMin,"Standard Deviation Electrical Demand: $StdDev W\n");
            push(@PeakMin,"5th percentile Electrical Demand: $Baseld W\n");
            push(@PeakMin,"95th percentile Electrical Demand: $this95 W\n\n");
        };
        
        # Save the aggregated space heating load
        PRINT_AGG_SH: if(@Heat) {
            my $sAggPath = "../summary_files/Aggregate_SpaceHeat$setName.csv";
            unlink $sAggPath;
            open my $out, '>', $sAggPath or die "Can't write $sAggPath: $!";
            
            # Determine the timestep
            my $fTStep = ($Time[1]-$Time[0])*1440; # Timestep [min]
            $fTStep = sprintf "%.0f", $fTStep;
            print $out "timestep [min],$fTStep\n";
            
            # Print the headers
            print $out "present day,Heating Demand [W],Num Call [-]\n";
            for(my $i=0; $i<=$#Time;$i++) {
                print $out "$Time[$i],$Heat[$i],$HeatCall[$i]\n";
            };
            close $out;
            
            my ($min, $max) = minmax @Heat;
            my $FindBase = Statistics::Descriptive::Full->new();
                $FindBase->add_data(\@Heat);
                my $Baseld=$FindBase->percentile(5);
                my $this95=$FindBase->percentile(95);
                my $mean = $FindBase->mean();
                my $median = $FindBase->median();
                my $StdDev = $FindBase->standard_deviation();
            $FindBase->clear();
            push(@PeakMin,"Max. Space Heating Demand: $max W\n");
            push(@PeakMin,"Min. Space Heating Demand: $min W\n");
            push(@PeakMin,"Mean Space Heating Demand: $mean W\n");
            push(@PeakMin,"Median Space Heating Demand: $median W\n");
            push(@PeakMin,"Standard Deviation Space Heating Demand: $StdDev W\n");
            push(@PeakMin,"5th percentile Space Heating Demand: $Baseld W\n");
            push(@PeakMin,"95th percentile Space Heating Demand: $this95 W\n\n");
        };
        
        # Save the aggregated space heating load
        PRINT_AGG_DHW: if(@DHW) {
            my $sAggPath = "../summary_files/Aggregate_DHW$setName.csv";
            unlink $sAggPath;
            open my $out, '>', $sAggPath or die "Can't write $sAggPath: $!";
            
            # Determine the timestep
            my $fTStep = ($Time[1]-$Time[0])*1440; # Timestep [min]
            $fTStep = sprintf "%.0f", $fTStep;
            print $out "timestep [min],$fTStep\n";
            
            # Print the headers
            print $out "present day,DHW Demand [W],Num Call [-]\n";
            for(my $i=0; $i<=$#Time;$i++) {
                print $out "$Time[$i],$DHW[$i],$DHWcall[$i]\n";
            };
            close $out;
            my ($min, $max) = minmax @DHW;
            my $FindBase = Statistics::Descriptive::Full->new();
                $FindBase->add_data(\@DHW);
                my $Baseld=$FindBase->percentile(5);
                my $this95=$FindBase->percentile(95);
                my $mean = $FindBase->mean();
                my $median = $FindBase->median();
                my $StdDev = $FindBase->standard_deviation();
            $FindBase->clear();
            push(@PeakMin,"Max. DHW Demand: $max W\n");
            push(@PeakMin,"Min. DHW Demand: $min W\n");
            push(@PeakMin,"Mean DHW Demand: $mean W\n");
            push(@PeakMin,"Median DHW Demand: $median W\n");
            push(@PeakMin,"Standard Deviation DHW Demand: $StdDev W\n");
            push(@PeakMin,"5th percentile DHW Demand: $Baseld W\n");
            push(@PeakMin,"95th percentile DHW Demand: $this95 W\n\n");
            
        };
        
        if(@Heat && @DHW) {
            my @Aggregate;
            for (my $i=0;$i<=$#Heat;$i++) {
                push(@Aggregate,($Heat[$i]+$DHW[$i]));
            };
            my ($min, $max) = minmax @Aggregate;
            my $FindBase = Statistics::Descriptive::Full->new();
                $FindBase->add_data(\@Aggregate);
                my $Baseld=$FindBase->percentile(5);
                my $this95=$FindBase->percentile(95);
                my $mean = $FindBase->mean();
                my $median = $FindBase->median();
                my $StdDev = $FindBase->standard_deviation();
            $FindBase->clear();
            push(@PeakMin,"Max. Thermal Demand: $max W\n");
            push(@PeakMin,"Min. Thermal Demand: $min W\n");
            push(@PeakMin,"Mean Thermal Demand: $mean W\n");
            push(@PeakMin,"Median Thermal Demand: $median W\n");
            push(@PeakMin,"Standard Deviation Thermal Demand: $StdDev W\n");
            push(@PeakMin,"5th percentile Thermal Demand: $Baseld W\n");
            push(@PeakMin,"95th percentile Thermal Demand: $this95 W\n\n");
        }
        
        if(@PeakMin) {
            my $sAggPath = "../summary_files/Aggregate_PeakBase$setName.txt";
            unlink $sAggPath;
            open my $out, '>', $sAggPath or die "Can't write $sAggPath: $!";
            
            foreach my $item (@PeakMin) {
                print $out $item;
            };
            close $out;
        };
        
        return 0;
    }; # END sub setAggregateLoads

}; # END SUBROUTINES