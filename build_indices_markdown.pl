use 5.036;
use strict;
use warnings;
use JSON;
use Carp qw /croak/;
use experimental qw /for_list refaliasing declared_refs/;
use Ref::Util qw /is_arrayref/;

my $col_index     = 0;
my $col_descr     = 1;
my $col_clus_text = 2;
my $col_nbr_count = 3;
my $col_formula   = 4;
my $col_reference = 5;

my $json_file = $ARGV[0] // 'indices.json';

open my $json_fh, $json_file or die $!;
my $json = do {local $/ = undef; <$json_fh>};
$json_fh->close;

my $data = decode_json ($json);


# my $version = $data->{_meta}{version};

my $wiki_leader  = "# $data->{_meta}{title} \n";
   $wiki_leader .= '_Generated GMT '
                    . (gmtime)
                    . ", Biodiverse version $data->{_meta}{version}._\n";

my $intro_wiki = $wiki_leader;

$intro_wiki .= <<"END_OF_INTRO";

This is a listing of the indices available in Biodiverse,
ordered by the calculations used to generate them.
It is generated from the system metadata and contains all the 
information visible in the GUI, plus some additional details.

Most of the headings are self-explanatory.  For the others:

  * The *Subroutine* is the name of the subroutine used to call the function if you
    are using Biodiverse through a script.
  * The *Index* is the name of the index in the SPATIAL_RESULTS list, or if it is its own list
    then this will be its name.  These lists can contain a variety of values, but are usually
    lists of labels with some value, for example the weights used in an endemism calculation.
    The names of such lists typically end in "LIST", "ARRAY", "HASH", "LABELS" or "STATS".
  * *Grouping?* states whether or not the index can be used to define the grouping for a
    cluster or region grower analysis.  A blank value means it cannot be used for either.
  * The *Minimum number of neighbour sets* dictates whether or not a calculation or index will
    be run.  If you specify only one neighbour set then all those calculations that require
    two sets will be dropped from the analysis.  (This is always the case for calculations
    applied to cluster nodes as there is only one neighbour set, defined by the set of groups
    linked to the terminal nodes below a cluster node).  Note that many of the calculations
    lump neighbour sets 1 and 2 together.  See the
    [SpatialConditions](https://biogeospatial.github.io/biodiverse-spatial-conditions/)
    page for more details on neighbour sets.

Note that some calculations can provide different numbers of indices depending on the nature
of the BaseData set used.
This currently applies to the hierarchically partitioned endemism calculations (both
[central](#endemism-central-hierarchical-partition) and
[whole](#endemism-whole-hierarchical-partition)).

For space reasons, columns are not shown if all cells are empty.

END_OF_INTRO

my $tabular_md = get_calculation_metadata_as_markdown($data);

my $md = $intro_wiki . $tabular_md;

#  hyperlink the Label counts text for now
$md =~ s/'Label counts'/\[Label counts\]\(#label-counts\)/g;

my $fname = "Indices.qmd";

say "Writing to file $fname";

my $fh;
open ($fh, '>', $fname) || die $!;

print {$fh} $md;
close $fh;

say 'done';


#  now we have moved to github
sub get_calculation_metadata_as_markdown {
    my $data = shift;

    \my %calculations = $data->{calculations};
    my %by_type;
    foreach my ($sub_name, $calc) ( %calculations ) {
        my $type = $calc->{type};
        $calc->{sub_name} = $sub_name;
        my $ref  = $by_type{$type} //= [];
        push @$ref, $calc;
    }

    #  the html version
    my @header = map {"*$_*"} (
        'Index',
        'Description',
        'Grouping metric?',
        'Minimum number of neighbour sets',
        'Formula', 'Reference',
    );

    my %hash;

    my @toc;
    my %indices;
    my %calculation_hash;
    foreach my $type ( sort keys %by_type ) {
        # say "Type: $type";
        my $wiki_anchor = lc $type;
        $wiki_anchor =~ s/ /-/g;
        $wiki_anchor =~ s/[^a-z0-9-]//g;
        push @toc, "  * [$type](#$wiki_anchor)";
        \my @type_arr = $by_type{$type};
        foreach my $calculations ( sort { $a->{name} cmp $b->{name} } @type_arr ) {
            # warn $calculations;
            my $ref = $calculations;
            $ref->{analysis} = $calculations;
            $calculation_hash{$type}{$calculations} = $ref;
            my $wiki_anchor = lc $ref->{name};
            $wiki_anchor =~ s/ /-/g;
            $wiki_anchor =~ s/[^a-z0-9-]//g;
            push @toc, "    * [$ref->{name}](#$wiki_anchor)";
        }
    }

    #my $sort_by_type_then_name = sub {   $a->{type} cmp $b->{type}
    #                                  || $a->{name} cmp $b->{name}
    #                                  };

    my $markdown;

    $markdown .= "**Indices available in Biodiverse:**\n\n";
    $markdown .= join "\n", @toc;
    $markdown .= "\n\n";

    my %done;
    my $count = 1;
    my $SPACE = q{ };

    # my $codecogs_url = 'http://latex.codecogs.com/png.latex?';

    # warn 'here';
    my %region_grower_indices;

    #loop through the types
    BY_TYPE:
    foreach my $type ( sort keys %by_type ) {
        my $type_text = $type;

        #$type_text =~ s/\*/`\*`/;  #  escape any highlight characters
        #$type_text =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
        $markdown .= "## $type_text ##";

        my $type_ref = $by_type{$type};
        # use DDP; p $type_ref;

        BY_NAME:    #  loop through the names
        foreach my $ref ( sort { $a->{name} cmp $b->{name} } @$type_ref ) {
            my $sub_name    = $ref->{sub_name};
            my $name        = $ref->{name};
            my $description = $ref->{description};

            $markdown .= "\n \n### $name\n \n";
            $markdown .= "**Description:**   $description\n\n";
            $markdown .= "**Subroutine:**   $sub_name\n\n";

            #$markdown .= "<p><b>Module:</b>   $ref->{source_module}</p>\n";  #  not supported yet
            if ( my $reference = $ref->{reference} ) {
                $markdown
                    .= '**Reference:**   '
                    . _process_reference($reference)
                    . "\n\n";
            }

            my $formula = $ref->{formula};
            croak 'Formula is not an array'
                if defined $formula and not(is_arrayref($formula));

            if ( $formula and is_arrayref ($formula) ) {
                my $formula_url;
                my $iter = 0;

                FORMULA_ELEMENT_OVERVIEW:
                foreach my $element ( @{$formula} ) {
                    if ( !defined $element
                        || $element eq q{} )
                    {
                        $iter++;
                        next FORMULA_ELEMENT_OVERVIEW;
                    }

                    if ( $iter % 2 ) {

                        #$formula .= "\n";
                        if ( not $element =~ /^\s/ ) {
                            $formula_url .= ' ';
                        }
                        $formula_url .= $element;
                    }
                    else {
                        $formula_url .= _format_equation_as_markdown($element);
                    }
                    $iter++;
                }

                $markdown .= "**Formula:**\n   $formula_url\n\n";
            }

            $markdown .= "**Indices:**\n\n";
            my $indices_md;

            my @table;
            push @table, [@header];

            my @index_names = sort keys %{ $ref->{indices} };

            my $i              = 0;
            my ($uses_reference, $uses_formula, $uses_clus_text);

            foreach my $index ( @index_names ) {
                my $index_ref = $ref->{indices}{$index};

                #  repeated code from above - need to generalise to a sub
                my $formula_url;
                my $formula = $index_ref->{formula};
                croak "Formula for $index is not an array"
                    if defined $formula and not( is_arrayref($formula) );

                if ( is_arrayref($formula) and scalar @$formula) {

                    $uses_formula = 1;

                    my $iter = 0;
                    foreach my $element (@$formula) {
                        if ( $iter % 2 ) {
                            if ( not $element =~ /^\s/ ) {
                                $formula .= ' ';
                            }
                            $formula_url .= $element;
                        }
                        else {
                            $formula_url .= _format_equation_as_markdown($element);
                        }
                        $iter++;
                    }
                }
                $formula_url .= $SPACE;

                my @line;

                # push @line, $count;
                push @line, $index;

                my $descr = $index_ref->{description} || $SPACE;
                $descr =~ s{[\r\n]}{ }gmo;    # purge any newlines
                #$description =~ s/\*/`\*`/;  #  avoid needless bolding
                push @line, $descr;

                my $clus_text
                    = $index_ref->{cluster} ? 'cluster metric'
                    : $index_ref->{lumper}  ? 'region grower'
                    : $SPACE;
                $uses_clus_text ||= ($clus_text ne ' ');

                push @line, $clus_text;
                push @line,
                    $index_ref->{uses_nbr_lists} // $ref->{uses_nbr_lists} // $SPACE;
                push @line, $formula_url;
                my $reference = $index_ref->{reference};

                if ( defined $reference ) {
                    $uses_reference = 1;
                    $reference = _process_reference($reference);
                    $reference =~ s{\n}{ }gmo;
                }
                push @line, $reference || $SPACE;

                push @table, \@line;

                $indices_md .= " * $index\n";
                $indices_md .= "   + $descr\n";
                if ($reference) {
                    $indices_md .= "   + Reference: $reference\n"
                }

                $i++;
                $count++;
            }

            #  remove the reference col if none given
            if ( !$uses_reference ) {
                foreach my $row (@table) {
                    splice @$row, $col_reference, 1;
                }
            }
            #  and remove the formula also if need be
            if ( !$uses_formula ) {
                foreach my $row (@table) {
                    splice @$row, $col_formula, 1;
                }
            }
            #  and remove the grouping text if need be
            if ( !$uses_clus_text ) {
                foreach my $row (@table) {
                    splice @$row, $col_clus_text, 1;
                }
            }

            #$markdown .= $table;

            #  splice in the separator text
            my @separator = ('----') x scalar @{ $table[0] };
            splice @table, 1, 0, \@separator;

            if (@index_names) {
                foreach my $line (@table) {
                    my $line_text;
                    $line_text .= q{| };
                    $line_text .= join(q{ | }, @$line);
                    $line_text .= q{ |};
                    $line_text .= "\n";

                    #my $x = grep {! defined $_} @$line;

                    $markdown .= $line_text;
                }

                $markdown .= "\n\n";
            }
            else {
                $markdown .= "  * Data set dependent\n";
            }
            # $markdown .= $indices_md;  #  not yet
        }
    }

    return $markdown;
}

sub _format_equation_as_markdown {
    my ($text) = @_;
    return qq{\$$text\$};
}

sub _process_reference {
    my ($text) = @_;
    my @components = split /\s*;\s*/, $text;

    foreach my $text (@components) {
        if ($text =~ /(.+)\s+(http[s]?:.+)/) {
            my ($auth, $url) = ($1, $2);
            $auth =~ s/\.$//;
            $text = "[$auth]($url)";
        }
    }
    return join '; ', @components;
}
