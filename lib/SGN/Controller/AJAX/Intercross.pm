=head1 NAME

SGN::Controller::AJAX::Intercross - a REST controller class to provide the
functions for download and upload Intercross files

=head1 DESCRIPTION


=head1 AUTHOR

Titima Tantikanjana <tt15@cornell.edu>

=cut

package SGN::Controller::AJAX::Intercross;
use Moose;
use Try::Tiny;
use DateTime;
use Time::HiRes qw(time);
use POSIX qw(strftime);
use Data::Dumper;
use File::Basename qw | basename dirname|;
use File::Copy;
use File::Slurp;
use File::Spec::Functions;
use Digest::MD5;
use List::MoreUtils qw /any /;
use List::MoreUtils 'none';
use Bio::GeneticRelationships::Pedigree;
use Bio::GeneticRelationships::Individual;
use CXGN::UploadFile;
use CXGN::Pedigree::AddCrosses;
use CXGN::Pedigree::AddCrossInfo;
use CXGN::Pedigree::AddCrossTransaction;
use CXGN::Pedigree::ParseUpload;
use CXGN::Trial::Folder;
use CXGN::Trial::TrialLayout;
use CXGN::Stock::StockLookup;
use CXGN::List::Validate;
use CXGN::List;
use Carp;
use File::Path qw(make_path);
use File::Spec::Functions qw / catfile catdir/;
use CXGN::Cross;
use JSON;
use SGN::Model::Cvterm;
use Tie::UrlEncoder; our(%urlencode);
use LWP::UserAgent;
use HTML::Entities;
use URI::Encode qw(uri_encode uri_decode);
use Sort::Key::Natural qw(natsort);
use Scalar::Util qw(looks_like_number);

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);


sub create_parents_file : Path('/ajax/intercross/create_parents_file') : ActionClass('REST') { }

sub create_parents_file_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $female_list_id = $c->req->param("female_list_id");
    my $male_list_id = $c->req->param("male_list_id");
    my $crossing_experiment_id = $c->req->param("crossing_experiment_id");
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $dbh = $c->dbc->dbh;

    my $accession_type_id  =  SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();
    my $female_list = CXGN::List->new({dbh => $dbh, list_id => $female_list_id});
    my $female_elements = $female_list->retrieve_elements($female_list_id);
    my @female_names = @$female_elements;

    my $male_list = CXGN::List->new({dbh => $dbh, list_id => $male_list_id});
    my $male_elements = $male_list->retrieve_elements($male_list_id);
    my @male_names = @$male_elements;

    my $list_error_message;
    my $female_validator = CXGN::List::Validate->new();
    my @female_accessions_missing = @{$female_validator->validate($schema,'uniquenames',\@female_names)->{'missing'}};
    if (scalar(@female_accessions_missing) > 0) {
        $list_error_message = "The following female parents did not pass validation: ".join("\n", @female_accessions_missing);
        $c->stash->{rest} = { error => $list_error_message };
        $c->detach();
    }

    my $male_validator = CXGN::List::Validate->new();
    my @male_accessions_missing = @{$male_validator->validate($schema,'uniquenames',\@male_names)->{'missing'}};
    if (scalar(@male_accessions_missing) > 0) {
        $list_error_message = "The following male parents did not pass validation: ".join("\n", @male_accessions_missing);
        $c->stash->{rest} = { error => $list_error_message };
        $c->detach();
    }

    my @all_rows;
    foreach my $female_name (@female_names) {
        my $female_rs = $schema->resultset("Stock::Stock")->find ({ 'uniquename' => $female_name, 'type_id' => $accession_type_id });
        my $female_id = $female_rs->stock_id();
        push @all_rows, [$female_id, '0', $female_name];
    }

    foreach my $male_name (@male_names) {
        my $male_rs = $schema->resultset("Stock::Stock")->find ({ 'uniquename' => $male_name, 'type_id' => $accession_type_id });
        my $male_id = $male_rs->stock_id();
        push @all_rows, [$male_id, '1', $male_name];
    }

    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');

    my $template_file_name = 'intercross_parents';
    my $user_id = $c->user()->get_object()->get_sp_person_id();
    my $user_name = $c->user()->get_object()->get_username();
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $subdirectory_name = "intercross_parents";
    my $archived_file_name = catfile($user_id, $subdirectory_name,$timestamp."_".$template_file_name.".csv");
    my $archive_path = $c->config->{archive_path};
    my $file_destination =  catfile($archive_path, $archived_file_name);
    print STDERR "FILE DESTINATION =".Dumper($file_destination)."\n";

    my $dir = $c->tempfiles_subdir('/download');
    my $rel_file = $c->tempfile( TEMPLATE => 'download/intercross_parentsXXXXX');
    my $tempfile = $c->config->{basepath}."/".$rel_file.".csv";
#    print STDERR "TEMPFILE =".Dumper($tempfile)."\n";
    open(my $FILE, '> :encoding(UTF-8)', $tempfile) or die "Cannot open tempfile $tempfile: $!";

    my @headers = qw(codeId sex name);
    my $formatted_header = join(',',@headers);
    print $FILE $formatted_header."\n";
    my $parent = 0;
    foreach my $row (@all_rows) {
        my @row_array = ();
        @row_array = @$row;
        my $csv_format = join(',',@row_array);
        print $FILE $csv_format."\n";
        $parent++;
    }
    close $FILE;

    open(my $F, "<", $tempfile) || die "Can't open file ".$self->tempfile();
    binmode $F;
    my $md5 = Digest::MD5->new();
    $md5->addfile($F);
    close($F);

    if (!-d $archive_path) {
        mkdir $archive_path;
    }

    if (! -d catfile($archive_path, $user_id)) {
        mkdir (catfile($archive_path, $user_id));
    }

    if (! -d catfile($archive_path, $user_id,$subdirectory_name)) {
        mkdir (catfile($archive_path, $user_id, $subdirectory_name));
    }

    my $md_row = $metadata_schema->resultset("MdMetadata")->create({
        create_person_id => $user_id,
    });
    $md_row->insert();
    my $file_row = $metadata_schema->resultset("MdFiles")->create({
        basename => basename($file_destination),
        dirname => dirname($file_destination),
        filetype => 'intercross_parents',
        md5checksum => $md5->hexdigest(),
        metadata_id => $md_row->metadata_id(),
    });
    $file_row->insert();
    my $file_id = $file_row->file_id();

    move($tempfile,$file_destination);
    unlink $tempfile;

    my %file_metadata;
    my $file_metadata_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'file_metadata_json', 'project_property');

    my $crossing_experiment = $schema->resultset("Project::Project")->find({project_id => $crossing_experiment_id});
    my $previous_projectprop_rs = $crossing_experiment->projectprops({type_id=>$file_metadata_cvterm->cvterm_id});
    if ($previous_projectprop_rs->count == 1){
        my $file_metadata_string = $previous_projectprop_rs->first->value();
        my $file_metadata_ref = decode_json $file_metadata_string;
        %file_metadata = %{$file_metadata_ref};
        $file_metadata{'intercross_download'}{$file_id}{'file_type'} = 'intercross_parents';
        my $updated_file_metadata_json = encode_json \%file_metadata;
        $previous_projectprop_rs->first->update({value=>$updated_file_metadata_json});
    } elsif ($previous_projectprop_rs->count > 1) {
        print STDERR "More than one found!\n";
        return;
    } else {
        $file_metadata{'intercross_download'}{$file_id}{'file_type'} = 'intercross_parents';
        my $file_metadata_json = encode_json \%file_metadata;
        $crossing_experiment->create_projectprops( { $file_metadata_cvterm->name() => $file_metadata_json } );
    }

    $c->stash->{rest} = {
        success => 1,
        file_id => $file_id,
        data => \@all_rows
    };

}


sub create_intercross_wishlist : Path('/ajax/intercross/create_intercross_wishlist') : ActionClass('REST') { }

sub create_intercross_wishlist_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $wishlist_data = decode_json $c->req->param('wishlist_data');
    my $crossing_experiment_id = $c->req->param('crossing_experiment_id');
    my @wishlist_array = @$wishlist_data;

    my @all_combinations;
    foreach my $wishlist_pair (@wishlist_array) {
        my @each_combination = ();
        my $female_name = $wishlist_pair->{'female_name'};
        my $male_name = $wishlist_pair->{'male_name'};
        my $info_string = $wishlist_pair->{'activity_info'};
        my $female_rs = $schema->resultset("Stock::Stock")->find( { uniquename => $female_name});
        my $female_id = $female_rs->stock_id();
        my $male_rs = $schema->resultset("Stock::Stock")->find( { uniquename => $male_name});
        my $male_id = $male_rs->stock_id();

        @each_combination = ($female_id, $male_id, $female_name, $male_name);

        my @info_array = split /,/ , $info_string;
        my $type = $info_array[0];
        $type =~ s/^\s+|\s+$//g;

        my %activity_types;
        $activity_types{'flower'} = 1;
        $activity_types{'fruit'} = 1;
        $activity_types{'seed'} = 1;

        if (!$activity_types{$type}){
            $c->stash->{rest} = {error => "$type type is not supported. Please use only flower, fruit or seed"};
            return;
        } else {
            push @each_combination, $type;
        }

        my $min = $info_array[1];
        $min =~ s/^\s+|\s+$//g;

        if (looks_like_number($min)) {
            push @each_combination, $min;
        } else {
            $c->stash->{rest} = {error => "$min is not a number. Please indicate minimum number"};
            return;
        }

        my $max = $info_array[2];
        $max =~ s/^\s+|\s+$//g;

        if (looks_like_number($max)) {
            push @each_combination, $max;
        } else {
            $c->stash->{rest} = {error => "$max is not a number. Please indicate maximum number"};
            return;
        }

        push @all_combinations, [@each_combination];
    }

    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');

    my $template_file_name = 'intercross_wishlist';
    my $user_id = $c->user()->get_object()->get_sp_person_id();
    my $user_name = $c->user()->get_object()->get_username();
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $subdirectory_name = "intercross_wishlist";
    my $archived_file_name = catfile($user_id, $subdirectory_name,$timestamp."_".$template_file_name.".csv");
    my $archive_path = $c->config->{archive_path};
    my $file_destination =  catfile($archive_path, $archived_file_name);

    my $dir = $c->tempfiles_subdir('/download');
    my $rel_file = $c->tempfile( TEMPLATE => 'download/intercross_wishlistXXXXX');
    my $tempfile = $c->config->{basepath}."/".$rel_file.".csv";
#    print STDERR "TEMPFILE =".Dumper($tempfile)."\n";
    open(my $FILE, '> :encoding(UTF-8)', $tempfile) or die "Cannot open tempfile $tempfile: $!";

    my @headers = qw(femaleDbId maleDbId femaleName maleName wishType wishMin wishMax);
    my $formatted_header = join(',',@headers);
    print $FILE $formatted_header."\n";
    my $wishlist = 0;
    foreach my $combination (@all_combinations) {
        my @combination_array = ();
        @combination_array = @$combination;
        my $csv_format = join(',',@combination_array);
        print $FILE $csv_format."\n";
        $wishlist++;
    }
    close $FILE;

    open(my $F, "<", $tempfile) || die "Can't open file ".$self->tempfile();
    binmode $F;
    my $md5 = Digest::MD5->new();
    $md5->addfile($F);
    close($F);

    if (!-d $archive_path) {
        mkdir $archive_path;
    }

    if (! -d catfile($archive_path, $user_id)) {
        mkdir (catfile($archive_path, $user_id));
    }

    if (! -d catfile($archive_path, $user_id,$subdirectory_name)) {
        mkdir (catfile($archive_path, $user_id, $subdirectory_name));
    }

    my $md_row = $metadata_schema->resultset("MdMetadata")->create({
        create_person_id => $user_id,
    });

    $md_row->insert();
    my $file_row = $metadata_schema->resultset("MdFiles")->create({
        basename => basename($file_destination),
        dirname => dirname($file_destination),
        filetype => 'intercross_wishlist',
        md5checksum => $md5->hexdigest(),
        metadata_id => $md_row->metadata_id(),
    });

    $file_row->insert();
    my $file_id = $file_row->file_id();

    move($tempfile,$file_destination);
    unlink $tempfile;

    my %file_metadata;
    my $file_metadata_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'file_metadata_json', 'project_property');

    my $crossing_experiment = $schema->resultset("Project::Project")->find({project_id => $crossing_experiment_id});
    my $previous_projectprop_rs = $crossing_experiment->projectprops({type_id=>$file_metadata_cvterm->cvterm_id});
    if ($previous_projectprop_rs->count == 1){
        my $file_metadata_string = $previous_projectprop_rs->first->value();
        my $file_metadata_ref = decode_json $file_metadata_string;
        %file_metadata = %{$file_metadata_ref};
        $file_metadata{'intercross_download'}{$file_id}{'file_type'} = 'intercross_wishlist';
        my $updated_file_metadata_json = encode_json \%file_metadata;
        $previous_projectprop_rs->first->update({value=>$updated_file_metadata_json});
    } elsif ($previous_projectprop_rs->count > 1) {
        print STDERR "More than one found!\n";
        return;
    } else {
        $file_metadata{'intercross_download'}{$file_id}{'file_type'} = 'intercross_wishlist';
        my $file_metadata_json = encode_json \%file_metadata;
        $crossing_experiment->create_projectprops( { $file_metadata_cvterm->name() => $file_metadata_json } );
    }

    $c->stash->{rest} = {
        success => 1,
        file_id => $file_id,
        data => \@all_combinations
    };

}


sub upload_intercross_file : Path('/ajax/cross/upload_intercross_file') : ActionClass('REST'){ }

sub upload_intercross_file_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    my $cross_id_format = $c->req->param('cross_id_format_option');
    my $page_crossing_experiment_id = $c->req->param('intercross_experiment_id');
    my $upload = $c->req->upload('intercross_file');
    my $parser;
    my $parsed_data;
    my $upload_original_name = $upload->filename();
    my $upload_tempfile = $upload->tempname;
    my $subdirectory = "intercross_upload";
    my $archived_filename_with_path;
    my $md5;
    my $validate_file;
    my $parsed_file;
    my $parse_errors;
    my %parsed_data;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $user_role;
    my $user_id;
    my $user_name;
    my $owner_name;
    my $session_id = $c->req->param("sgn_session_id");
    my @error_messages;

    if ($session_id){
        my $dbh = $c->dbc->dbh;
        my @user_info = CXGN::Login->new($dbh)->query_from_cookie($session_id);
        if (!$user_info[0]){
            $c->stash->{rest} = {error=>'You must be logged in to upload intercross data!'};
            $c->detach();
        }
        $user_id = $user_info[0];
        $user_role = $user_info[1];
        my $p = CXGN::People::Person->new($dbh, $user_id);
        $user_name = $p->get_username;
    } else {
        if (!$c->user){
            $c->stash->{rest} = {error=>'You must be logged in to upload intercross data!'};
            $c->detach();
        }
        $user_id = $c->user()->get_object()->get_sp_person_id();
        $user_name = $c->user()->get_object()->get_username();
        $user_role = $c->user->get_object->get_user_type();
    }

    if (($user_role ne 'curator') && ($user_role ne 'submitter')) {
        $c->stash->{rest} = {error=>'Only a submitter or a curator can upload intercross file'};
        $c->detach();
    }

    my $uploader = CXGN::UploadFile->new({
        tempfile => $upload_tempfile,
        subdirectory => $subdirectory,
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });

    ## Store uploaded temporary file in arhive
    $archived_filename_with_path = $uploader->archive();
    $md5 = $uploader->get_md5($archived_filename_with_path);
    if (!$archived_filename_with_path) {
        $c->stash->{rest} = {error => "Could not save file $upload_original_name in archive",};
        return;
    }
    unlink $upload_tempfile;

    #parse uploaded file with appropriate plugin
    $parser = CXGN::Pedigree::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('IntercrossCSV');
    $parsed_data = $parser->parse();
#    print STDERR "PARSED DATA =". Dumper($parsed_data)."\n";
    if (!$parsed_data){
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;
            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error};
        $c->detach();
    }

    if ($parsed_data){

        my $md_row = $metadata_schema->resultset("MdMetadata")->create({create_person_id => $user_id});
        $md_row->insert();
        my $upload_file = CXGN::UploadFile->new();
        my $md5 = $upload_file->get_md5($archived_filename_with_path);
        my $md5checksum = $md5->hexdigest();
        my $file_row = $metadata_schema->resultset("MdFiles")->create({
            basename => basename($archived_filename_with_path),
            dirname => dirname($archived_filename_with_path),
            filetype => 'intercross_upload',
            md5checksum => $md5checksum,
            metadata_id => $md_row->metadata_id(),
        });
        my $file_id = $file_row->file_id();

        my %intercross_data = %{$parsed_data};
        my $crossing_experiment_name = $intercross_data{'crossing_experiment_name'};
        my $crossing_experiment_rs = $schema->resultset('Project::Project')->find({name => $crossing_experiment_name});
        my $crossing_experiment_id = $crossing_experiment_rs->project_id();

        my $page_crossing_experiment_rs = $schema->resultset('Project::Project')->find({project_id => $page_crossing_experiment_id});
        my $page_crossing_experiment_name = $page_crossing_experiment_rs->name();

        if ($crossing_experiment_id != $page_crossing_experiment_id) {
            $c->stash->{rest} = {error_string => "Error: You are uploading data for crossing experiment:$crossing_experiment_name on $page_crossing_experiment_name page!"};
            $c->detach();
        }

        my $crosses_ref = $intercross_data{'crosses'};
        my %crosses_hash = %{$crosses_ref};
        my @intercross_identifier_list = keys %crosses_hash;

        my $crosses = CXGN::Cross->new({schema => $schema, trial_id => $crossing_experiment_id});
        my $identifiers = $crosses->get_cross_identifiers_in_crossing_experiment();
        my %existing_identifier_hash = %{$identifiers};

        my @new_cross_identifiers;
        if (%existing_identifier_hash) {
            my @existing_identifier_list = keys %existing_identifier_hash;

            foreach my $intercross_identifier(@intercross_identifier_list) {
                if (none {$_ eq $intercross_identifier} @existing_identifier_list) {
                    push @new_cross_identifiers, $intercross_identifier;
                }
            }
        } else {
            @new_cross_identifiers = @intercross_identifier_list;
        }
#        print STDERR "NEW CROSS IDENTIFIER ARRAY =".Dumper(\@new_cross_identifiers)."\n";

        my @new_crosses;
        my %new_stockprop;
        if (scalar(@new_cross_identifiers) > 0) {
            if ($cross_id_format eq 'customized_id') {
                foreach my $new_identifier (@new_cross_identifiers) {
                    my $intercross_female_parent = $crosses_hash{$new_identifier}{'intercross_female_parent'};
                    my $intercross_male_parent = $crosses_hash{$new_identifier}{'intercross_male_parent'};
                    push @error_messages, "Cross between $intercross_female_parent and $intercross_male_parent has no associated cross unique ID in crossing experiment: $crossing_experiment_name";
                }

                my $formatted_error_messages = join("<br>", @error_messages);
                $c->stash->{rest} = {error_string => $formatted_error_messages};
                return;
            } elsif ($cross_id_format eq 'auto_generated_id') {
                my $accession_stock_type_id  =  SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();
                my $plot_stock_type_id  =  SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();
                my $plant_stock_type_id  =  SGN::Model::Cvterm->get_cvterm_row($schema, 'plant', 'stock_type')->cvterm_id();
                my $plot_of_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_of', 'stock_relationship')->cvterm_id();
                my $plant_of_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant_of', 'stock_relationship')->cvterm_id();

                my $generated_cross_unique_id;

                if (%existing_identifier_hash) {
                    my @existing_cross_unique_ids = values %existing_identifier_hash;
                    my @sorted_existing_cross_unique_ids = natsort @existing_cross_unique_ids;
                    $generated_cross_unique_id = $sorted_existing_cross_unique_ids[-1];
                } else {
                    $generated_cross_unique_id = $crossing_experiment_name.'_'.'0';
                }
#                print STDERR "STARTING GENERATED CROSS UNIQUE ID =".Dumper($generated_cross_unique_id)."\n";
                foreach my $new_identifier (@new_cross_identifiers) {
                    $generated_cross_unique_id =~ s/(\d+)$/$1 + 1/e;
#                    print STDERR "GENERATED CROSS UNIQUE ID =".Dumper($generated_cross_unique_id)."\n";
                    my $validate_new_cross_rs = $schema->resultset("Stock::Stock")->search({uniquename=> $generated_cross_unique_id});
                    if ($validate_new_cross_rs->count() > 0) {
                        $c->stash->{rest} = {error_string => "Error creating new cross unique id",};
                        return;
                    }

                    my $intercross_cross_type = $crosses_hash{$new_identifier}{'cross_type'};
                    my $cross_type;
                    if ($intercross_cross_type eq 'BIPARENTAL') {
                        $cross_type = 'biparental';
                    } elsif ($intercross_cross_type eq 'SELF') {
                        $cross_type = 'self';
                    } elsif ($intercross_cross_type eq 'OPEN') {
                        $cross_type = 'open';
                    } elsif ($intercross_cross_type eq 'POLY') {
                        $cross_type = 'polycross';
                    }

                    my $pedigree =  Bio::GeneticRelationships::Pedigree->new(name => $generated_cross_unique_id, cross_type =>$cross_type);
                    my $intercross_female_parent = $crosses_hash{$new_identifier}{'intercross_female_parent'};
                    my $intercross_female_stock_id = $schema->resultset("Stock::Stock")->find({uniquename => $intercross_female_parent})->stock_id();
                    my $intercross_female_type_id = $schema->resultset("Stock::Stock")->find({uniquename => $intercross_female_parent})->type_id();

                    my $female_parent_name;
                    my $female_parent_stock_id;
                    if ($intercross_female_type_id == $plot_stock_type_id) {
                        $female_parent_stock_id = $schema->resultset("Stock::StockRelationship")->find({subject_id=>$intercross_female_stock_id, type_id=>$plot_of_type_id})->object_id();
                        $female_parent_name = $schema->resultset("Stock::Stock")->find({stock_id => $female_parent_stock_id})->uniquename();
                        my $female_plot_individual = Bio::GeneticRelationships::Individual->new(name => $intercross_female_parent);
                        $pedigree->set_female_plot($female_plot_individual);
                    } elsif ($intercross_female_type_id == $plant_stock_type_id) {
                        $female_parent_stock_id = $schema->resultset("Stock::StockRelationship")->find({subject_id=>$intercross_female_stock_id, type_id=>$plant_of_type_id})->object_id();
                        $female_parent_name = $schema->resultset("Stock::Stock")->find({stock_id => $female_parent_stock_id})->uniquename();
                        my $female_plant_individual = Bio::GeneticRelationships::Individual->new(name => $intercross_female_parent);
                        $pedigree->set_female_plant($female_plant_individual);
                    } else {
                        $female_parent_name = $intercross_female_parent;
                    }

                    my $female_parent_individual = Bio::GeneticRelationships::Individual->new(name => $female_parent_name);
                    $pedigree->set_female_parent($female_parent_individual);

                    my $intercross_male_parent = $crosses_hash{$new_identifier}{'intercross_male_parent'};
                    my $male_parent_name;
                    if ($intercross_male_parent) {
                        my $male_parent_stock_id;
                        my $intercross_male_stock_id = $schema->resultset("Stock::Stock")->find({uniquename => $intercross_male_parent})->stock_id();
                        my $intercross_male_type_id = $schema->resultset("Stock::Stock")->find({uniquename => $intercross_male_parent})->type_id();

                        if ($intercross_male_type_id == $plot_stock_type_id) {
                            $male_parent_stock_id = $schema->resultset("Stock::StockRelationship")->find({subject_id=>$intercross_male_stock_id, type_id=>$plot_of_type_id})->object_id();
                            $male_parent_name = $schema->resultset("Stock::Stock")->find({stock_id => $male_parent_stock_id})->uniquename();
                            my $male_plot_individual = Bio::GeneticRelationships::Individual->new(name => $intercross_male_parent);
                            $pedigree->set_male_plot($male_plot_individual);
                        } elsif ($intercross_male_type_id == $plant_stock_type_id) {
                            $male_parent_stock_id = $schema->resultset("Stock::StockRelationship")->find({subject_id=>$intercross_male_stock_id, type_id=>$plant_of_type_id})->object_id();
                            $male_parent_name = $schema->resultset("Stock::Stock")->find({stock_id => $male_parent_stock_id})->uniquename();
                            my $male_plant_individual = Bio::GeneticRelationships::Individual->new(name => $intercross_male_parent);
                            $pedigree->set_male_plant($male_plant_individual);
                        } else {
                            $male_parent_name = $intercross_male_parent
                        }

                        my $male_parent_individual = Bio::GeneticRelationships::Individual->new(name => $male_parent_name);
                        $pedigree->set_male_parent($male_parent_individual);
                    }

                    my $cross_combination = $female_parent_name.'/'.$male_parent_name;
                    $pedigree->set_cross_combination($cross_combination);

                    push @new_crosses, $pedigree;

                    $new_stockprop{$generated_cross_unique_id} = $new_identifier;
                    $existing_identifier_hash{$new_identifier} = $generated_cross_unique_id;
                }

                my $cross_add = CXGN::Pedigree::AddCrosses->new({
                    chado_schema => $schema,
                    phenome_schema => $phenome_schema,
                    metadata_schema => $metadata_schema,
                    dbh => $dbh,
                    crossing_trial_id => $crossing_experiment_id,
                    crosses => \@new_crosses,
                    user_id => $user_id,
                    file_id => $file_id
                });

                if (!$cross_add->validate_crosses()){
                    $c->stash->{rest} = {error_string => "Error validating crosses",};
                    return;
                }

                if (!$cross_add->add_crosses()){
                    $c->stash->{rest} = {error_string => "Error adding crosses",};
                    return;
                }
           }
        }

        foreach my $cross_identifier(keys %crosses_hash) {
            my $cross_transaction_info = $crosses_hash{$cross_identifier}{'activities'};
            my $db_cross_unique_id = $existing_identifier_hash{$cross_identifier};
            my $cross_transaction = CXGN::Pedigree::AddCrossTransaction->new({
                chado_schema => $schema,
                cross_unique_id => $db_cross_unique_id,
                transaction_info => $cross_transaction_info
            });

            my $return = $cross_transaction->add_intercross_transaction();

            if (!$return) {
                $c->stash->{rest} = {error_string => "Error adding cross transaction",};
                return;
            }
        }

        my $file_metadata_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'file_metadata_json', 'project_property');
        my %file_metadata;
        my $crossing_experiment = $schema->resultset("Project::Project")->find({project_id => $crossing_experiment_id});
        my $previous_projectprop_rs = $crossing_experiment->projectprops({type_id=>$file_metadata_cvterm->cvterm_id});
        if ($previous_projectprop_rs->count == 1){
            my $file_metadata_string = $previous_projectprop_rs->first->value();
            my $file_metadata_ref = decode_json $file_metadata_string;
            %file_metadata = %{$file_metadata_ref};
            $file_metadata{'intercross_upload'}{$file_id}{'file_type'} = 'intercross_upload';
            my $updated_file_metadata_json = encode_json \%file_metadata;
            $previous_projectprop_rs->first->update({value=>$updated_file_metadata_json});
        } elsif ($previous_projectprop_rs->count > 1) {
            print STDERR "More than one found!\n";
            return;
        } else {
            $file_metadata{'intercross_upload'}{$file_id}{'file_type'} = 'intercross_upload';
            my $file_metadata_json = encode_json \%file_metadata;
            $crossing_experiment->create_projectprops( { $file_metadata_cvterm->name() => $file_metadata_json } );
        }
    }

    $c->stash->{rest} = {success => "1",};
}


sub upload_cip_cross_file : Path('/ajax/cross/upload_cip_cross_file') : ActionClass('REST'){ }

sub upload_cip_cross_file_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    my $crossing_experiment_id = $c->req->param('cip_cross_experiment_id');
    my $upload = $c->req->upload('cip_cross_file');
    my $parser;
    my $parsed_data;
    my $upload_original_name = $upload->filename();
    my $upload_tempfile = $upload->tempname;
    my $subdirectory = "cip_cross_upload";
    my $archived_filename_with_path;
    my $md5;
    my $validate_file;
    my $parsed_file;
    my $parse_errors;
    my %parsed_data;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $user_role;
    my $user_id;
    my $user_name;
    my $owner_name;
    my $session_id = $c->req->param("sgn_session_id");
    my @error_messages;

    if ($session_id){
        my $dbh = $c->dbc->dbh;
        my @user_info = CXGN::Login->new($dbh)->query_from_cookie($session_id);
        if (!$user_info[0]){
            $c->stash->{rest} = {error=>'You must be logged in to upload CIP-Cross data!'};
            $c->detach();
        }
        $user_id = $user_info[0];
        $user_role = $user_info[1];
        my $p = CXGN::People::Person->new($dbh, $user_id);
        $user_name = $p->get_username;
    } else {
        if (!$c->user){
            $c->stash->{rest} = {error=>'You must be logged in to upload CIP-Cross data!'};
            $c->detach();
        }
        $user_id = $c->user()->get_object()->get_sp_person_id();
        $user_name = $c->user()->get_object()->get_username();
        $user_role = $c->user->get_object->get_user_type();
    }

    if (($user_role ne 'curator') && ($user_role ne 'submitter')) {
        $c->stash->{rest} = {error=>'Only a submitter or a curator can upload CIP-Cross file'};
        $c->detach();
    }

    my $uploader = CXGN::UploadFile->new({
        tempfile => $upload_tempfile,
        subdirectory => $subdirectory,
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });

    ## Store uploaded temporary file in arhive
    $archived_filename_with_path = $uploader->archive();
    $md5 = $uploader->get_md5($archived_filename_with_path);
    if (!$archived_filename_with_path) {
        $c->stash->{rest} = {error => "Could not save file $upload_original_name in archive",};
        return;
    }
    unlink $upload_tempfile;

    #parse uploaded file with appropriate plugin
    $parser = CXGN::Pedigree::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('CIPcross');
    $parsed_data = $parser->parse();
#    print STDERR "PARSED DATA =". Dumper($parsed_data)."\n";
    if (!$parsed_data){
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;
            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error};
        $c->detach();
    }

    if ($parsed_data){
#        print STDERR "CIP CROSS DATA =".Dumper($parsed_data->{crosses})."\n";

        my $md_row = $metadata_schema->resultset("MdMetadata")->create({create_person_id => $user_id});
        $md_row->insert();
        my $upload_file = CXGN::UploadFile->new();
        my $md5 = $upload_file->get_md5($archived_filename_with_path);
        my $md5checksum = $md5->hexdigest();
        my $file_row = $metadata_schema->resultset("MdFiles")->create({
            basename => basename($archived_filename_with_path),
            dirname => dirname($archived_filename_with_path),
            filetype => 'crosses',
            md5checksum => $md5checksum,
            metadata_id => $md_row->metadata_id(),
        });
        my $file_id = $file_row->file_id();

        my $cross_add = CXGN::Pedigree::AddCrosses->new({
            chado_schema => $schema,
            phenome_schema => $phenome_schema,
            metadata_schema => $metadata_schema,
            dbh => $dbh,
            crossing_trial_id => $crossing_experiment_id,
            crosses =>  $parsed_data->{crosses},
            user_id => $user_id,
            file_id => $file_id
        });

        #validate the crosses
        if (!$cross_add->validate_crosses()){
            $c->stash->{rest} = {error_string => "Error validating crosses",};
            return;
        }
        if (!$cross_add->add_crosses()){
            $c->stash->{rest} = {error_string => "Error adding crosses",};
            return;
        }

        my $cross_info = $parsed_data->{cross_info};
        my %cip_cross_info = %{$cross_info};
#        print STDERR "CIP CROSS INFO =".Dumper(\%cip_cross_info)."\n";
        my $cross_info_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema,'crossing_metadata_json', 'stock_property');

        my $cross_json_string;
        my $cross_json_hash_ref = {};
        my %cross_json_hash;
        my %all_cross_info;
        foreach my $cross_name_key (keys %cip_cross_info){
            %cross_json_hash = ();
            %all_cross_info = ();
            %{$cross_json_hash_ref} =();
            my $valid_cross_name = $schema->resultset("Stock::Stock")->find({uniquename => $cross_name_key});
            if ($valid_cross_name){
                my %info_hash = %{$cip_cross_info{$cross_name_key}};
#                print STDERR "CROSS NAME KEY =".Dumper($cross_name_key)."\n";
#                print STDERR "NEW INFO HASH =".Dumper(\%info_hash)."\n";

                my $previous_stockprop_rs = $valid_cross_name->stockprops({type_id=>$cross_info_cvterm->cvterm_id});
                if ($previous_stockprop_rs->count == 1){
                    $cross_json_string = $previous_stockprop_rs->first->value();
                    $cross_json_hash_ref = decode_json $cross_json_string;
                    %cross_json_hash = %{$cross_json_hash_ref};
                    %all_cross_info = (%cross_json_hash, %info_hash);
#                    print STDERR "PREVIOUS CROSS INFO =".Dumper(\%cross_json_hash);
#                    print STDERR "ALL CROSS INFO =".Dumper(\%all_cross_info);
                    my $all_cross_info_string = encode_json \%all_cross_info;
                    $previous_stockprop_rs->first->update({value=>$all_cross_info_string});
                } elsif ($previous_stockprop_rs->count > 1) {
                    print STDERR "More than one found!\n";
                    return;
                } else {
                    my $new_cross_info_string = encode_json \%info_hash;
                    $valid_cross_name->create_stockprops({$cross_info_cvterm->name() => $new_cross_info_string});
                }
            }
        }

        my $cross_additional_info = $parsed_data->{cross_additional_info};
        my %cip_cross_additional_info = %{$cross_additional_info};
        my $cross_additional_info_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema,'cross_additional_info', 'stock_property');
        print STDERR "CIP CROSS ADDITIONAL INFO =".Dumper(\%cip_cross_additional_info)."\n";

        my $cross_additional_info_string;
        my $cross_additional_info_hash_ref = {};
        my %cross_additional_info_hash;
        my %all_cross_additional_info;

        foreach my $name_key (keys %cip_cross_additional_info){
            %cross_additional_info_hash = ();
            %all_cross_additional_info = ();
            %{$cross_additional_info_hash_ref} =();

            my $valid_name_key = $schema->resultset("Stock::Stock")->find({uniquename => $name_key});
            if ($valid_name_key){
                my %additional_info_hash = %{$cip_cross_additional_info{$name_key}};
                print STDERR "NAME KEY =".Dumper($name_key)."\n";
                print STDERR "NEW ADDITIONAL INFO HASH =".Dumper(\%additional_info_hash)."\n";
                my $previous_additional_stockprop_rs = $valid_name_key->stockprops({type_id=>$cross_additional_info_cvterm->cvterm_id});
                if ($previous_additional_stockprop_rs->count == 1){
                    $cross_additional_info_string = $previous_additional_stockprop_rs->first->value();
                    $cross_additional_info_hash_ref = decode_json $cross_additional_info_string;
                    %cross_additional_info_hash = %{$cross_additional_info_hash_ref};
                    %all_cross_additional_info = (%cross_additional_info_hash, %additional_info_hash);
                    print STDERR "PREVIOUS CROSS ADDITIONAL INFO =".Dumper(\%cross_additional_info_hash);
                    print STDERR "ALL CROSS ADDITIONAL INFO =".Dumper(\%all_cross_additional_info);
                    my $all_additional_info_string = encode_json \%all_cross_additional_info;
                    $previous_additional_stockprop_rs->first->update({value=>$all_additional_info_string});
                } elsif ($previous_additional_stockprop_rs->count > 1) {
                    print STDERR "More than one found!\n";
                    return;
                } else {
                    my $new_additional_info_string = encode_json \%additional_info_hash;
                    $valid_name_key->create_stockprops({$cross_additional_info_cvterm->name() => $new_additional_info_string});
                }
            }
        }

        my %project_additional_info = %{$parsed_data->{project_info}};
        my %formatted_info;
        while (my ($key, $value) =  each(%project_additional_info)) {
            my $additional_info = (keys %{$value})[0];
            $formatted_info{$key} = $additional_info;
        }
#        print STDERR "FORMATTED INFO =".Dumper(\%formatted_info)."\n";

        my $project_additional_info_string = encode_json \%formatted_info;
        my $crossing_experiment = $schema->resultset("Project::Project")->find({project_id => $crossing_experiment_id});
        my $crossing_experiment_additional_into_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema,'crossing_experiment_additional_info', 'project_property');
        $crossing_experiment->create_projectprops({$crossing_experiment_additional_into_cvterm->name() => $project_additional_info_string});

        my %parent_info = %{$parsed_data->{parent_info}};
        my $parent_info_string = encode_json \%parent_info;
        my $crossing_experiment_rs = $schema->resultset("Project::Project")->find({project_id => $crossing_experiment_id});
        my $parent_into_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema,'crossing_experiment_parent_info', 'project_property');
        $crossing_experiment_rs->create_projectprops({$parent_into_cvterm->name() => $parent_info_string});
    }

    $c->stash->{rest} = {success => "1",};
}


sub get_project_female_info :Path('/ajax/cross/project_female_info') :Args(1) {
    my $self = shift;
    my $c = shift;
    my $crossing_experiment_id = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my @project_female_info;

    my $crossing_experiment = CXGN::Cross->new( {schema => $schema, trial_id => $crossing_experiment_id });
    my $project_parent_info = $crossing_experiment->get_crossing_experiment_parent_info();

    if ($project_parent_info) {
        my $female_parent_info = $project_parent_info->{'female'};
        my $female_info_keys = $c->config->{crossing_experiment_female_info};
        my @female_keys = split ',',$female_info_keys;

        foreach my $female_parent (keys %{$female_parent_info}) {
            my @each_female_details = ();
            foreach my $female_key (@female_keys) {
                push @each_female_details, $female_parent_info->{$female_parent}->{$female_key};
            }
            push @project_female_info, [@each_female_details];
        }
    }

    $c->stash->{rest} = { data => \@project_female_info};

}

sub get_project_male_info :Path('/ajax/cross/project_male_info') :Args(1) {
    my $self = shift;
    my $c = shift;
    my $crossing_experiment_id = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my @project_male_info;

    my $crossing_experiment = CXGN::Cross->new( {schema => $schema, trial_id => $crossing_experiment_id });
    my $project_parent_info = $crossing_experiment->get_crossing_experiment_parent_info();

    if ($project_parent_info) {
        my $male_parent_info = $project_parent_info->{'male'};
        my $male_info_keys = $c->config->{crossing_experiment_male_info};
        my @male_keys = split ',',$male_info_keys;

        foreach my $male_parent (keys %{$male_parent_info}) {
            my @each_male_details = ();
            foreach my $male_key (@male_keys) {
                push @each_male_details, $male_parent_info->{$male_parent}->{$male_key};
            }
            push @project_male_info, [@each_male_details];
        }
    }

    $c->stash->{rest} = { data => \@project_male_info};

}


1;
