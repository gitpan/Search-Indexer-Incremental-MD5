
package Search::Indexer::Incremental::MD5::Indexer ;

use strict;
use warnings ;
use Carp qw(carp croak confess) ;

BEGIN 
{
use Sub::Exporter -setup => 
	{
	exports => [ qw(add_files remove_files check_index) ],
	groups  => 
		{
		all  => [ qw() ],
		}
	};
	
use vars qw ($VERSION);
$VERSION     = '0.01';
}

#----------------------------------------------------------------------------------------------------------

use List::Util      qw/max/;
use Time::HiRes     qw/time/;
use Search::Indexer 0.75;
use BerkeleyDB;
use File::Slurp ;
use English qw( -no_match_vars ) ;
use Readonly ;


=head1 NAME

Search::Indexer::Incremental::MD5::Indexer - Incrementaly index your files

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
  

=head1 DESCRIPTION

This module implements an incremential text indexer and searcher based on L<Search::Indexer>.

=head1 DOCUMENTATION

Given a list of files, this module will allow you to create an indexed text database that you can later
query for matches. You can also use the B<siim> command line application installed with this module.

=head1 SUBROUTINES/METHODS

=cut

#----------------------------------------------------------------------------------------------------------

sub new
{

=head2 new( %named_arguments)

Create a Search::Indexer::Incremental::MD5::Indexer object.  

  my $indexer = new Search::Indexer::Incremental::MD5::Indexer(%named_arguments) ;

I<Arguments> - %named_arguments

=over 2 

=item %named_arguments - 

=back

I<Returns> - A B<Search::Indexer::Incremental::MD5::Indexer> object

I<Exceptions> - 

=over 2 

=item * Incomplete argument list

=item * Error creating index directory

=item * Error creating index metadata database

=item * Error creating a Search::Indexer object

=back

=cut

my ($invocant, %arguments) = @_ ;

my $class = ref($invocant) || $invocant ;
confess 'Invalid constructor call!' unless defined $class ;

my $index_directory = $arguments{INDEX_DIRECTORY} or croak "Error: index directory missing" ;
-d $index_directory or mkdir $index_directory or croak "Error: mkdir $index_directory: $!";

Readonly my $ID_TO_METADATA_FILE => 'id_to_docs_metatdata.bdb' ;

# use id_to_docs_metatdata.bdb, to store a lookup from the uniq id 
# to the document metadata {$doc_id => "$md5\t$path"}
tie my %id_to_metatdata, 'BerkeleyDB::Hash', 
	-Filename => "$index_directory/$ID_TO_METADATA_FILE", 
	-Flags    => DB_CREATE
		or croak "Error: opening '$index_directory/$ID_TO_METADATA_FILE': $^E $BerkeleyDB::Error";

# build a path  to document metadata lookup
my %path_to_metadata ;

while (my ($id, $document_metadata) = each %id_to_metatdata) 
	{
	my ($md5, $path) = split /\t/, $document_metadata ; #todo: use substr
	
	$path_to_metadata{$path} = {id => $id, MD5 => $md5};
	}

return 
	bless 
		{
		INDEXER => new Search::Indexer
					(
					dir       => $arguments{INDEX_DIRECTORY} || '.',
					writeMode => 1,
					positions => $arguments{USE_POSITIONS},
					wregex    => $arguments{WORD_REGEX},
					stopwords => $arguments{STOP_WORDS} || [],
					) ,

		INDEXED_FILES => {},
		ID_TO_METATDATA => \%id_to_metatdata,
		MAX_DOC_ID => max(keys %id_to_metatdata),
		PATH_TO_METADATA => \%path_to_metadata,
		USE_POSITIONS => $arguments{USE_POSITIONS} , 
		INDEX_DIRECTORY => $arguments{INDEX_DIRECTORY}, 
		}, $class ;
}

#----------------------------------------------------------------------------------------------------------

sub add_files
{

=head2 add_files(%named_arguments)

Adds the contents of the files passed as arguments to the index database. Files already indexed are checked and
re-indexed only if their content has changed

I<Arguments> %named_arguments

=over 2 

=item FILES  - Array reference - a list of files to add to the index

=item DONE_ONE_FILE_CALLBACK - sub reference - called everytime a file is handled

=over 2 

=item $file_name -  the name of the file re-indexed

=item $file_info -  Hash reference

=over 2 

=item * STATE - Boolean -  

=over 2 

=item 0 - up to date, no re-indexing necessary

=item 1 - file content changed since last index, re-indexed

=back

=item * TIME - Float -  re_indexing time

=back

=back

=back

I<Returns> - Hash reference keyed on the file name

=over 2 

=item * STATE - Boolean -  

=over 2 

=item 0 - up to date, no re-indexing necessary

=item 1 - file content changed since last index, re-indexed

=item 2 - new file

=back

=item * TIME - Float -  re-indexing time

=back

I<Exceptions>

=cut

my ($self, %arguments) = @_;

my $files = $arguments{FILES} ;
my $callback =  $arguments{DONE_ONE_FILE_CALLBACK} ;

my %file_information ;

FILE:
foreach my $file (grep {-f } @{$files}) # index files only
	{
	next FILE if ($self->{INDEXED_FILES}{$file}++) ;
	
	my $t0 = time;
	my $file_md5 = Search::Indexer::Incremental::MD5::get_file_MD5($file) ;
	
	if ($file_md5 eq ($self->{PATH_TO_METADATA}{$file}{MD5} || 'no_md5_for_the_file')) 
		{
		$file_information{$file} = {STATE => 0, TIME => (time - $t0)} ;
		$callback->($file, $file_information{$file}) if $callback ;
		
		next FILE ;
		}

	my $old_id = $self->{PATH_TO_METADATA}{$file}{id};
	my $new_id = $old_id || ++$self->{MAX_DOC_ID};
	
	my $file_contents = read_file($file) ;
	my $state = 2 ; # new file
	
	if ($old_id)
		{
		$state = 1 ; # re-index file
		
		if($self->{USE_POSITIONS})
			{
			$self->{INDEXER}->remove($old_id)   ;
			}
		else
			{
			$self->{INDEXER}->remove($old_id, $file_contents)   ;
			}
		}
		
	$self->{INDEXER}->add($new_id, $file_contents);
	
	$file_information{$file} = {STATE => $state, TIME => (time - $t0)} ;

	$self->{ID_TO_METATDATA}{$new_id} = "$file_md5\t$file" ;
	$callback->($file, $file_information{$file}) if $callback ;
	}
	
return \%file_information ;
}

#----------------------------------------------------------------------------------------------------------

sub remove_files
{

=head2 remove_files(%named_arguments)

removes the contents of the files passed as arguments to the index database.

I<Arguments> %named_arguments

=over 2 

=item FILES  - Array reference - a list of files to remove from to the index

=item DONE_ONE_FILE_CALLBACK - sub reference - called everytime a file is handled

=over 2 

=item $file_name -  the name of the file removed

=item $file_info -  Hash reference

=over 2 

=item * STATE - Boolean -  

=over 2 

=item 0 - file not found

=item 1 - file found and removed

=back

=item * TIME - Float -  removal time

=back

=back

=back

I<Returns> - Hash reference keyed on the file name

=over 2 

=item * STATE - Boolean -  

=over 2 

=item 0 - file found and removed

=item 1 - file not found

=back

=item * TIME - Float -  re-indexing time

=back

I<Exceptions>

=cut

my ($self, %arguments) = @_;

my $files = $arguments{FILES} ;
my $callback =  $arguments{DONE_ONE_FILE_CALLBACK} ;

my %file_information ;

FILE:
foreach my $file (grep {-f } @{$files}) # index files only
	{
	next FILE if ($self->{INDEXED_FILES}{$file}++) ;
	
	my $t0 = time;

	my $old_id = $self->{PATH_TO_METADATA}{$file}{id};
	
	my $state = 1 ; # not found

	if ($old_id)
		{
		$state = 0 ; # found and removed
		
		delete $self->{ID_TO_METATDATA}{$old_id} ;
		
		if($self->{USE_POSITIONS})
			{
			$self->{INDEXER}->remove($old_id)   ;
			}
		else
			{
			my $file_contents = '' ;
			$file_contents = read_file($file) if -e $file ;
			
			$self->{INDEXER}->remove($old_id, $file_contents)   ;
			}
		}
		
	$file_information{$file} = {STATE => $state, TIME => (time - $t0)} ;
	$callback->($file, $file_information{$file}) if $callback ;
	}
	
return \%file_information ;
}

#----------------------------------------------------------------------------------------------------------

sub check_indexed_files
{

=head2 check_indexed_files(%named_arguments)

Checks the index database contents.

I<Arguments> %named_arguments

=over 2 

=item DONE_ONE_FILE_CALLBACK - sub reference - called everytime a file is handled

=over 2 

=item $file_name -  the name of the file checkied

=item $file_info -  Hash reference

=over 2 

=item * STATE - Boolean -  

=over 2 

=item 0 - file found and identical

=item 1 - file found, content is different (needs re-indexing)

=item 2 - file not found

=back

=item * TIME - Float -  check time

=back

=back

=back

I<Returns> - Hash reference keyed on the file name

=over 2 

=item * STATE - Boolean -  

=over 2 

=item 0 - file found and identical

=item 1 - file found, content is different (needs re-indexing)

=item 2 - file not found

=back

=item * TIME - Float -  check time

=back

I<Exceptions>

=cut

my ($self, %arguments) = @_;

my $callback =  $arguments{DONE_ONE_FILE_CALLBACK} ;

my %file_information ;

for my $file (keys %{$self->{PATH_TO_METADATA}})
	{
	my $t0 = time;
	my $state = 2 ;

	if(-e $file)
		{
		$state = 1 ;
		
		my $file_md5 = Search::Indexer::Incremental::MD5::get_file_MD5($file) ;
		
		if($self->{PATH_TO_METADATA}{$file}{MD5} eq $file_md5)
			{
			$state = 0 ;
			}
		}
		
	$file_information{$file} = {STATE => $state, TIME => (time - $t0)} ;
	$callback->($file, $file_information{$file}) if $callback ;
	}
	
return \%file_information ;
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

=cut
