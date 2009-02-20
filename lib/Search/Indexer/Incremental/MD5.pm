package Search::Indexer::Incremental::MD5 ;

use strict;
use warnings ;
use Carp qw(carp croak confess) ;

BEGIN 
{
use Sub::Exporter -setup => 
	{
	exports => [ qw(delete_indexing_databases) ],
	groups  => 
		{
		all  => [ qw() ],
		}
	};
	
use vars qw ($VERSION);
$VERSION     = '0.02';
}

#----------------------------------------------------------------------------------------------------------

use Digest::MD5 ;
use English qw( -no_match_vars ) ;

use Readonly ;
Readonly my $EMPTY_STRING => q{} ;

#----------------------------------------------------------------------------------------------------------

=head1 NAME

Search::Indexer::Incremental::MD5 - Incrementaly index your files

=head1 SYNOPSIS

  use File::Find::Rule ;
  
  use Readonly ;
  Readonly my $DEFAUT_MAX_FILE_SIZE_INDEXING_THRESHOLD => 300 << 10 ; # 300KB
  
  my $indexer 
	= Search::Indexer::Incremental::MD5::Indexer->new
		(
		USE_POSITIONS => 1, 
		INDEX_DIRECTORY => 'text_index', 
		get_perl_word_regex_and_stop_words(),
		) ;
  
  my @files = File::Find::Rule
		->file()
		->name( '*.pm', '*.pod' )
		->size( "<=$DEFAUT_MAX_FILE_SIZE_INDEXING_THRESHOLD" )
		->not_name(qr[auto | unicore | DateTime/TimeZone | DateTime/Locale])
		->in('.') ;
  
  indexer->add_files(@files) ;
  indexer->add_files(@more_files) ;
  indexer = undef ;
  
  my $search_string = 'find_me' ;
  my $searcher = 
	eval 
	{
	Search::Indexer::Incremental::MD5::Searcher->new
		(
		USE_POSITIONS => 1, 
		INDEX_DIRECTORY => 'text_index', 
		get_perl_word_regex_and_stop_words(),
		)
	} or croak "No full text index found! $@\n" ;
  
  my $results = $searcher->search($search_string) ;
  
  # sort in decreasing score order
  my @indexes = map { $_->[0] }
		    reverse
		        sort { $a->[1] <=> $b->[1] }
			    map { [$_, $results->[$_]{SCORE}] }
			        0 .. $#$results ;
  
  for (@indexes)
	{
	print "$results->[$_]{PATH} [$results->[$_]{SCORE}].\n" ;
	}
	
  $searcher = undef ;
  

=head1 DESCRIPTION

This module implements an incremential text indexer and searcher based on L<Search::Indexer>.

=head1 DOCUMENTATION

Given a list of files, this module will allow you to create an indexed text database that you can later
query for matches. You can also use the B<siim> command line application installed with this module.

=head1 SUBROUTINES/METHODS

=cut

#----------------------------------------------------------------------------------------------------------

sub delete_indexing_databases
{

=head2 delete_indexing_databases($index_directory)

Removes all the index databases from the passed directory

I<Arguments>

=over 2 

=item * $index_directory - location of the index databases

=back

I<Returns> - Nothing

I<Exceptions> - Can't remove index databases.

=cut

my ($index_directory) = @_ ;

croak "Error: Invalid or undefined index directory!\n" unless defined $index_directory ;

unlink $_ or croak "unlink $_ : $!" foreach glob("$index_directory/*.bdb");

return ;

}

#----------------------------------------------------------------------------------------------------------

sub get_file_MD5
{

=head2 get_file_MD5($file)

Returns the MD5 of the I<$file> argument.

I<Arguments>

=over 2 

=item $file - The location of the file to compute an MD5 for

=back

I<Returns> - A string containing the file md5

I<Exceptions> - fails if the file can't be open

=cut

my ($file) = @_ ;
open(FILE, $file) or croak "Error: Can't open '$file' to compute MD5: $!";
binmode(FILE);
return Digest::MD5->new->addfile(*FILE)->hexdigest ;
}

#----------------------------------------------------------------------------------------------------------

1 ;

=head1 BUGS AND LIMITATIONS

None so far.

=head1 AUTHOR

	Nadim ibn hamouda el Khemir
	CPAN ID: NKH
	mailto: nadim@cpan.org

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Search::Indexer::Incremental::MD5

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Search-Indexer-Incremental-MD5>

=item * RT: CPAN's request tracker

Please report any bugs or feature requests to  L <bug-search-indexer-incremental-md5@rt.cpan.org>.

We will be notified, and then you'll automatically be notified of progress on
your bug as we make changes.

=item * Search CPAN

L<http://search.cpan.org/dist/Search-Indexer-Incremental-MD5>

=back

=head1 SEE ALSO

L<Search::Indexer>

L<Search::Indexer::Incremental::MD5::Indexer> and L<Search::Indexer::Incremental::MD5::Searcher>

=cut
