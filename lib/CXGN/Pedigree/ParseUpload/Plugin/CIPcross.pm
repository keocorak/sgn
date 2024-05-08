package CXGN::Pedigree::ParseUpload::Plugin::CIPcross;

use Moose::Role;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseXLSX;
use CXGN::Stock::StockLookup;
use SGN::Model::Cvterm;
use Data::Dumper;
use CXGN::List::Validate;

sub _validate_with_plugin {
    my $self = shift;
    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();
    my @error_messages;
    my %errors;
    my %supported_cross_types;

    # Match a dot, extension .xls / .xlsx
    my ($extension) = $filename =~ /(\.[^.]+)$/;
    my $parser;

    if ($extension eq '.xlsx') {
        $parser = Spreadsheet::ParseXLSX->new();
    }
    else {
        $parser = Spreadsheet::ParseExcel->new();
    }

    my $excel_obj;
    my $worksheet;

    $excel_obj = $parser->parse($filename);
    if ( !$excel_obj ) {
        push @error_messages,  $parser->error();
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    $worksheet = ( $excel_obj->worksheets() )[0]; #support only one worksheet
    if (!$worksheet) {
        push @error_messages, "Spreadsheet must be on 1st tab in Excel (.xls) file";
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();
    if (($col_max - $col_min)  < 4 || ($row_max - $row_min) < 1 ) { #must have header and at least one row of crosses
        push @error_messages, "Spreadsheet is missing header or contains no row";
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    my $inventory_id_head;
    my $template_file_id_head;
    my $crossing_plan_id_head;
    my $female_order_head;
    my $female_accession_number_head;
    my $female_code_breeder_head;
    my $female_attributes_head;
    my $male_order_head;
    my $male_accession_number_head;
    my $male_code_breeder_head;
    my $male_attributes_head;
    my $number_of_flowers_head;
    my $crossing_date_head;
    my $number_of_fruits_head;
    my $fruit_harvest_date_head;
    my $fruit_maceration_date_head;
    my $population_head;
    my $type_of_pollination_head;
    my $crossing_location_head;
    my $cip_region_crossing_head;
    my $country_crossing_head;
    my $adm_1_crossing_head;
    my $adm_2_crossing_head;
    my $adm_3_crossing_head;
    my $adm_4_crossing_head;
    my $seed_with_spot_markers_head;
    my $seed_without_spot_markers_head;
    my $total_number_of_seeds_head;
    my $seed_stock_head;
    my $seed_count_date_head;


    if ($worksheet->get_cell(0,0)) {
        $inventory_id_head  = $worksheet->get_cell(0,0)->value();
        $inventory_id_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,3)) {
        $template_file_id_head  = $worksheet->get_cell(0,3)->value();
        $template_file_id_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,4)) {
        $crossing_plan_id_head  = $worksheet->get_cell(0,4)->value();
        $crossing_plan_id_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,5)) {
        $female_order_head  = $worksheet->get_cell(0,5)->value();
        $female_order_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,6)) {
        $female_accession_number_head  = $worksheet->get_cell(0,6)->value();
        $female_accession_number_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,7)) {
        $female_code_breeder_head  = $worksheet->get_cell(0,7)->value();
        $female_code_breeder_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,8)) {
        $female_attributes_head  = $worksheet->get_cell(0,8)->value();
        $female_attributes_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,9)) {
        $male_order_head  = $worksheet->get_cell(0,9)->value();
        $male_order_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,10)) {
        $male_accession_number_head  = $worksheet->get_cell(0,10)->value();
        $male_accession_number_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,11)) {
        $male_code_breeder_head  = $worksheet->get_cell(0,11)->value();
        $male_code_breeder_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,12)) {
        $male_attributes_head  = $worksheet->get_cell(0,12)->value();
        $male_attributes_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,13)) {
        $number_of_flowers_head  = $worksheet->get_cell(0,13)->value();
        $number_of_flowers_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,14)) {
        $crossing_date_head  = $worksheet->get_cell(0,14)->value();
        $crossing_date_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,16)) {
        $number_of_fruits_head  = $worksheet->get_cell(0,16)->value();
        $number_of_fruits_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,17)) {
        $fruit_harvest_date_head  = $worksheet->get_cell(0,17)->value();
        $fruit_harvest_date_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,20)) {
        $fruit_maceration_date_head  = $worksheet->get_cell(0,20)->value();
        $fruit_maceration_date_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,22)) {
        $population_head  = $worksheet->get_cell(0,22)->value();
        $population_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,23)) {
        $type_of_pollination_head  = $worksheet->get_cell(0,23)->value();
        $type_of_pollination_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,25)) {
        $crossing_location_head  = $worksheet->get_cell(0,25)->value();
        $crossing_location_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,28)) {
        $cip_region_crossing_head  = $worksheet->get_cell(0,28)->value();
        $cip_region_crossing_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,29)) {
        $country_crossing_head  = $worksheet->get_cell(0,29)->value();
        $country_crossing_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,30)) {
        $adm_1_crossing_head  = $worksheet->get_cell(0,30)->value();
        $adm_1_crossing_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,31)) {
        $adm_2_crossing_head  = $worksheet->get_cell(0,31)->value();
        $adm_2_crossing_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,32)) {
        $adm_3_crossing_head  = $worksheet->get_cell(0,32)->value();
        $adm_3_crossing_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,33)) {
        $adm_4_crossing_head  = $worksheet->get_cell(0,33)->value();
        $adm_4_crossing_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,39)) {
        $seed_with_spot_markers_head  = $worksheet->get_cell(0,39)->value();
        $seed_with_spot_markers_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,40)) {
        $seed_without_spot_markers_head  = $worksheet->get_cell(0,40)->value();
        $seed_without_spot_markers_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,41)) {
        $total_number_of_seeds_head  = $worksheet->get_cell(0,41)->value();
        $total_number_of_seeds_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,42)) {
        $seed_stock_head  = $worksheet->get_cell(0,42)->value();
        $seed_stock_head =~ s/^\s+|\s+$//g;
    }
    if ($worksheet->get_cell(0,43)) {
        $seed_count_date_head  = $worksheet->get_cell(0,43)->value();
        $seed_count_date_head =~ s/^\s+|\s+$//g;
    }

    if (!$inventory_id_head || $inventory_id_head ne 'Inventory ID' ) {
        push @error_messages, "Cell A1: Inventory ID is missing from the header";
    }
    if (!$template_file_id_head || $template_file_id_head ne 'Template File ID' ) {
        push @error_messages, "Cell D1: Template File ID is missing from the header";
    }
    if (!$crossing_plan_id_head || $crossing_plan_id_head ne 'Crossing Plan ID' ) {
        push @error_messages, "Cell E1: Crossing Plan ID is missing from the header";
    }
    if (!$female_order_head || $female_order_head ne 'Female Order' ) {
        push @error_messages, "Cell F1: Female Order is missing from the header";
    }
    if (!$female_accession_number_head || $female_accession_number_head ne 'Female Accession Number') {
        push @error_messages, "Cell G1: Female Accession Number is missing from the header";
    }
    if (!$female_code_breeder_head || $female_code_breeder_head ne 'Female Code Breeder' ) {
        push @error_messages, "Cell H1: Female Code Breeder is missing from the header";
    }
    if (!$female_attributes_head || $female_attributes_head ne 'Female Attributes' ) {
        push @error_messages, "Cell I1: Female Attributes is missing from the header";
    }
    if (!$male_order_head || $male_order_head ne 'Male Order' ) {
        push @error_messages, "Cell J1: Male Order is missing from the header";
    }
    if (!$male_accession_number_head || $male_accession_number_head ne 'Male Accession Number') {
        push @error_messages, "Cell K1: Male Accession Number is missing from the header";
    }
    if (!$male_code_breeder_head || $male_code_breeder_head ne 'Male Code Breeder' ) {
        push @error_messages, "Cell L1: Male Code Breeder is missing from the header";
    }
    if (!$male_attributes_head || $male_attributes_head ne 'Male Attributes' ) {
        push @error_messages, "Cell M1: Male Attributes is missing from the header";
    }
    if (!$number_of_flowers_head || $number_of_flowers_head ne 'Number of Flowers' ) {
        push @error_messages, "Cell N1: Number of Flowers is missing from the header";
    }
    if (!$crossing_date_head || $crossing_date_head ne 'Crossing Date' ) {
        push @error_messages, "Cell O1: Crossing Date is missing from the header";
    }
    if (!$number_of_fruits_head || $number_of_fruits_head ne 'Number of Fruits' ) {
        push @error_messages, "Cell Q1: Number of Fruits is missing from the header";
    }
    if (!$fruit_harvest_date_head || $fruit_harvest_date_head ne 'Fruit Harvest Date' ) {
        push @error_messages, "Cell R1: Fruit Harvest Date is missing from the header";
    }
    if (!$fruit_maceration_date_head || $fruit_maceration_date_head ne 'Fruit Maceration Date' ) {
        push @error_messages, "Cell U1: Fruit Maceration Date is missing from the header";
    }
    if (!$population_head || $population_head ne 'Population' ) {
        push @error_messages, "Cell W1: Population is missing from the header";
    }
    if (!$type_of_pollination_head || $type_of_pollination_head ne 'Type of Pollination' ) {
        push @error_messages, "Cell X1: Type of Pollination is missing from the header";
    }
    if (!$crossing_location_head || $crossing_location_head ne 'Crossing Location' ) {
        push @error_messages, "Cell Z1: Crossing Location is missing from the header";
    }
    if (!$cip_region_crossing_head || $cip_region_crossing_head ne 'CIP Region Crossing' ) {
        push @error_messages, "Cell AC1: CIP Region Crossing is missing from the header";
    }
    if (!$country_crossing_head || $country_crossing_head ne 'Country Crossing' ) {
        push @error_messages, "Cell AD1: Country Crossing is missing from the header";
    }
    if (!$adm_1_crossing_head || $adm_1_crossing_head ne 'Adm 1 Crossing' ) {
        push @error_messages, "Cell AE1: Adm 1 Crossing is missing from the header";
    }
    if (!$adm_2_crossing_head || $adm_2_crossing_head ne 'Adm 2 Crossing' ) {
        push @error_messages, "Cell AF1: Adm 2 Crossing is missing from the header";
    }
    if (!$adm_3_crossing_head || $adm_3_crossing_head ne 'Adm 3 Crossing' ) {
        push @error_messages, "Cell AG1: Adm 3 Crossing is missing from the header";
    }
    if (!$adm_4_crossing_head || $adm_4_crossing_head ne 'Adm 4 Crossing' ) {
        push @error_messages, "Cell AH1: Adm 4 Crossing is missing from the header";
    }
    if (!$seed_with_spot_markers_head || $seed_with_spot_markers_head ne 'Seed with Spot Markers' ) {
        push @error_messages, "Cell AN1: Seed with Spot Markers is missing from the header";
    }
    if (!$seed_without_spot_markers_head || $seed_without_spot_markers_head ne 'Seed without Spot Markers' ) {
        push @error_messages, "Cell AO1: Seed without Spot Markers is missing from the header";
    }
    if (!$total_number_of_seeds_head || $total_number_of_seeds_head ne 'Total Number of Seeds' ) {
        push @error_messages, "Cell AP1: Total Number of Seeds is missing from the header";
    }
    if (!$seed_stock_head || $seed_stock_head ne 'Seed Stock' ) {
        push @error_messages, "Cell AQ1: Seed Stock is missing from the header";
    }
    if (!$seed_count_date_head || $seed_count_date_head ne 'Seed Count Date' ) {
        push @error_messages, "Cell AR1: Seed Count Date is missing from the header";
    }


    my %seen_inventory_ids;
    my %seen_accession_names;

    for my $row ( 1 .. $row_max ) {
        my $row_name = $row+1;
        my $inventory_id;
        my $female_accession_number;
        my $male_accession_number;

        if ($worksheet->get_cell($row,0)) {
            $inventory_id = $worksheet->get_cell($row,0)->value();
        }
        if ($worksheet->get_cell($row,6)) {
            $female_accession_number =  $worksheet->get_cell($row,6)->value();
            $female_accession_number =~ s/^\s+|\s+$//g;
        }

        if (!defined $inventory_id && !defined $female_accession_number) {
            last;
        }

        if ($worksheet->get_cell($row,10)) {
            $male_accession_number = $worksheet->get_cell($row,10)->value();
            $male_accession_number =~ s/^\s+|\s+$//g;
        }

        if (!$inventory_id || $inventory_id eq '') {
            push @error_messages, "Cell A$row_name: Inventory ID missing";
        } else {
            $inventory_id =~ s/^\s+|\s+$//g;
        }

#        if ($seen_inventory_ids{$inventory_id}) {
#            push @error_messages, "Cell A$row_name: duplicate Inventory ID: $inventory_id";
#        }

        if (!$female_accession_number || $female_accession_number eq '') {
            push @error_messages, "Cell G$row_name: Female Accession Number missing";
        } else {
            $female_accession_number =~ s/^\s+|\s+$//g;
            $seen_accession_names{$female_accession_number}++;
        }

        if (!$male_accession_number || $male_accession_number eq '') {
            push @error_messages, "Cell K$row_name: Male Accession Number missing";
        } else {
            $male_accession_number =~ s/^\s+|\s+$//g;
            $seen_accession_names{$male_accession_number}++;
        }

    }

    my @accessions = keys %seen_accession_names;
    my $accession_validator = CXGN::List::Validate->new();
    my @accessions_missing = @{$accession_validator->validate($schema,'uniquenames',\@accessions)->{'missing'}};

    if (scalar(@accessions_missing) > 0) {
        push @error_messages, "The following parents are not in the database, or are not in the database as uniquenames: ".join(',',@accessions_missing);
    }

    my @all_inventory_ids = keys %seen_inventory_ids;
    my $inventory_rs = $schema->resultset("Stock::Stock")->search({
        'is_obsolete' => { '!=' => 't' },
        'uniquename' => { -in => \@all_inventory_ids }
    });
    while (my $r=$inventory_rs->next){
        push @error_messages, "Inventory ID already exists in database: ".$r->uniquename;
    }

    if (scalar(@error_messages) >= 1) {
        $errors{'error_messages'} = \@error_messages;
        $self->_set_parse_errors(\%errors);
        return;
    }

    return 1;

}

sub _parse_with_plugin {
    my $self = shift;
    my $filename = $self->get_filename();
    my $schema = $self->get_chado_schema();

    # Match a dot, extension .xls / .xlsx
    my ($extension) = $filename =~ /(\.[^.]+)$/;
    my $parser;

    if ($extension eq '.xlsx') {
        $parser = Spreadsheet::ParseXLSX->new();
    }
    else {
        $parser = Spreadsheet::ParseExcel->new();
    }

    my $excel_obj;
    my $worksheet;
    my %parent_info;
    my @pedigrees;
    my %cross_info;
    my %cross_additional_info;
    my %project_info;
    my %parsed_result;


    $excel_obj = $parser->parse($filename);
    if ( !$excel_obj ) {
        return;
    }

    $worksheet = ( $excel_obj->worksheets() )[0];
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();

    for my $row ( 1 .. $row_max ) {
        my $inventory_id;
        my $template_file_id;
        my $crossing_plan_id;
        my $female_order;
        my $female_accession_number;
        my $female_code_breeder;
        my $female_attributes;
        my $male_order;
        my $male_accession_number;
        my $male_code_breeder;
        my $male_attributes;
        my $number_of_flowers;
        my $crossing_date;
        my $number_of_fruits;
        my $fruit_harvest_date;
        my $fruit_maceration_date;
        my $population;
        my $type_of_pollination;
        my $crossing_location;
        my $cip_region_crossing;
        my $country_crossing;
        my $adm_1_crossing;
        my $adm_2_crossing;
        my $adm_3_crossing;
        my $adm_4_crossing;
        my $seed_with_spot_markers;
        my $seed_without_spot_markers;
        my $total_number_of_seeds;
        my $seed_stock;
        my $seed_count_date;


        if ($worksheet->get_cell($row,0)) {
            $inventory_id = $worksheet->get_cell($row,0)->value();
            $inventory_id =~ s/^\s+|\s+$//g;
        }

        if (!defined $inventory_id) {
            last;
        }

        if ($worksheet->get_cell($row,3)) {
            $template_file_id = $worksheet->get_cell($row,3)->value();
            $template_file_id =~ s/^\s+|\s+$//g;
            $project_info{'Template File ID'}{$template_file_id}++;
        }
        if ($worksheet->get_cell($row,4)) {
            $crossing_plan_id = $worksheet->get_cell($row,4)->value();
            $crossing_plan_id =~ s/^\s+|\s+$//g;
            $project_info{'Crossing Plan ID'}{$crossing_plan_id}++;
        }
        if ($worksheet->get_cell($row,5)) {
            $female_order = $worksheet->get_cell($row,5)->value();
            $female_order =~ s/^\s+|\s+$//g;
        }
        if ($worksheet->get_cell($row,6)) {
            $female_accession_number =  $worksheet->get_cell($row,6)->value();
            $female_accession_number =~ s/^\s+|\s+$//g;
            $parent_info{'female'}{$female_accession_number}{'Female Order'} = $female_order;
            $parent_info{'female'}{$female_accession_number}{'Female Accession Name'} = $female_accession_number;
        }
        if ($worksheet->get_cell($row,7)) {
            $female_code_breeder = $worksheet->get_cell($row,7)->value();
            $female_code_breeder =~ s/^\s+|\s+$//g;
            $parent_info{'female'}{$female_accession_number}{'Female Code Breeder'} = $female_code_breeder;
        }
        if ($worksheet->get_cell($row,8)) {
            $female_attributes = $worksheet->get_cell($row,8)->value();
            $female_attributes =~ s/^\s+|\s+$//g;
            $cross_additional_info{$inventory_id}{'female_focus_trait'} = $female_attributes
#            $parent_info{'female'}{$female_accession_number}{'Female Attributes'} = $female_attributes;
        }
        if ($worksheet->get_cell($row,9)) {
            $male_order = $worksheet->get_cell($row,9)->value();
            $male_order =~ s/^\s+|\s+$//g;
        }
        if ($worksheet->get_cell($row,10)) {
            $male_accession_number = $worksheet->get_cell($row,10)->value();
            $male_accession_number =~ s/^\s+|\s+$//g;
            $parent_info{'male'}{$male_accession_number}{'Male Order'} = $male_order;
            $parent_info{'male'}{$male_accession_number}{'Male Accession Name'} = $male_accession_number;
        }
        if ($worksheet->get_cell($row,11)) {
            $male_code_breeder = $worksheet->get_cell($row,11)->value();
            $male_code_breeder =~ s/^\s+|\s+$//g;
            $parent_info{'male'}{$male_accession_number}{'Male Code Breeder'} = $male_code_breeder;
        }
        if ($worksheet->get_cell($row,12)) {
            $male_attributes = $worksheet->get_cell($row,12)->value();
            $male_attributes =~ s/^\s+|\s+$//g;
            $cross_additional_info{$inventory_id}{'male_focus_trait'} = $male_attributes
#            $parent_info{'male'}{$male_accession_number}{'Male Attributes'} = $male_attributes;
        }
        if ($worksheet->get_cell($row,13)) {
            $number_of_flowers  = $worksheet->get_cell($row,13)->value();
            $number_of_flowers =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Number of Flowers'} = $number_of_flowers;
        }
        if ($worksheet->get_cell($row,14)) {
            $crossing_date  = $worksheet->get_cell($row,14)->value();
            $crossing_date =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Crossing Date'} = $crossing_date;
        }
        if ($worksheet->get_cell($row,16)) {
            $number_of_fruits  = $worksheet->get_cell($row,16)->value();
            $number_of_fruits =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Number of Fruits'} = $number_of_fruits;
        }
        if ($worksheet->get_cell($row,17)) {
            $fruit_harvest_date  = $worksheet->get_cell($row,17)->value();
            $fruit_harvest_date =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Fruit Harvest Date'} = $fruit_harvest_date;
        }
        if ($worksheet->get_cell($row,20)) {
            $fruit_maceration_date  = $worksheet->get_cell($row,20)->value();
            $fruit_maceration_date =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Fruit Maceration Date'} = $fruit_maceration_date;
        }
        if ($worksheet->get_cell($row,22)) {
            $population = $worksheet->get_cell($row,22)->value();
            $population =~ s/^\s+|\s+$//g;
            $project_info{'Population'}{$population}++;
        }
        if ($worksheet->get_cell($row,23)) {
            $type_of_pollination = $worksheet->get_cell($row,23)->value();
            $type_of_pollination =~ s/^\s+|\s+$//g;
            $project_info{'Type of Pollination'}{$type_of_pollination}++;
        }
#        if ($worksheet->get_cell($row,25)) {
#            $crossing_location = $worksheet->get_cell($row,25)->value();
#            $crossing_location =~ s/^\s+|\s+$//g;
#            $project_info{'Crossing Location'}{$crossing_location}++;
#        }
        if ($worksheet->get_cell($row,28)) {
            $cip_region_crossing = $worksheet->get_cell($row,28)->value();
            $cip_region_crossing =~ s/^\s+|\s+$//g;
            $project_info{'CIP Region Crossing'}{$cip_region_crossing}++;
        }
        if ($worksheet->get_cell($row,29)) {
            $country_crossing = $worksheet->get_cell($row,29)->value();
            $country_crossing =~ s/^\s+|\s+$//g;
            $project_info{'Country Crossing'}{$country_crossing}++;
        }
        if ($worksheet->get_cell($row,30)) {
            $adm_1_crossing = $worksheet->get_cell($row,30)->value();
            $adm_1_crossing =~ s/^\s+|\s+$//g;
            $project_info{'Adm 1 Crossing'}{$adm_1_crossing}++;
        }
        if ($worksheet->get_cell($row,31)) {
            $adm_2_crossing = $worksheet->get_cell($row,31)->value();
            $adm_2_crossing =~ s/^\s+|\s+$//g;
            $project_info{'Adm 2 Crossing'}{$adm_2_crossing}++;
        }
        if ($worksheet->get_cell($row,32)) {
            $adm_3_crossing = $worksheet->get_cell($row,32)->value();
            $adm_3_crossing =~ s/^\s+|\s+$//g;
            $project_info{'Adm 3 Crossing'}{$adm_3_crossing}++;
        }
        if ($worksheet->get_cell($row,33)) {
            $adm_4_crossing = $worksheet->get_cell($row,33)->value();
            $adm_4_crossing =~ s/^\s+|\s+$//g;
            $project_info{'Adm 4 Crossing'}{$adm_4_crossing}++;
        }
        if ($worksheet->get_cell($row,39)) {
            $seed_with_spot_markers  = $worksheet->get_cell($row,39)->value();
            $seed_with_spot_markers =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Seed with Spot Markers'} = $seed_with_spot_markers;
        }
        if ($worksheet->get_cell($row,40)) {
            $seed_without_spot_markers  = $worksheet->get_cell($row,40)->value();
            $seed_without_spot_markers =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Seed without Spot Markers'} = $seed_without_spot_markers;
        }
        if ($worksheet->get_cell($row,41)) {
            $total_number_of_seeds  = $worksheet->get_cell($row,41)->value();
            $total_number_of_seeds =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Total Number of Seeds'} = $total_number_of_seeds;
        }
        if ($worksheet->get_cell($row,42)) {
            $seed_stock  = $worksheet->get_cell($row,42)->value();
            $seed_stock =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Seed Stock'} = $seed_stock;
        }
        if ($worksheet->get_cell($row,43)) {
            $seed_count_date  = $worksheet->get_cell($row,43)->value();
            $seed_count_date =~ s/^\s+|\s+$//g;
            $cross_info{$inventory_id}{'Seed Count Date'} = $seed_count_date;
        }

        my $pedigree =  Bio::GeneticRelationships::Pedigree->new(name=>$inventory_id, cross_type=>'biparental');
        if ($female_accession_number) {
            my $female_parent = Bio::GeneticRelationships::Individual->new(name => $female_accession_number);
            $pedigree->set_female_parent($female_parent);
        }
        if ($male_accession_number) {
            my $male_parent = Bio::GeneticRelationships::Individual->new(name => $male_accession_number);
            $pedigree->set_male_parent($male_parent);
        }

        my $cross_combination = $female_accession_number.'/'.$male_accession_number;
        $pedigree->set_cross_combination($cross_combination);

        push @pedigrees, $pedigree;

    }

    $parsed_result{'project_info'} = \%project_info;
    $parsed_result{'parent_info'} = \%parent_info;
    $parsed_result{'crosses'} = \@pedigrees;
    $parsed_result{'cross_info'} = \%cross_info;
    $parsed_result{'cross_additional_info'} = \%cross_additional_info;    

    $self->_set_parsed_data(\%parsed_result);

    return 1;

}




1;
