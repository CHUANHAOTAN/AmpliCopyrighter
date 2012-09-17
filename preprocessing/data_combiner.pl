#! /usr/bin/env perl

# data_combiner
# Copyright 2012 Adam Skarshewski
# You may distribute this module under the terms of the GPLv3


=head1 NAME

data_combiner - Combine IDs and other data from different sources

=head1 SYNOPSIS

  data_combiner.pl -i img_metadata.tsv -g gg_tax.txt -c 16S_vs_prokMSA.list > output.txt

=head1 DESCRIPTION

Take an IMG metadata file, Greengenes taxonomy file, and IMG-GG correspondance
file and combine them into one.

The output of this script is a tab-delimited file containing these columns: IMG
ID, IMG Name, IMG Tax, GG ID, GG Tax, 16S Count, Genome Length, Gene Count.

=head1 REQUIRED ARGUMENTS

=over

=item -i <img_file>

Input IMG metadata file. The IMG metadata file can be obtained using the export
function of IMG (http://img.jgi.doe.gov/). It should have 13 tab-delimited
columns (in this order): taxon_oid, Domain, Status, Genome Name, Phylum, Class,
Order, Family, Genus, Species, Genome Size, Gene Count, 16S rRNA Count.

=for Euclid:
   img_file.type: readable

=item -g <gg_file>

Input Greengenes taxonomy file. The Greengenes taxonomy file
(http://www.secondgenome.com/go/2011-greengenes-taxonomy/) is tab-delimited and
has two columns: prokMSA_ID, GG taxonomy string.

=for Euclid:
   gg_file.type: readable

=item -c <corr_file>

IMG - Greengenes correspondance file. The tab-delimited correlation file
contains these columns: IMG ID (taxon_oid), GG ID (prokMSA_ID). Some of these
correspondances can be extracted from GOLD (http://www.genomesonline.org/).

=for Euclid:
   corr_file.type: readable

=back

=head1 OPTIONAL ARGUMENTS

=over

=item -f <finished>

Include finished genomes only: 1 is yes, 0 is no (include draft genomes as well).
Default: finished.default

=for Euclid:
   finished.type: integer, finished == 0 || finished == 1
   finished.default: 1

=item -s <species>

Fix missing missing genus and species name in Greengenes taxonomy string when
possible: 1 is yes, 0 is no. Default: species.default

=for Euclid:
   species.type: integer, species == 0 || species == 1
   species.default: 1

=back

=head1 AUTHOR

Adam Skarshewski

=head1 BUGS

All complex software has bugs lurking in it, and this program is no exception.
If you find a bug, please report it on the SourceForge Tracker:
L<http://github.com/fangly/AmpliCopyrighter/issues>

=head1 COPYRIGHT

Copyright 2012 Adam Skarshewski

Copyrighter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
Copyrighter is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with Copyrighter.  If not, see <http://www.gnu.org/licenses/>.

=cut


use strict;
use warnings;
use Getopt::Euclid qw(:minimal_keys);


# Create GG taxonomies hash
my $spp_space = ''; # space in species name?
my $sep_space = ''; # separator ';' followed by a space?
my %gg_taxonomies;
open(my $fh,  $ARGV{'g'}) or die "Error: Could not read file\n$!\n";
while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ m/^#/;
    my ($id, $tax_string) = split /\t/, $line;
    $gg_taxonomies{$id} = $tax_string;
    my $species = (split /;/, $tax_string)[-1];
    if ($species =~ s/^\s+//) {
        $sep_space = ' ';
    }
    if ($species =~ m/ /) {
        $spp_space = ' ';
    }
}
close($fh);
warn "Read ".scalar(keys(%gg_taxonomies))." entries from taxonomy file\n";


# Create IMG-GG correlation hash
my %correlations;
open($fh, $ARGV{'c'}) or die "Error: Could not read file\n$!\n";
while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ m/^#/;
    my ($img_id, $gg_id) = split /\t/, $line;
    $correlations{$img_id} = $gg_id;
}
close($fh);
warn "Read ".scalar(keys(%correlations))." entries from correlation file\n";


# Substitutions
my $num_fixed = 0;
print "#IMG ID\tIMG Name\tIMG Tax\tGG ID\tGG Tax\t16S Count\tGenome Length\tGene Count\n";
open($fh, $ARGV{'i'}) or die "Error: Could not read file\n$!\n";
<$fh>; # burn headers
my $num = 0;
while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ m/^#/;
    $num++;
    my @splitline = split /\t/, $line;
    my $domain = $splitline[1];
    my $status = $splitline[2];
    
    if (! (($domain eq 'Bacteria') || ($domain eq 'Archaea'))) {
        # Keep only bacteria and archaea. Skip eukaryotes, etc.
        next;
    }

    if ($ARGV{'f'}) {
        # Keep only finished genomes. Skip draft genomes, etc.
        if (! ($status eq 'Finished')) {
            next;
        }
    }
    
    my $img_id      = $splitline[0];
    my $img_name    = $splitline[3];
    my $img_tax     = join(";", @splitline[4..9]);
    my $gg_id       = $correlations{$img_id};
    my $gg_tax      = (defined($gg_id) && exists($gg_taxonomies{$gg_id})) ? $gg_taxonomies{$gg_id} : '-';
    my $rRNA_count  = $splitline[12];
    my $genome_size = $splitline[10];
    my $gene_count  = $splitline[11];
    
    if ($ARGV{'s'}) {
        $gg_tax = fix_gg_tax($gg_tax, $img_name);
    }

    if ((defined ($rRNA_count)) && ($rRNA_count > 0)) {
            print(join("\t",(
                     $img_id,
                     $img_name,
                     $img_tax,
                     (defined($gg_id) ? $gg_id : '-'),
                     $gg_tax,
                     $rRNA_count,
                     $genome_size,
                     $gene_count
                     )), "\n");
    }

}
close($fh);
warn "Read $num entries from metadata file\n";
warn "Fixed $num_fixed GG taxonomy strings\n";

exit;



sub fix_gg_tax {
    # If genus or species is missing from GG taxonomy string but present in IMG
    # name, add them to the GG taxonomy string. Abort if anything is suspicious,
    # e.g. lowercase genus, uppercase species, inconsistent genus, wrong number
    # of fields.
    my ($gg_tax, $img_name) = @_;

    my $tmp_name = $img_name;
    my $candidatus = ($tmp_name =~ s/^Candidatus\s+//i);
    my ($genus, $species, $strain) = split /\s+/, $tmp_name;

    # Genus should be capitalized
    #my $msg = 'Not fixing the taxonomy string';
    if ($genus =~ /^[a-z]/) {
        # Fishy genus
        #warn "Warning: Genus $genus is lowercase. $msg\n";
        return $gg_tax;
    }

    # Species should not be capitalized
    if ($species =~ /^[A-Z]/) {
        # Fishy species
        #warn "Warning: Species $species is uppercase. $msg\n";
        return $gg_tax;
    }

    my $names = [ split /;\s*/, $gg_tax ];
    if (scalar @$names == 7) { # Proper number of fields, not simply '-'

        my $tax_genus   = $names->[-2];
        my $tax_species = $names->[-1];

        if ( ($tax_genus eq 'g__') || ($tax_species eq 's__') ) {
            # Should try to fix, but check that it is safe
            if ( (not $tax_genus eq 'g__') &&
                 (not $tax_genus eq 'g__'.($candidatus?'Candidatus ':'').$genus) ) {
                #warn "Warning: Genus disagreement for '$img_name'. Genus in taxonomy ".
                #    "string is $tax_genus. $msg\n";
            } else {

                my $fixed = 0;
 
                # Fix genus if it is known
                if ( (not $genus eq '') && ($tax_genus eq 'g__') ) {
                    $names->[-2] = 'g__'.$genus;
                    $fixed = 1;
                }

                # Fix species if it is known
                if ( ($species !~ m/^sp\.?$/) && ($tax_species eq 's__') ) {
                    $names->[-1] = 's__'.($candidatus?'Candidatus'.$spp_space:'').$genus.$spp_space.$species;
                    $fixed = 1;
                }

                $num_fixed++ if $fixed;
                $gg_tax = join ';'.$sep_space, @$names;

            }
        }
    }

    return $gg_tax;
}

