# ====================================================================
# Database.pm
# Author: Lukas Swan
# Date: July 2009
# Copyright: Dalhousie University
# ====================================================================
# The following subroutines are included in the perl module:
# database_XML: this file reads the XML files and generates ESP-r database and passes the info back to the calling program
# ====================================================================

# Declare the package name of this perl module
package Database;

# Declare packages used by this perl module
use strict;
use XML::Simple;	# to parse the XML databases
use Data::Dumper;

# Set the package up to export the subroutines for local use within the calling perl script
require Exporter;
our @ISA = qw(Exporter);

# Place the routines that are to be automatically exported here
our @EXPORT = qw(database_XML AddArchetypedatabase_XML);
# Place the routines that must be requested as a list following use in the calling script
our @EXPORT_OK = ();

# ====================================================================
# database_XML
# This subroutine generates the esp-r database files to facilitate opening 
# CSDDRD houses within prj. This script reads the material and 
# composite construction XML databases and generates the appropriate 
# ASCII columnar delimited format files required by ESP-r. It then passes
# back the XML information in hash format to the calling program for use
# ====================================================================

sub database_XML {
	my $mat_data;	# declare repository for mat_db.xml readin
	my $con_data;	# declare repository for con_db.xml readin
	my $optic_data;	# declare a hash ref to store the optical data from optic_db.xml
	my $cfc_data;	# declare a hash ref to store the CFC optical data from cfc_db.xml
	my  $pln_data; # declare a hash ref to store the plant component data from plant_db.xml

	MATERIALS: {
		$mat_data = XMLin("../databases/mat_db.xml");	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
		my $date_time = $mat_data->{'date'}; # Record the date for backwards compatibility with the next line
		$mat_data = \%{$mat_data->{'material'}};	# link straight to the material names so we don't have 'material' in the way
		$mat_data->{'Gap'}->{'number'} = 0; # Set the gap material number to zero

# 		open (MAT_DB_XML, '>', "../databases/mat_db_regen.xml") or die ("can't open  ../databases/mat_db_regen.xml");	# open a writeout file
# 		print MAT_DB_XML XMLout ($mat_data);	# printout the XML data
# 		close MAT_DB_XML;
		
		# create a listing by class so that we can organize the data into classes
		my $mat_class;
		foreach my $mat (keys %{$mat_data}) {
			# store a reference to the material data within the class type under that name
			$mat_class->{$mat_data->{$mat}->{'class'}}->{$mat} = \%{$mat_data->{$mat}};
			
			# also store the name within the material - this is redundant, but may be used in Hse_Gen
			$mat_data->{$mat}->{'name'} = $mat;
		};
		
		# delete the gap reference, because ESP-r does not use it
		delete ($mat_class->{'Gap'});
# 		print Dumper $mat_class;

		NEW_FORMAT: {	# the tagged format version 1.1
			open (MAT_DB, '>', "../databases/mat_db_xml_1.1.a") or die ("can't open  ../databases/mat_db_xml_1.1.a");	# open a writeout file

			print MAT_DB "*Materials 1.1\n";	# print the head tag line
			my $time = localtime();	# determine the time
			printf MAT_DB ("%s,%s\n", "*date", $date_time);	# print the time
			print MAT_DB "*doc,Materials database (tagged format) constructed from mat_db.xml by Database.pm\n#\n";	# print the documentation tag line

			my $classes = keys (%{$mat_class});
			printf MAT_DB ("%u %s", $classes,"# total number of classes\n#\n");	# print the number of classes

			# specification of file format
			printf MAT_DB ("%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
				"# Material classes are listed as follows:",
				"#	*class, 'class number'(2 digits),'number of materials in class','class name'",
				"#	'class description",
				"#",
				"# Materials within each class are listed as follows:",
				"#	*item,'material name','material number'(20 * 'class number' + 'material position within class'; 3 digits),'class number'(2 digits),'material description'",
				"# The material tag is followed by the following material attributes:",
				"#	conductivity (W/(m-K), density (kg/m**3), specific heat (J/(kg-K),",
				"#	emissivity out (-), emissivity in (-), absorptivity out, (-) absorptivity in (-),",
				"#	diffusion resistance (?), default thickness (mm),",
				"#	flag [-] legacy [o] opaque [t] transparent [g] gas data+T cor [h] gas data at 4T",
				"#",
				"#	transparent material include additional attributes:",
				"#		longwave tran (-), solar direct tran (-), solar reflec out (-), solar refled in (-),",
				"#		visable tran (-), visable reflec out (-), visable reflec in (-), colour rendering (-)"
			);

			my $class_num = 0;
			my $mat_num = 0;

			foreach my $class (sort {$a cmp $b} keys (%{$mat_class})) {	# iterate over each class
				$class_num++;

				print MAT_DB "#\n#\n# CLASS\n";	# print a common identifier

				my @mats = sort {$a cmp $b} keys (%{$mat_class->{$class}});
				my $mats = @mats;

				printf MAT_DB ("%s,%u,%u,%s\n",	# print the class information
					"*class",	# class tag
					$class_num,	# class number
					$mats,	# number of materials in the class
					"$class"	# class name
				);
				print MAT_DB "$class class includes the following materials: @mats\n";	# print the class description

				print MAT_DB "#\n# MATERIALS\n";	# print a common identifier
				
				# setup the material number to the next 10's - this is how ESP-r handles its classes
				if ($mat_num =~ /^(\d)(\d)(\d)\d$/) {
					$mat_num = $1 * 1000 + $2 * 100 + ($3 + 1) * 10;
				}
				elsif ($mat_num =~ /^(\d)(\d)\d$/) {
					$mat_num = $1 * 100 + ($1 + 1) * 10;
				}
				elsif ($mat_num =~ /^(\d)\d$/) {
					$mat_num = ($1 + 1) * 10;
				}
				elsif ($mat_num =~ /^(\d)$/) {
					if ($1 > 0) {
						$mat_num = 10
					};
				}
				else {die "MATERIALS DB: Too many materials - $mat_num\n";};


				foreach my $mat_name (sort {$a cmp $b} keys (%{$mat_class->{$class}})) {	# iterate over each material within the class
					$mat_num++;
					my $mat = \%{$mat_class->{$class}->{$mat_name}};
					$mat->{'number'} = $mat_num;

					printf MAT_DB ("%s,%s,%u,%u,%s\n",	# print the material title line
						'*item',	# material tag
						$mat_name,	# material name
						$mat_num,	# material number (groups of 20)
						$class_num,
						$mat->{'description'}	# material description
					);


					# print the first part of the material data line
					printf MAT_DB ("%.3f,", $mat->{'conductivity_W_mK'});
					printf MAT_DB ("%.0f,", $mat->{'density_kg_m3'});
					printf MAT_DB ("%.0f,", $mat->{'spec_heat_J_kgK'});
					foreach my $property ('emissivity_out', 'emissivity_in', 'absorptivity_out', 'absorptivity_in') {
						printf MAT_DB ("%.3f,", $mat->{$property});
					};
					printf MAT_DB ("%.0f,", $mat->{'vapor_resist'});
					printf MAT_DB ("%.1f,", $mat->{'default_thickness_mm'});	# this property has a different format but is on the same line

					if ($mat->{'type'} eq 'OPAQ') {print MAT_DB "o\n";} # opaque material so print last digit of line
					elsif ($mat->{'type'} eq 'TRAN') {	# translucent material so print t and additional data
						print MAT_DB 't,';	# print TRAN identifier
						# print the translucent properties
						foreach my $property ('trans_long', 'trans_solar', 'trans_vis', 'refl_solar_out', 'refl_solar_in', 'refl_vis_out', 'refl_vis_in') {
							printf MAT_DB ("%.3f,", $mat->{'optic_mat_props'}->{$property});
						};
						printf MAT_DB ("%.3f\n", $mat->{'optic_mat_props'}->{'clr_render'});	# print the last part of translucent properties line
					};
				};
			};
			print MAT_DB "*end\n";	# print the end tag
			close MAT_DB;
		};
	};


	OPTICS: {
		$optic_data = XMLin("../databases/optic_db.xml", ForceArray => ['layers']);	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
		
		foreach my $optic (keys %{$optic_data}) {
			#  store the name within the optic - this is redundant, but may be used in Hse_Gen
			$optic_data->{$optic}->{'name'} = $optic;
		};

		open (OPTIC_DB_XML, '>', "../databases/optics_db_regen.xml") or die ("can't open  ../databases/optics_db_regen.xml");	# open a writeout file
		print OPTIC_DB_XML XMLout($optic_data);	# printout the XML data
		close OPTIC_DB_XML;

		open (OPTIC_DB, '>', "../databases/optic_db_xml.a") or die ("can't open  ../databases/optic_db_xml.a");	# open a writeout file for the optics database
		open (OPTIC_LIST, '>', "../databases/optic_db_xml_list") or die ("can't open  ../databases/optic_db_xml_list");	# open a list file that will simply list the optic name and description 

		# provide the header lines and instructions to the optics database
		print OPTIC_DB "# optics database (columnar format) constructed from con_db.xml by DB_Gen.pl based on mat_db.xml\n#\n";

		# print the file format
		foreach my $statement (
			"# optical properties db for default windows and most of the information",
			"# required to automatically build transparent constructions & tmc files.",
			"#",
			"# 1st line of each item is column sensitive and holds:",
			"# an identifier (12 char) followed by a description",
			"# 2nd line holds:",
			"# a) the number of default (always 1?) and tmc layers (equal to construction)",
			"# b) visable trans ",
			"# c) solar reflectance (outside)",
			"# d) overall solar absorbed",
			"# e) U value (for reporting purposes only)",
			"# 3rd line holds:",
			"# a) direct solar tran at 0deg 40deg 55deg 70deg 80deg from normal",
			"# b) total heat gain at the same angles (for reporting purposes only)",
			"# then for each layer there is a line containing",
			"# a) refractive index",
			"# b) solar absorption at 0deg 40deg 55deg 70deg 80deg from normal",
			"#",
			"#"
			) {printf OPTIC_DB ("%s\n", $statement);
			};

		my @optics = sort {$a cmp $b} keys (%{$optic_data});	# sort optic types to order the printout


		foreach my $optic (sort {$a cmp $b} keys (%{$optic_data})) {

			my $opt = \%{$optic_data->{$optic}};	# shorten the name for subsequent use

			# fill out the optics database (TMC)
			printf OPTIC_DB ("%-14s%s\n",
				$optic,	# print the optics name
				": $opt->{'description'}"	# print the optics description
			);

			printf OPTIC_LIST ("%-14s%s\n",
				$optic,	# print the optics name
				": $opt->{'description'}"	# print the optics description
			);

			print OPTIC_DB "# $opt->{'optic_con_props'}->{'optical_description'}\n";	# print additional optical description

			# print the one time optical information
			printf OPTIC_DB ("%s%4d%7.3f%7.3f%7.3f%7.3f\n",
				"  1",
				$#{$opt->{'layers'}} + 1,
				$opt->{'optic_con_props'}->{'trans_vis'},
				$opt->{'optic_con_props'}->{'refl_solar_doc_only'},
				$opt->{'optic_con_props'}->{'abs_solar_doc_only'},
				$opt->{'optic_con_props'}->{'U_val_W_m2K_doc_only'}
			);

			# print the transmission and heat gain values at different angles for the construction type
			printf OPTIC_DB ("  %s %s\n",
				$opt->{'optic_con_props'}->{'trans_solar'},
				$opt->{'optic_con_props'}->{'heat_gain_doc_only'}
			);

			print OPTIC_DB "# layers\n";	# print a common identifier
			# print the refractive index and abs values at different angles for each layer of the transluscent construction type
			foreach my $layer (@{$opt->{'layers'}}) {	# iterate over construction layers
				printf OPTIC_DB ("  %4.3f %s\n",
					$layer->{'refr_index'},
					$layer->{'absorption'}
				);
			};
		};

		close OPTIC_DB;
		close OPTIC_LIST;
	};

	CONSTRUCTIONS: {
		$con_data = XMLin("../databases/con_db.xml", ForceArray => ['layers']);	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
		$con_data = \%{$con_data->{'construction'}};
		
		foreach my $con (keys %{$con_data}) {
			#  store the name within the optic - this is redundant, but may be used in Hse_Gen
			$con_data->{$con}->{'name'} = $con;
		};
		
# 		print Dumper $con_data;
# 		open (CON_DB_XML, '>', "../databases/con_db_regen.xml") or die ("can't open  ../databases/con_db_regen.xml");	# open a writeout file
# 		print CON_DB_XML XMLout($con_data);	# printout the XML data
# 		close CON_DB_XML;

		open (CON_DB, '>', "../databases/con_db_xml.a") or die ("can't open  ../databases/con_db_xml.a");	# open a writeout file for the constructions
		open (CON_LIST, '>', "../databases/con_db_xml_list") or die ("can't open  ../databases/con_db_xml_list");	# open a list file that will simply list the materials 

		print CON_DB "# composite constructions database (columnar format) constructed from con_db.xml by DB_Gen.pl based on mat_db.xml\n#\n";	# heading intro line
		print CON_LIST "# composite constructions database (columnar format) constructed from con_db.xml by DB_Gen.pl based on mat_db.xml\n#\n";	# heading intro line

		my $con_count = keys (%{$con_data});
		printf CON_DB ("%u %s\n", $con_count,"# total number of constructions\n#");	# print the number of constructions

		printf CON_DB ("%s\n%s\n%s\n",	# format instructions for the construction database
			"# for each construction list the: # of layers, construction name, type (OPAQ or TRAN or CFC), Optics name (or OPAQUE), symmetry.",
			"#\t followed by for each material of the construction:",
			"#\t\t material number, thickness (m), material name, and if 'Gap' then RSI at vert horiz and sloped"
		);

		foreach my $con_key (sort {$a cmp $b} keys (%{$con_data})) {	# iterate over each construction
			my $con = \%{$con_data->{$con_key}};
			print CON_DB "#\n#\n# CONSTRUCTION\n";	# print a common identifier

			printf CON_LIST ("%16s : %8s : %16s : %s\n", $con_key, $con->{'type'}, $con->{'symmetry'}, $con->{'description'});	# print the construction name and description to the list

			printf CON_DB ("%5d    %-14s%-6s", 	# print the construction information
				$#{$con->{'layers'}} + 1,	# number of layers in the construction
				$con_key,	# construction name
				$con->{'type'}	# type of construction (OPAQ or TRAN)
			);

			if ($con->{'type'} eq 'OPAQ') {printf CON_DB ("%-14s", 'OPAQUE');}	# opaque so no line to optics database
			elsif ($con->{'type'} eq 'CFC') {printf CON_DB ("%-14s", 'USE GSLedit');}      # CFC so should use cfc properties
			elsif ($con->{'type'} eq 'TRAN') {printf CON_DB ("%-14s", $con->{'optic_name'});};	# transluscent construction so link to the optics database


			printf CON_DB ("%-14s\n", $con->{'symmetry'});	# print symetrical or not

			print CON_DB "# $con_key Description: $con->{'description'}\n";	# print the construction description
			print CON_DB "#\n# MATERIALS\n";	# print a common identifier

			foreach my $layer (@{$con->{'layers'}}) {	# iterate over construction layers
# 				print Dumper $layer;
				printf CON_DB ("%5d%10.4f",	# print the layers number and name
					$mat_data->{$layer->{'mat'}}->{'number'},	# material number
					$layer->{'thickness_mm'} / 1000	# material thickness in (m)
				);

				if ($layer->{'mat'} eq 'Gap') {	# it is Gap based on material number zero
					# print the RSI properties of Gap for the three positions that the construction may be placed in
					printf CON_DB ("%s%4.3f %4.3f %4.3f\n",
						"  Gap  ",
						$layer->{'gap_RSI'}->{'vert'},
						$layer->{'gap_RSI'}->{'horiz'},
						$layer->{'gap_RSI'}->{'slope'}
					);
				}
				else {	# not Gap so simply report the name and descriptions
					print CON_DB "  $layer->{'mat'} : $mat_data->{$layer->{'mat'}}->{'description'}\n";	# material name and description from the list
				};

				print CON_LIST "\t$layer->{'mat'} : $layer->{'thickness_mm'} (mm) : $mat_data->{$layer->{'mat'}}->{'description'}\n";	# material name and description
			};
		};
		close CON_DB;
		close CON_LIST;
	};
	CFC:{
	    $cfc_data = XMLin("../databases/cfc_db.xml", ForceArray => ['layers_solar_normal', 'layers_visible_normal', 'layers_longwave_normal', 'gas_layers']);	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
# 	    $cfc_data = \%{$cfc_data->{'CFC_optics'}};
# 	    print Dumper $cfc_data;
	};
	
	PLN:{
	    $pln_data = XMLin("../databases/plant_db.xml", ForceArray => ['comp_data']); # Readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
	    $pln_data = \%{$pln_data->{'component'}};
# 	    
# 	    print Dumper $pln_data;
	};

	return ($mat_data, $con_data, $optic_data, $cfc_data, $pln_data);
};

# ====================================================================
# AddArchetypedatabase_XML
# This subroutine generates appends the construction, optics, and  
# materials database to include Archetype specific data.
# ====================================================================

sub AddArchetypedatabase_XML {
	my $mat_data=shift;	# declare repository for mat_db.xml readin
	my $con_data=shift;	# declare repository for con_db.xml readin
	my $optic_data=shift;	# declare a hash ref to store the optical data from optic_db.xml

	#MATERIALS: {
	#	$mat_data = XMLin("../databases/mat_db.xml");	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
	#	my $date_time = $mat_data->{'date'}; # Record the date for backwards compatibility with the next line
	#	$mat_data = \%{$mat_data->{'material'}};	# link straight to the material names so we don't have 'material' in the way
	#	$mat_data->{'Gap'}->{'number'} = 0; # Set the gap material number to zero
    #
# 	#	open (MAT_DB_XML, '>', "../databases/mat_db_regen.xml") or die ("can't open  ../databases/mat_db_regen.xml");	# open a writeout file
# 	#	print MAT_DB_XML XMLout ($mat_data);	# printout the XML data
# 	#	close MAT_DB_XML;
	#	
	#	# create a listing by class so that we can organize the data into classes
	#	my $mat_class;
	#	foreach my $mat (keys %{$mat_data}) {
	#		# store a reference to the material data within the class type under that name
	#		$mat_class->{$mat_data->{$mat}->{'class'}}->{$mat} = \%{$mat_data->{$mat}};
	#		
	#		# also store the name within the material - this is redundant, but may be used in Hse_Gen
	#		$mat_data->{$mat}->{'name'} = $mat;
	#	};
	#	
	#	# delete the gap reference, because ESP-r does not use it
	#	delete ($mat_class->{'Gap'});
# 	#	print Dumper $mat_class;
    #
	#	NEW_FORMAT: {	# the tagged format version 1.1
	#		open (MAT_DB, '>', "../databases/mat_db_xml_1.1.a") or die ("can't open  ../databases/mat_db_xml_1.1.a");	# open a writeout file
    #
	#		print MAT_DB "*Materials 1.1\n";	# print the head tag line
	#		my $time = localtime();	# determine the time
	#		printf MAT_DB ("%s,%s\n", "*date", $date_time);	# print the time
	#		print MAT_DB "*doc,Materials database (tagged format) constructed from mat_db.xml by Database.pm\n#\n";	# print the documentation tag line
    #
	#		my $classes = keys (%{$mat_class});
	#		printf MAT_DB ("%u %s", $classes,"# total number of classes\n#\n");	# print the number of classes
    #
	#		# specification of file format
	#		printf MAT_DB ("%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
	#			"# Material classes are listed as follows:",
	#			"#	*class, 'class number'(2 digits),'number of materials in class','class name'",
	#			"#	'class description",
	#			"#",
	#			"# Materials within each class are listed as follows:",
	#			"#	*item,'material name','material number'(20 * 'class number' + 'material position within class'; 3 digits),'class number'(2 digits),'material description'",
	#			"# The material tag is followed by the following material attributes:",
	#			"#	conductivity (W/(m-K), density (kg/m**3), specific heat (J/(kg-K),",
	#			"#	emissivity out (-), emissivity in (-), absorptivity out, (-) absorptivity in (-),",
	#			"#	diffusion resistance (?), default thickness (mm),",
	#			"#	flag [-] legacy [o] opaque [t] transparent [g] gas data+T cor [h] gas data at 4T",
	#			"#",
	#			"#	transparent material include additional attributes:",
	#			"#		longwave tran (-), solar direct tran (-), solar reflec out (-), solar refled in (-),",
	#			"#		visable tran (-), visable reflec out (-), visable reflec in (-), colour rendering (-)"
	#		);
    #
	#		my $class_num = 0;
	#		my $mat_num = 0;
    #
	#		foreach my $class (sort {$a cmp $b} keys (%{$mat_class})) {	# iterate over each class
	#			$class_num++;
    #
	#			print MAT_DB "#\n#\n# CLASS\n";	# print a common identifier
    #
	#			my @mats = sort {$a cmp $b} keys (%{$mat_class->{$class}});
	#			my $mats = @mats;
    #
	#			printf MAT_DB ("%s,%u,%u,%s\n",	# print the class information
	#				"*class",	# class tag
	#				$class_num,	# class number
	#				$mats,	# number of materials in the class
	#				"$class"	# class name
	#			);
	#			print MAT_DB "$class class includes the following materials: @mats\n";	# print the class description
    #
	#			print MAT_DB "#\n# MATERIALS\n";	# print a common identifier
	#			
	#			# setup the material number to the next 10's - this is how ESP-r handles its classes
	#			if ($mat_num =~ /^(\d)(\d)(\d)\d$/) {
	#				$mat_num = $1 * 1000 + $2 * 100 + ($3 + 1) * 10;
	#			}
	#			elsif ($mat_num =~ /^(\d)(\d)\d$/) {
	#				$mat_num = $1 * 100 + ($1 + 1) * 10;
	#			}
	#			elsif ($mat_num =~ /^(\d)\d$/) {
	#				$mat_num = ($1 + 1) * 10;
	#			}
	#			elsif ($mat_num =~ /^(\d)$/) {
	#				if ($1 > 0) {
	#					$mat_num = 10
	#				};
	#			}
	#			else {die "MATERIALS DB: Too many materials - $mat_num\n";};
    #
    #
	#			foreach my $mat_name (sort {$a cmp $b} keys (%{$mat_class->{$class}})) {	# iterate over each material within the class
	#				$mat_num++;
	#				my $mat = \%{$mat_class->{$class}->{$mat_name}};
	#				$mat->{'number'} = $mat_num;
    #
	#				printf MAT_DB ("%s,%s,%u,%u,%s\n",	# print the material title line
	#					'*item',	# material tag
	#					$mat_name,	# material name
	#					$mat_num,	# material number (groups of 20)
	#					$class_num,
	#					$mat->{'description'}	# material description
	#				);
    #
    #
	#				# print the first part of the material data line
	#				printf MAT_DB ("%.3f,", $mat->{'conductivity_W_mK'});
	#				printf MAT_DB ("%.0f,", $mat->{'density_kg_m3'});
	#				printf MAT_DB ("%.0f,", $mat->{'spec_heat_J_kgK'});
	#				foreach my $property ('emissivity_out', 'emissivity_in', 'absorptivity_out', 'absorptivity_in') {
	#					printf MAT_DB ("%.3f,", $mat->{$property});
	#				};
	#				printf MAT_DB ("%.0f,", $mat->{'vapor_resist'});
	#				printf MAT_DB ("%.1f,", $mat->{'default_thickness_mm'});	# this property has a different format but is on the same line
    #
	#				if ($mat->{'type'} eq 'OPAQ') {print MAT_DB "o\n";} # opaque material so print last digit of line
	#				elsif ($mat->{'type'} eq 'TRAN') {	# translucent material so print t and additional data
	#					print MAT_DB 't,';	# print TRAN identifier
	#					# print the translucent properties
	#					foreach my $property ('trans_long', 'trans_solar', 'trans_vis', 'refl_solar_out', 'refl_solar_in', 'refl_vis_out', 'refl_vis_in') {
	#						printf MAT_DB ("%.3f,", $mat->{'optic_mat_props'}->{$property});
	#					};
	#					printf MAT_DB ("%.3f\n", $mat->{'optic_mat_props'}->{'clr_render'});	# print the last part of translucent properties line
	#				};
	#			};
	#		};
	#		print MAT_DB "*end\n";	# print the end tag
	#		close MAT_DB;
	#	};
	#};


	OPTICS: {
		my $arch_optic_data = XMLin("../databases/NBC_optic_db.xml", ForceArray => ['layers']);	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
		
		foreach my $optic (keys %{$arch_optic_data}) {
			#  store the name within the optic - this is redundant, but may be used in Hse_Gen
			$arch_optic_data->{$optic}->{'name'} = $optic;
		};
        
        # Append the existing database
        @{$optic_data}{keys %{$arch_optic_data}} = values %{$arch_optic_data};
    
		open (OPTIC_DB_XML, '>', "../databases/optics_db_regen.xml") or die ("can't open  ../databases/optics_db_regen.xml");	# open a writeout file
		print OPTIC_DB_XML XMLout($optic_data);	# printout the XML data
		close OPTIC_DB_XML;
    
		open (OPTIC_DB, '>', "../databases/optic_db_xml.a") or die ("can't open  ../databases/optic_db_xml.a");	# open a writeout file for the optics database
		open (OPTIC_LIST, '>', "../databases/optic_db_xml_list") or die ("can't open  ../databases/optic_db_xml_list");	# open a list file that will simply list the optic name and description 
    
		# provide the header lines and instructions to the optics database
		print OPTIC_DB "# optics database (columnar format) constructed from con_db.xml by DB_Gen.pl based on mat_db.xml\n#\n";
    
		# print the file format
		foreach my $statement (
			"# optical properties db for default windows and most of the information",
			"# required to automatically build transparent constructions & tmc files.",
			"#",
			"# 1st line of each item is column sensitive and holds:",
			"# an identifier (12 char) followed by a description",
			"# 2nd line holds:",
			"# a) the number of default (always 1?) and tmc layers (equal to construction)",
			"# b) visable trans ",
			"# c) solar reflectance (outside)",
			"# d) overall solar absorbed",
			"# e) U value (for reporting purposes only)",
			"# 3rd line holds:",
			"# a) direct solar tran at 0deg 40deg 55deg 70deg 80deg from normal",
			"# b) total heat gain at the same angles (for reporting purposes only)",
			"# then for each layer there is a line containing",
			"# a) refractive index",
			"# b) solar absorption at 0deg 40deg 55deg 70deg 80deg from normal",
			"#",
			"#"
			) {printf OPTIC_DB ("%s\n", $statement);
			};
    
		my @optics = sort {$a cmp $b} keys (%{$optic_data});	# sort optic types to order the printout
    
    
		foreach my $optic (sort {$a cmp $b} keys (%{$optic_data})) {
    
			my $opt = \%{$optic_data->{$optic}};	# shorten the name for subsequent use
    
			# fill out the optics database (TMC)
			printf OPTIC_DB ("%-14s%s\n",
				$optic,	# print the optics name
				": $opt->{'description'}"	# print the optics description
			);
    
			printf OPTIC_LIST ("%-14s%s\n",
				$optic,	# print the optics name
				": $opt->{'description'}"	# print the optics description
			);
    
			print OPTIC_DB "# $opt->{'optic_con_props'}->{'optical_description'}\n";	# print additional optical description
    
			# print the one time optical information
			printf OPTIC_DB ("%s%4d%7.3f%7.3f%7.3f%7.3f\n",
				"  1",
				$#{$opt->{'layers'}} + 1,
				$opt->{'optic_con_props'}->{'trans_vis'},
				$opt->{'optic_con_props'}->{'refl_solar_doc_only'},
				$opt->{'optic_con_props'}->{'abs_solar_doc_only'},
				$opt->{'optic_con_props'}->{'U_val_W_m2K_doc_only'}
			);
    
			# print the transmission and heat gain values at different angles for the construction type
			printf OPTIC_DB ("  %s %s\n",
				$opt->{'optic_con_props'}->{'trans_solar'},
				$opt->{'optic_con_props'}->{'heat_gain_doc_only'}
			);
    
			print OPTIC_DB "# layers\n";	# print a common identifier
			# print the refractive index and abs values at different angles for each layer of the transluscent construction type
			foreach my $layer (@{$opt->{'layers'}}) {	# iterate over construction layers
				printf OPTIC_DB ("  %4.3f %s\n",
					$layer->{'refr_index'},
					$layer->{'absorption'}
				);
			};
		};
    
		close OPTIC_DB;
		close OPTIC_LIST;
	};

	CONSTRUCTIONS: {
		my $arch_con_data = XMLin("../databases/NBC_cons.xml", ForceArray => ['layers']);	# readin the XML data, note that any hash with properties will recieve an array index even if there is only one of that hash
		$arch_con_data = \%{$arch_con_data->{'construction'}};
		
		foreach my $con (keys %{$arch_con_data}) {
			#  store the name within the optic - this is redundant, but may be used in Hse_Gen
			$arch_con_data->{$con}->{'name'} = $con;
		};
		
 		# Append the existing database
        @{$con_data}{keys %{$arch_con_data}} = values %{$arch_con_data};

# 		open (CON_DB_XML, '>', "../databases/con_db_regen.xml") or die ("can't open  ../databases/con_db_regen.xml");	# open a writeout file
# 		print CON_DB_XML XMLout($con_data);	# printout the XML data
# 		close CON_DB_XML;

		open (CON_DB, '>', "../databases/con_db_xml.a") or die ("can't open  ../databases/con_db_xml.a");	# open a writeout file for the constructions
		open (CON_LIST, '>', "../databases/con_db_xml_list") or die ("can't open  ../databases/con_db_xml_list");	# open a list file that will simply list the materials 

		print CON_DB "# composite constructions database (columnar format) constructed from con_db.xml by DB_Gen.pl based on mat_db.xml\n#\n";	# heading intro line
		print CON_LIST "# composite constructions database (columnar format) constructed from con_db.xml by DB_Gen.pl based on mat_db.xml\n#\n";	# heading intro line

		my $con_count = keys (%{$con_data});
		printf CON_DB ("%u %s\n", $con_count,"# total number of constructions\n#");	# print the number of constructions

		printf CON_DB ("%s\n%s\n%s\n",	# format instructions for the construction database
			"# for each construction list the: # of layers, construction name, type (OPAQ or TRAN or CFC), Optics name (or OPAQUE), symmetry.",
			"#\t followed by for each material of the construction:",
			"#\t\t material number, thickness (m), material name, and if 'Gap' then RSI at vert horiz and sloped"
		);

		foreach my $con_key (sort {$a cmp $b} keys (%{$con_data})) {	# iterate over each construction
			my $con = \%{$con_data->{$con_key}};
			print CON_DB "#\n#\n# CONSTRUCTION\n";	# print a common identifier

			printf CON_LIST ("%16s : %8s : %16s : %s\n", $con_key, $con->{'type'}, $con->{'symmetry'}, $con->{'description'});	# print the construction name and description to the list

			printf CON_DB ("%5d    %-14s%-6s", 	# print the construction information
				$#{$con->{'layers'}} + 1,	# number of layers in the construction
				$con_key,	# construction name
				$con->{'type'}	# type of construction (OPAQ or TRAN)
			);

			if ($con->{'type'} eq 'OPAQ') {printf CON_DB ("%-14s", 'OPAQUE');}	# opaque so no line to optics database
			elsif ($con->{'type'} eq 'CFC') {printf CON_DB ("%-14s", 'USE GSLedit');}      # CFC so should use cfc properties
			elsif ($con->{'type'} eq 'TRAN') {printf CON_DB ("%-14s", $con->{'optic_name'});};	# transluscent construction so link to the optics database


			printf CON_DB ("%-14s\n", $con->{'symmetry'});	# print symetrical or not

			print CON_DB "# $con_key Description: $con->{'description'}\n";	# print the construction description
			print CON_DB "#\n# MATERIALS\n";	# print a common identifier

			foreach my $layer (@{$con->{'layers'}}) {	# iterate over construction layers
# 				print Dumper $layer;
				printf CON_DB ("%5d%10.4f",	# print the layers number and name
					$mat_data->{$layer->{'mat'}}->{'number'},	# material number
					$layer->{'thickness_mm'} / 1000	# material thickness in (m)
				);

				if ($layer->{'mat'} eq 'Gap') {	# it is Gap based on material number zero
					# print the RSI properties of Gap for the three positions that the construction may be placed in
					printf CON_DB ("%s%4.3f %4.3f %4.3f\n",
						"  Gap  ",
						$layer->{'gap_RSI'}->{'vert'},
						$layer->{'gap_RSI'}->{'horiz'},
						$layer->{'gap_RSI'}->{'slope'}
					);
				}
				else {	# not Gap so simply report the name and descriptions
					print CON_DB "  $layer->{'mat'} : $mat_data->{$layer->{'mat'}}->{'description'}\n";	# material name and description from the list
				};

				print CON_LIST "\t$layer->{'mat'} : $layer->{'thickness_mm'} (mm) : $mat_data->{$layer->{'mat'}}->{'description'}\n";	# material name and description
			};
		};
		close CON_DB;
		close CON_LIST;
	};

	return ($mat_data, $con_data,$optic_data);
};

# Final return value of one to indicate that the perl module is successful
1;
