#!/usr/bin/env perl


=head1 NAME

AddAnalyticsProtocolCvterms

=head1 SYNOPSIS

mx-run AddAnalyticsProtocolCvterms [options] -H hostname -D dbname -u username [-F]

this is a subclass of L<CXGN::Metadata::Dbpatch>
see the perldoc of parent class for more details.

=head1 DESCRIPTION
This patch adds cvterms for analytics protocols. These protocols are for saving results/graphs/files from analytics processes
This subclass uses L<Moose>. The parent class uses L<MooseX::Runnable>

=head1 AUTHOR

=head1 COPYRIGHT & LICENSE

Copyright 2010 Boyce Thompson Institute for Plant Research

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


package AddAnalyticsProtocolCvterms;

use Moose;
use Bio::Chado::Schema;
use Try::Tiny;
extends 'CXGN::Metadata::Dbpatch';


has '+description' => ( default => <<'' );
This patch adds cvterms for analytics protocols. These protocols are for saving results/graphs/files from analytics processes

has '+prereq' => (
	default => sub {
        [],
    },

);

sub patch {
    my $self=shift;

    print STDOUT "Executing the patch:\n " .   $self->name . ".\n\nDescription:\n  ".  $self->description . ".\n\nExecuted by:\n " .  $self->username . " .";

    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";

    print STDOUT "\nExecuting the SQL commands.\n";
    my $schema = Bio::Chado::Schema->connect( sub { $self->dbh->clone } );

    print STDERR "INSERTING CV TERMS...\n";

    my $terms = {
        'protocol_type' => [
            'drone_imagery_analytics_env_simulation_protocol'
        ],
        'protocol_property' => [
            'analytics_protocol_properties',
            'analytics_protocol_result_summary',
        ],
        'experiment_type' => [
            'analytics_protocol_experiment'
        ]
    };

    foreach my $t (keys %$terms){
        foreach (@{$terms->{$t}}){
            $schema->resultset("Cv::Cvterm")->create_with({
                name => $_,
                cv => $t
            });
        }
    }

    print "You're done!\n";
}


####
1; #
####
