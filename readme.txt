bilbs84/cifs-backup

A simple utility for backing up configuration or other files and directories to a remote location using CIFS.
Multiple locations, and configurations can be defined, and you can either create a .tar.gz archive of the location,
or mirror the directory structure using rsync. Scheduling is performed using standard cron expressions.

https://crontab.guru/⁠ is useful for generating valid cron expressions.
Ensure that there are no warnings about the expression being Non standard, as it will not work.

More information can be found at https://hub.docker.com/r/bilbs84/cifs-backup

CHANGELOG
--------------------------------------------------------------------------------
1.0_rc: Initial release.  Tested, and working, however with some limitations.
1.1: Changed mount point from /src/cifs to /src/<section title> to prevent issues with multiple instances of the
       script trying to use the same mount point.  Can still only run one instance at a time due to filelock
       implementation - to be cahnged in a later release
1.1.1: Changed config.cfg to config.ini to better suit the files formatting.
       Added readme with changelog to container.
1.1.2: Changed the filelock implementation to include the section name to allow multiple instances of the script
         to run at the same time.
1.1.3: Fixed typo in filelock routine.
1.1.4: Added function in entry script to set the system time to match the TZ environmental variable passed in during the
         container creation, and testing log colorization
1.1.5: Corrected typo in logic for timezone sync.
1.1.6: Corrected more typo's, continued colorization of logs, and added better error handling for startup script.
1.1.7: Correct handling of errors for cron syncronization.
1.1.8: Change method for detecting cron file errors
1.2.0: Changed base image to debain:slim to trim the image size.
1.2.5-alpine: Changed base image to alpine, modified scripts to work with alpine as required.
1.2.6-alpine: More work on colorization of logs.
