# test

use strict ;
use warnings ;

use Test::Exception ;
use Test::Warn;
use Test::NoWarnings qw(had_no_warnings);

use Test::More 'no_plan';
#use Test::UniqueTestNames ;

use Test::Block qw($Plan);
use Test::Command ;

use Search::Indexer::Incremental::MD5 ;

=for comment

{
local $Plan = {'completion_script' => 3} ;



## testing exit status

my $generate_completion = 'siim --completion_script';

exit_is_num($generate_completion, 1);
stdout_like($generate_completion, qr/^_siim_bash_completion()/smx);

my %tree_structure =
	(
	#~ dir_1 =>
		#~ {
		#~ subdir_1 =>{},
		#~ file_1 =>[],
		#~ file_a => [],
		#~ },
	#~ dir_2 =>
		#~ {
		#~ subdir_2 =>
			#~ {
			#~ file_22 =>[],
			#~ file_2a =>[],
			#~ },
		#~ file_2 =>[],
		#~ file_a =>['12345'],
		#~ file_b =>[],
		#~ },
		
	#~ file_0 => [] ,
	) ;
	
use Directory::Scratch::Structured qw(create_structured_tree) ;
my $temporary_directory = create_structured_tree(%tree_structure) ;

my $source_completion = "siim --completion_script > $temporary_directory/siim ; source $temporary_directory/siim" ;
exit_is_num($source_completion, 0);
	
#~ throws_ok
	#~ {
	#~ }
	#~ qr//, 'failed' ;
}

=cut

__END__
         'i|index_directory=s'   path to the database index
		path that is non writable
		
         'r|remove_files'        remove files from the database
		removing non existing files
		 removing files not in the index

         'delete_database'       deletes the database in the index directory
         'database_information'  shows some database information
	 
         'a|add_files'           add files to the database
		'stopwords_file=s'      path to files containing stopwords
		'maximum_document_size' default is 300 KB
		
		'p|perl_mode'           pre-defined perl stopword list
			test override
	 
		 indexing of non existing file
		 'c|check_index'         check the database and display file state
		 
		 add a file non modified
		 add a file modified
		 
		 add multiple times the same file in the same operation
		 
	 indexing of file that can't be accessed
	 indexing of file that don't exist
	 
	 search queries
		matching
			verbose
			non verbose
			
		non matching
		
