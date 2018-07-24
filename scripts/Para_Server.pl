#!/usr/bin/perl

use warnings;
use strict;

use XML::Simple;	# to parse the XML databases
use Cwd;
use Archive::Tar;
use File::Find;
use File::Copy;
use Data::Dumper; # For debugging

use lib qw(./modules);
use General;

# Global variables
my @Ceiling = (0,1,2,3);
my @Basement = (0,1,2,3);
my @Windows = (0,1,2,3);
my @Walls = (0,1,2,3);
my @VNT = (1,2);

my @sSkipList; # Array of strings holding sets to be skipped

my $hse_type_num;
my $region_num;
my $set_name;
my $hse_types;
my $regions;
my $BaseSet;
my $InternalSet;
my $cores;
my $sSignal = "../../Deposit/Signal.txt";
my $sSkipFile = "ToSkip.txt";

# Each houses extensions
my @sResExtensions;
#push (@sResExtensions, qw(csv bps xml cfg xml.orig));
push (@sResExtensions, qw(csv bps));

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if (@ARGV < 4) {die "A minimum Four arguments are required: house_types regions set_name core_information\n";};
    
	$hse_type_num = shift (@ARGV);
    $region_num = shift (@ARGV);
    $set_name = shift (@ARGV);
    ($hse_types, $regions, $BaseSet) = &hse_types_and_regions_and_set_name($hse_type_num, $region_num, $set_name);
    # Identify this set as an upgrade
	$InternalSet = '_UPG_' . $BaseSet;
    
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
};

# Load the original input file
my $Upgrades = XMLin("../Input_upgrade/Input_All_UPG.xml", keyattr => [], forcearray => 0);
rename "../Input_upgrade/Input_All_UPG.xml", "../Input_upgrade/Input_All_UPG.xml.orig";
unlink "../Input_upgrade/Input_All_UPG.xml";

# Load the skip list
if (-e $sSkipFile) {
    open (my $fh, '<', $sSkipFile) or die ("Can't open datafile: $sSkipFile");	# open readable file
    @sSkipList=<$fh>;
    close $fh;
    for(my $i=0;$i<=$#sSkipList;$i++){
        $sSkipList[$i]=~ s/^\s+|\s+$//g;
    };
};

foreach my $ceil (@Ceiling) {
    foreach my $base (@Basement) {
       foreach my $wind (@Windows) {
            foreach my $wall (@Walls) {
                INNER: foreach my $aim (@VNT) {
                    # Check wait until the files from the last simulations have been collected
                    while (-e $sSignal) {
                        sleep 30;
                    };
                
                    # Set name for this batch of sims
                    #=======================================================
                    my $sBatch = "$ceil" . "_$aim" . "_$base" . "_$wind" . "_$wall";
                    
                    # Check to see if this set needs to be simulated
                    #=======================================================
                    if (-e $sSkipFile) {
                        my @sMatches = grep(/^($sBatch)$/,@sSkipList);
                        if (@sMatches) {next INNER;}
                    };
                    
                    # Update the inputs
                    #=======================================================
                    $Upgrades->{'CEIL_INS'}->{'ins_sys'}=$ceil;
                    $Upgrades->{'VNT'}->{'vent_sys'}=$aim;
                    $Upgrades->{'BASE_INS'}->{'ins_sys'}=$base;
                    $Upgrades->{'GLZ'}->{'GlzSystem'}=$wind;
                    $Upgrades->{'WALL_INS'}->{'RSI_goal'}=$wall;
                    
                    # Write the new input file
                    #=======================================================
                    my $xmlPath = "../Input_upgrade/Input_All_UPG.xml";
                    open (my $xmlFID, '>', $xmlPath) or die ("Can't open datafile: $xmlPath");	# open writeable file
                    print $xmlFID XMLout($Upgrades, keyattr => []);	# printout the XML data
                    close $xmlFID;
                    
                    # Call the simulation script
                    #=======================================================
                    my $sCoreArg = "$cores->{'num'}/$cores->{'low'}/$cores->{'high'}";
                    my @PVargs = ("Sim_Upgrades.pl", "$hse_type_num", "$region_num","$set_name","$sCoreArg");
                    system($^X, @PVargs);
                    
                    # Call the Results script
                    #=======================================================
                    my $sResSetName = "UPG_$set_name";
                    #@PVargs = ("Results.pl", "$hse_type_num", "$region_num","$sResSetName","$sCoreArg");
                    @PVargs = ("Results.pl", "$hse_type_num", "$region_num","$sResSetName","$sCoreArg");
                    system($^X, @PVargs);
                    
                    # Collect and archive data
                    #=======================================================
                    my $sThisFolder = "../../Deposit/$sBatch";
                    mkdir $sThisFolder;
                    
                    # Navigate to project folder
                    my $sPathFiles = "../". $hse_types->{$hse_type_num} . $InternalSet . '/' . $regions->{$region_num};
                    # Get all the houses
                    my @files=();
                    opendir( my $DIR, $sPathFiles );
                    while ( my $entry = readdir $DIR ) {
                        next unless -d $sPathFiles . '/' . $entry;
                        next if $entry eq '.' or $entry eq '..';
                        push(@files,$entry);
                    }
                    closedir $DIR;
    
                    # Collect all output from each house
                    foreach my $sHouseName (@files) {
                        mkdir $sThisFolder."/$sHouseName";
                        foreach my $extens (@sResExtensions) {
                            move($sPathFiles."/$sHouseName/$sHouseName".".$extens" ,$sThisFolder."/$sHouseName/$sHouseName".".$extens");
                        };
                        #move($sPathFiles."/$sHouseName/input.xml" ,$sThisFolder."/$sHouseName/input.xml");
                    };
                    
                    # Store the summary data
                    @files = glob "../summary_files/Aggregate_*";
                    push(@files, glob "../summary_files/*_Info.xml");
                    push(@files, glob "../summary_files/*_Surfaces.xml");
                    push(@files, glob "../summary_files/*_Sim-Status_Core-*.txt");
                    push(@files, glob "../summary_files/Results_*_Houses.csv");
                    mkdir $sThisFolder . "/summary_files";
                    foreach my $CSV (@files) {
                        my $sThisHouse;
                        ($sThisHouse = $CSV) =~s/.*\///;
                        if($sThisHouse !~ m/^(Aggregate_DHW)/) {
                            move($CSV,$sThisFolder."/summary_files/$sThisHouse");
                        } else {
                            copy($CSV,$sThisFolder."/summary_files/$sThisHouse");
                        };
                    };
                    
                    # Archive the folders
                    # Create inventory of files & directories
                    my @inventory = ();
                    my $archive = $sBatch.".tar.gz";
                    my $sCurrentDir = getcwd;
                    chdir '../../Deposit';
                    find (sub { push @inventory, $File::Find::name }, $sBatch);
                    # Create a new tar object
                    my $tar = Archive::Tar->new();
                    $tar->add_files( @inventory );
                    # Write compressed tar file
                    $tar->write( $archive, 9 );
                    $tar->clear;
                    chdir $sCurrentDir;
    
                    # Clean out summary and UPG folder
                    #=======================================================
                    unlink "../Input_upgrade/Input_All_UPG.xml";
                    system("rm -rf $sThisFolder");
                    $sPathFiles = "../". $hse_types->{$hse_type_num} . $InternalSet;
                    system("rm -rf $sPathFiles");
                    
                    # Let the local machine know we are ready for the next pass
                    #=======================================================
                    open(my $fh, '>', $sSignal);
                    print $fh "Lets rock\n";
                    close $fh;
                };
            };
        };
    };
};

# All done. Clean up
rename "../Input_upgrade/Input_All_UPG.xml.orig", "../Input_upgrade/Input_All_UPG.xml";