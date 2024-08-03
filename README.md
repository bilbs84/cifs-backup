A simple utility for backing up configuration or other files and directories to a remote location using CIFS.  Multiple locations, and configurations can be defined, and you can either create a .tar.gz archive of the location, or mirror the directory structure using rsync.  Scheduling is performed using standard cron expressions.  https://crontab.guru/ is useful for generating valid cron expressions.  Ensure that there is no warning about the expression being Non standard, as it will not work.<p>


Docker compose...<br>
```
name: sample-docker-compose
services:
    cifs-backup:
        container_name: cifs-backup
        volumes:
            - /path/to/backup/folder:/src/backup1:ro
            - /path/to/backup/folder2:/src/backup2:ro
            - /path/to/config.ini:/etc/config.ini
        restart: unless-stopped
        image: /bilbs84/cifs-backup:latest
        environment:
            - TZ=Australia/Melbourne
        privileged: true
```
<p>

You can define as many folders to backup as you like, and you can name the container folders as you please, as these will all get defined in the configuration file.  I like to mount them as read only to ensure that there is no possibility of messing anything up, but the scripts don't do anything the the mounted directories.

<p>Here is a sample of config.ini
    
```
# Backups configuration
  
[Server]
server=192.168.4.69
share=Backups
user=backup
password=backup
source=/src/backup1/folder/to/backup
compress=0
schedule=* * * * 0

[ZIP-Configs]
server=192.168.4.169
share=configs
user=user
password=secret
source=/src/backup2
compress=1
keep=3
# Excludes - must be relative to the /src/backups-folder location, for example - /src/backups2/folder-to-exclude
exclude=folder-to-exlude
exclude=folder-to-exclude/subfolder
# Can also specify file types, or specific files to exclude
exclude=*.sock
schedule=0 * 3 * *

# Backed up files will be stored in the share folder, under a subfolder of the section name
[ZIP-Server]
server=192.168.4.69
share=Backups
user=backup
password=backup
source=/src/backup1/folder/to/backup
compress=1
keep=2
schedule=30 * 3 * *
```

The following configuration options are required for each section

- `[Unit-title]` The header for each section, also used as the subfolder on the share
- `server` The IP address of the server for backing up to.
- `share` The share name of the server.
- `user` Username associated with the share.  Currently, I only offer support for password protected shares.
- `password` The password for the share user.
- `source` The location of the folder to backup.  Specified in the docker run command, or compose file.
- `compress` Set to 1 to compress the contents of the source folder.
- `keep` How many days to keep compressed archives, any backups older than this will be removed.
- `exclude` And exclusions for the backup (See example above)
- `schedule` A cron expression for the schedule that the backups will run.
<br>
More information can be found at https://hub.docker.com/r/bilbs84/cifs-backup

CHANGELOG
--------------------------------------------------------------------------------
- 1.0_rc: Initial release.  Tested, and working, however with some limitations.
- 1.1: Changed mount point from /src/cifs to /src/<section title> to prevent issues with multiple instances of the
       script trying to use the same mount point.  Can still only run one instance at a time due to filelock
       implementation - to be cahnged in a later release
- 1.1.1: Changed config.cfg to config.ini to better suit the files formatting.
       Added readme with changelog to container.
- 1.1.2: Changed the filelock implementation to include the section name to allow multiple instances of the script
         to run at the same time.
- 1.1.3: Fixed typo in filelock routine.
- 1.1.4: Added function in entry script to set the system time to match the TZ environmental variable passed in during the
         container creation, and testing log colorization
- 1.1.5: Corrected typo in logic for timezone sync.
- 1.1.6: Corrected more typo's, continued colorization of logs, and added better error handling for startup script.
- 1.1.7: Correct handling of errors for cron syncronization.
- 1.1.8: Change method for detecting cron file errors
- 1.2.0: Changed base image to debain:slim to trim the image size.
- 1.2.5-alpine: Changed base image to alpine, modified scripts to work with alpine as required.
- 1.2.6-alpine: More work on colorization of logs.
