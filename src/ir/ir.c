/*      ir        -       input router

        route messages from stdin to a variety of targets

        ir [-hoelcyp] [-f file] [-a file] [-t tag] [-P priority] [-F facility]

        Options:
		-h		help
                -o       	stdout
                -e       	stderr
                -l       	syslog
                -c       	/dev/console
                -y       	/dev/tty
		-f file		Copy output to file.
		-a file		Append output to file.
                -p		include syslog Process ID
                -t tag		syslog message tag
		-F facility	syslog message facility
                -P priority	syslog message priority

	Note: this code correctly handles logging messages containing
              percent signs to the syslog, which /bin/logger does not.

History:
	1.0 Initial release

*/

#include <stdio.h>
#include <syslog.h>
#include <limits.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#define CHECKALLOC 						\
	if (NextTargetFile > MaxTargetFile) { 			\
		MaxTargetFile+=10;				\
		TargetFiles=realloc(TargetFiles,		\
			(MaxTargetFile+1)*sizeof(FILE *));	\
	}

struct table{
    int Number;
    char *ShortName;
    char *LongName;
};

struct table PriorityTable[] = {
    LOG_EMERG,	"EMERGENCY",	"LOG_EMERG",
    LOG_ALERT,	"ALERT",	"LOG_ALERT",
    LOG_CRIT,	"CRITICAL", 	"LOG_CRIT",
    LOG_ERR,	"ERROR",	"LOG_ERR",
    LOG_WARNING,"WARNING",	"LOG_WARNING",
    LOG_NOTICE,	"NOTICE",	"LOG_NOTICE", 
    LOG_INFO,	"INFO",		"LOG_INFO",
    LOG_DEBUG,	"DEBUG",	"LOG_DEBUG"
};
struct table FacilityTable[] = {
    LOG_KERN,	"KERNEL",	"LOG_KERN",
    LOG_USER,	"USER",		"LOG_USER",
    LOG_MAIL,	"MAIL",		"LOG_MAIL",
    LOG_DAEMON,	"DAEMON",	"LOG_DAEMON",
    LOG_AUTH,	"AUTH",		"LOG_AUTH",
    LOG_LPR,	"LPR",		"LOG_LPR",
    LOG_NEWS,	"NEWS",		"LOG_NEWS",
    LOG_UUCP,	"UUCP",		"LOG_UUCP",
    LOG_LOCAL0,	"LOCAL0",	"LOG_LOCAL0",
    LOG_LOCAL1,	"LOCAL1",	"LOG_LOCAL1",
    LOG_LOCAL2,	"LOCAL2",	"LOG_LOCAL2",
    LOG_LOCAL3,	"LOCAL3",	"LOG_LOCAL3",
    LOG_LOCAL4,	"LOCAL4",	"LOG_LOCAL4",
    LOG_LOCAL5,	"LOCAL5",	"LOG_LOCAL5",
    LOG_LOCAL6,	"LOCAL6",	"LOG_LOCAL6",
    LOG_LOCAL7,	"LOCAL7",	"LOG_LOCAL7"
};

#define PTSIZE sizeof(PriorityTable) / sizeof(PriorityTable[0])
#define FTSIZE sizeof(FacilityTable) / sizeof(FacilityTable[0])

char *msMyName;
char msUsage[256];

main (int argc, char **argv) {

    int iOpt;
    extern int optind;
    extern char *optarg;
 
    char Message[PIPE_BUF];	/* Message read and written. */
    char *SysLogTag;            /* Syslog tag. */
    int  SysLogPriority;        /* Syslog priority. */
    int  SysLogFacility;	/* Syslog facility. */
    int  SysLogFlags;           /* Syslog flags. */
    FILE **TargetFiles;         /* Output target files. */
    int  NextTargetFile;        /* Index into TargetFiles array. */
    int  TargetIndex;        	/* Index into TargetFiles array. */
    int  MaxTargetFile;         /* Maximum index for TargetFiles. */
    int  UseSysLog;		/* Booleen flag - write to syslog? */

    /* Get my command name, for error messages. */
    if ((msMyName = strrchr(argv[0],'/')) == NULL)
        msMyName=argv[0];
    else
        msMyName++;
       
    /* Insert our name into Usage message. */
    sprintf(msUsage, "\n\n\tUsage: %s [-oelycp] [-f file] [-a file] [-t tag] [-P priority] [-F facility]\n", msMyName);

    /* Set defaults */
    SysLogTag="\0";
    SysLogPriority=LOG_INFO;
    SysLogFacility=LOG_USER;
    SysLogFlags=LOG_CONS+LOG_NOWAIT;
    UseSysLog=0;			/* Don't use syslog. */

    /* Allocate space for file pointers. */
    TargetFiles = malloc(10*sizeof(FILE *));
    NextTargetFile = 0;
    MaxTargetFile = 9;

    /* Process options. */
    while ((iOpt = getopt(argc, argv, "hoelcypf:a:t:P:F:")) != EOF)
    {
        switch (iOpt)
        {
	    case 'h':				/* Help */
		HelpMessage();
		exit(1);
	    case 'o':				/* Stdout */	
		CHECKALLOC
                TargetFiles[NextTargetFile]=stdout;
		NextTargetFile++;
                break;
	    case 'e':				/* Stderr */
		CHECKALLOC
                TargetFiles[NextTargetFile]=stderr;
		NextTargetFile++;
                break;
            case 'f':				/* Write to file. */
		CHECKALLOC
                TargetFiles[NextTargetFile]=fopen(optarg,"w");
                if (TargetFiles[NextTargetFile] == NULL) 
			perror(msMyName);
		else
			NextTargetFile++;
                break;
            case 'a':				/* Append to file. */
		CHECKALLOC
                TargetFiles[NextTargetFile]=fopen(optarg,"a");
                if (TargetFiles[NextTargetFile] == NULL) 
			perror(msMyName);
		else
			NextTargetFile++;
                break;
            case 'y':				/* Write to TTY. */
		CHECKALLOC
                TargetFiles[NextTargetFile]=fopen("/dev/tty","w");
                if (TargetFiles[NextTargetFile] == NULL) 
			perror(msMyName);
		else
			NextTargetFile++;
                break;
            case 'c':				/* Write to console. */
		CHECKALLOC
                TargetFiles[NextTargetFile]=fopen("/dev/console","w");
                if (TargetFiles[NextTargetFile] == NULL) 
			perror(msMyName);
		else
			NextTargetFile++;
                break;
	    case 'l':
		UseSysLog=1;
		break;
            case 't':
		UseSysLog=1;
                SysLogTag=optarg;
                break;
            case 'P':
		UseSysLog=1;
                SysLogPriority=SearchTable(PriorityTable, PTSIZE, optarg);
                if (SysLogPriority == -1)
		{
		    fprintf(stderr,"%s invalid priority: %s\n",
			msMyName, optarg);
		    exit(2);		/* Invalid priority. */
		}
		if (SysLogPriority < LOG_ERR && getuid() != 0 && geteuid() != 0) 
		{
		    fprintf(stderr,"%s: Must be root to use this priority.\n",
			msMyName);
		    exit(2);
		}
                break;
            case 'F':
		UseSysLog=1;
                SysLogFacility=SearchTable(FacilityTable, FTSIZE, optarg);
                if (SysLogFacility == -1) 
		{
		    fprintf(stderr,"%s invalid facility: %s\n", msMyName, 
			optarg);
		    exit(2);		/* Invalid priority. */
		}
		if (SysLogFacility != LOG_USER && getuid() != 0 && geteuid() != 0) 
		{
		    fprintf(stderr,"%s: Must be root to use this facility code.\n",msMyName);
		    exit(2);
		}
                break;
            case 'p':
		UseSysLog=1;
                SysLogFlags |= LOG_PID;
                break;
            case '?':
                fprintf(stderr,"\n%s\n\n", msUsage);
                exit(1);
        }
    }

    if (argc - optind > 0 )
    {
        fprintf(stderr,"%s: Incorrect parameters\n%s\n", msMyName, msUsage);
        exit(1);
    }

    MaxTargetFile=NextTargetFile - 1;

    if (UseSysLog) {
	openlog(SysLogTag, SysLogFlags, SysLogFacility);
    }

    /* Get the message. */
    while (fgets(Message, sizeof(Message), stdin)) 
    {

	/* Write it to the syslog? */
	if (UseSysLog) 
	    syslog(SysLogPriority,"%s",Message);/* Yes.  Write to syslog. */

	/* Write it to any other targets they asked for. */
	for (TargetIndex=0;TargetIndex<=MaxTargetFile;TargetIndex++)
	{
	    /* Only write to files that we haven't ready received errors on. */
	    if (TargetFiles[TargetIndex] != NULL)
	    {
		if (fputs(Message, TargetFiles[TargetIndex]) == EOF)
		{
			/* We got an error.  Report it and skip it next time. */
			perror(msMyName);
			TargetFiles[TargetIndex]=NULL;
		}
	    }
	}
    }

    /* Close files. */
    for (TargetIndex=0;TargetIndex<=MaxTargetFile;TargetIndex++)
    {
	fclose(TargetFiles[TargetIndex]);
    }
    if (UseSysLog) {
	closelog();
    }

    /* Release memory */
    free(TargetFiles);
}


int SearchTable(struct table Table[], int TableEntries, char *OptArg)
{

    int TableIndex;
    int NumericOptArg;

    if (isdigit(*OptArg)) 
	NumericOptArg=atoi(OptArg);
    else 
 	NumericOptArg=-1;

    for (TableIndex=0;TableIndex < TableEntries;TableIndex++)
    {
	if (NumericOptArg == Table[TableIndex].Number) 
		return NumericOptArg;
	if (strcmp(OptArg,Table[TableIndex].ShortName) == 0)
		return Table[TableIndex].Number;
	if (strcmp(OptArg,Table[TableIndex].LongName) == 0) 
		return Table[TableIndex].Number;
    }

    return -1;
}

HelpMessage()
{

    int TableIndex;

    printf( \
"%s copies standard input to zero or more output destinations. Destinations\n\
are specified on the command line using command line flags as follows:\n\
                -o       	stdout\n\
                -e              stderr\n\
                -l              syslog\n\
                -c       	/dev/console\n\
                -y              /dev/tty\n\
                -f file     	Copy output to file.\n\
                -a file	        Append output to file.\n\
                -p              include Process ID in syslog\n\
                -t tag	        syslog message tag\n\
                -F facility     syslog message facility\n\
                -P priority     syslog message priority\n\
The -f and -a flags may be repeated to specify multiple files.\n\n\
Facilities may be specified with the -F flag as a numeric value, or as one\n\
of two keywords.  Valid facilities are:\n",msMyName);
    for (TableIndex=0; TableIndex < FTSIZE; TableIndex++)
	printf("\t%.4d\t%-12.12s\t%-12.12s\n", FacilityTable[TableIndex].Number,
		FacilityTable[TableIndex].ShortName,
		FacilityTable[TableIndex].LongName);

    printf( \
"\n\nPriorities may be specified with the -P flag as a numeric value, or as\n\
one of two keywords.  Valid priorities are:\n");
    for (TableIndex=0; TableIndex < PTSIZE; TableIndex++)
	printf("\t%.4d\t%-12.12s\t%-12.12s\n", PriorityTable[TableIndex].Number,
		PriorityTable[TableIndex].ShortName,
		PriorityTable[TableIndex].LongName);

}
