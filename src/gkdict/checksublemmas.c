#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <gkstring.h>

#include "../morphlib/nextkey.proto.h"

/*
 * Checks the :sl: lines of Latin stem sources before they are indexed. A :sl: names the word that the stem lines
 * after it belong to, until the next :sl: or :le:.
 *
 *   checksublemmas file ...      files whose :sl: lines the noun indexer reads
 *   checksublemmas -n file ...   files that must have none
 *
 * Prints each refused line as file:line: reason, and exits 1 if there is any.
 */

#define LINESIZE (BUFSIZ * 5)

static int refusals = 0;

static void refuse(char *file, int lineno, char *reason)
{
	fprintf(stderr,"%s:%d: %s\n", file, lineno, reason);
	refusals++;
}

static void check_sublemma(char *file, int lineno, char *lemma, char *sublemma)
{
	char toolong[64];

	sublemma[strcspn(sublemma,"\n")] = 0;
	snprintf(toolong,sizeof toolong,":sl: longer than %d bytes", MAXWORDSIZE - 1);

	if( ! lemma[0] )
		refuse(file,lineno,":sl: before the file's first :le:");
	else if( ! sublemma[0] )
		refuse(file,lineno,"empty :sl:");
	else if( sublemma[strcspn(sublemma," \t:")] )
		refuse(file,lineno,":sl: with a space or a colon");
	else if( strlen(sublemma) >= MAXWORDSIZE )
		refuse(file,lineno,toolong);
	else if( ! strcmp(sublemma,lemma) )
		refuse(file,lineno,":sl: equal to its :le:");
}

static void check_file(char *file, int takes_sublemmas)
{
	FILE * f = fopen(file,"r");
	char line[LINESIZE];
	char lemma[LINESIZE];
	int lineno = 0;
	int under_sublemma = 0;
	int has_base = 0;

	lemma[0] = 0;
	while(fgets(line,(int)sizeof line,f)) {
		lineno++;
		if( ! strncmp(line,":le:",4) ) {
			nextkey(line+4,lemma);
			under_sublemma = has_base = 0;
		} else if( ! strncmp(line,":sl:",4) ) {
			if( takes_sublemmas )
				check_sublemma(file,lineno,lemma,line+4);
			else
				refuse(file,lineno,":sl: in a file that takes none");
			under_sublemma = 1;
			has_base = 0;
		} else if( ! strncmp(line,":aj:",4) || ! strncmp(line,":no:",4) ) {
			has_base = 1;
		} else if( line[0] == '@' && under_sublemma && ! has_base ) {
			refuse(file,lineno,"@ line under a :sl: with no :no: or :aj: line of its own above it");
		}
	}
	fclose(f);
}

int main(int argc, char *argv[])
{
	int takes_sublemmas = 1;

	if( getopt(argc,argv,"n") == 'n' )
		takes_sublemmas = 0;
	for(;optind<argc;optind++)
		check_file(argv[optind],takes_sublemmas);
	return( refusals ? 1 : 0 );
}
