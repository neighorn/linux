#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>			/* For getopt constants. */

#define FIRST_LINE_END 42
char *msMyName;
char msUsage[256];
long mlMaxLine = 4096;

main (int argc, char **argv) {
    
    int iFileNum;
    int iRetCode = 0;
    int iMaxRC = 0;

    int iOpt;
    extern int optind;
    extern char *optarg;

    /* Get my command name, for error messages. */
    if ((msMyName = strrchr(argv[0],'/')) == NULL)
	msMyName=argv[0];
    else
	msMyName++;	

    /* Insert our name into Usage message. */
    sprintf(msUsage, "Usage: %s [-l lengthlimit] inputfile", msMyName);

    /* Process options. */
    while ((iOpt = getopt(argc, argv, "l:")) != EOF)
    {
 	switch (iOpt)
        {
            case 'l':
		mlMaxLine=atol(optarg);
		break;
	    case '?':
		fprintf(stderr,"\n%s\n\n", msUsage);
		exit(1);
	}
    }

    if (argc - optind < 1)
    {
        fprintf(stderr,"%s: Insufficient parameters\n%s\n", msMyName, msUsage);
        exit(1);
    }

    for (iFileNum = optind; iFileNum < argc; iFileNum++)
    {
	iRetCode=CleanFile(argv[iFileNum]);
	if (iRetCode > iMaxRC) iMaxRC = iRetCode;
    }

    exit (iMaxRC);

}
   

int CleanFile (char *sInFile) {
	
    FILE *in, *out;			/* Input and output file pointers. */
    char sOutFile[FILENAME_MAX+1];	/* Name of output file. */
    long lInPosition;			/* Position in our input file. */
    char *sBuffer;			/* Pointer to input buffer. */
    long lBuffSize;			/* Current size of buffer. */
    long lIndex;			/* Index into sBuffer. */
    char cByte;				/* Current byte. */
    int  iFirstLine;			/* First-line flag. */
    int  iSkipping;			/* Skipping until \n found flag */

    if ((in=fopen(sInFile,"r")) == NULL) 
    {
	perror(msMyName);
	return(3);
    }

    sOutFile[0]='\0';
    strcpy(sOutFile, sInFile);
    strcat(sOutFile, ".tmp");
    if ((out=fopen(sOutFile,"w")) == NULL) 
    {
	perror(msMyName);
	fclose(in);
	return(3);
    }

    lBuffSize = 512;
    if ((sBuffer = malloc(lBuffSize)) == NULL)
    {
	perror(msMyName);
	fclose(in);
	fclose(out);
	return(4);
    }

    iFirstLine=TRUE;			/* First line doesn't have a \n */
    iSkipping=FALSE;			/* Not skipping until \n */
    while (! feof(in)) 
    {
	/* Save current position. */
        lInPosition = ftell(in);

	/* Get a buffer's worth. */
	if (fgets(sBuffer, lBuffSize, in) == NULL)
	{
	    /* EOF or I/O error. */
	    if (feof(in)) break;
	    perror(msMyName);
	    fclose(in);
	    fclose(out);
	    remove(sOutFile);
	    return(5);
	}

	/* Make sure we got an entire line. */
	if ((strchr(sBuffer,'\n') == NULL) && \
		(strlen(sBuffer)+1 >= lBuffSize) && \
		(lBuffSize < mlMaxLine))
	{
	    /* No newline.  Buffer is too short.  Reallocate and reread. */
	    lBuffSize += 512;			/* Increase the size by 512. */
	    free(sBuffer);
	    if ((sBuffer = malloc(lBuffSize)) == NULL)
	    {
		/* Couldn't reallocate the buffer. */
		perror(msMyName);
		fclose(in);
		fclose(out);
	        remove(sOutFile);
		return(4);
	    }
	    fseek(in,lInPosition,SEEK_SET);	/* Reposition for reread.    */
	    continue;				/* Recycle through the loop. */
	}

	if (strchr(sBuffer,'\n') == NULL)
	{
	    /* No new-line.  Buffer at max size. */
	    fprintf(out,"<<%s: line too long>>\n",msMyName);
	    iSkipping=TRUE;
	}
	if (iSkipping)
	    continue;
	else
	    iSkipping=FALSE;
	/* Check for first line. */
	if (iFirstLine && (strlen(sBuffer) > FIRST_LINE_END))
	{
	    /* Just print the first line and delete it from the record. */
	    fprintf(out,"%-*.*s\n", FIRST_LINE_END, FIRST_LINE_END, sBuffer);
	    strcpy(sBuffer,sBuffer+FIRST_LINE_END);
	    iFirstLine = FALSE;
	}

	/* Edit the line. */
	lIndex = 0;
	while ((cByte = *(sBuffer+lIndex)) != '\n') 
	{
	    if (cByte == '\b' && lIndex >= 1)
	    {
		/* Backspace found.  Delete it and prior letter. */
		strncpy(sBuffer+lIndex-1, sBuffer+lIndex+1, \
			strlen(sBuffer) - lIndex); 
		lIndex--;
		continue;
	    }
	    else if (cByte == '\r' && *(sBuffer+lIndex+1) != '\n')
	    {
		/* ^M in mid-stream found.  Leave it as is. */
		lIndex++;
		continue;
	    }
	    else if (cByte == '\b' || cByte == '\r')
	    {
		/* Leading backspace or trailing ^M found.  Delete it. */
		strncpy(sBuffer+lIndex, sBuffer+lIndex+1, \
			strlen(sBuffer) - lIndex + 1); 
		continue;
	    }
	    else
	    {
		lIndex++;		/* Ordinary character.  Leave it. */
	    }	
	}
	/* Make sure it's not too long. */
	if (strlen(sBuffer) > mlMaxLine)
	{
	    fprintf(out,"<<%s: line too long>>\n",msMyName);
	}
	else
	{
	    fputs(sBuffer, out);	/* Write the edited record out. */
	}

    }
    fclose(in);
    fclose(out);
    remove(sInFile);			/* Clean up files. */
    rename(sOutFile, sInFile);
    return;
}
