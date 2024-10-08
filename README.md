A simple utility for backing up configuration or other files and directories to a remote location using CIFS.  Multiple locations, and configurations can be defined, and you can either create a .tar.gz archive of the location, or mirror the directory structure using rsync.  Scheduling is performed using standard cron expressions.  https://crontab.guru/ is useful for generating valid cron expressions.  Ensure that there is no warning about the expression being Non standard, as it will not work.<p>


Docker compose...<br>
```
name: sample-docker-compose
services:
    cifs-backup:
        container_name: cifs-backup
        volumes:
            - /path/to/backup/folder:/src/training:ro
            - /path/to/backup/folder2:/src/rebel-base:ro
            - /path/to/backup/folder3:/src/plans
            - /path/to/config.ini:/etc/config.ini
        restart: unless-stopped
        image: /bilbs84/cifs-backup:latest
        environment:
            - TZ=Australia/Melbourne
        privileged: true
```
<p>

You can define as many folders to backup as you like, and you can name the container folders as you please, as these will all get defined in the configuration file.  I like to mount them as read only to ensure that there is no possibility of messing anything up, but the scripts don't do anything the the mounted directories.

<p>As of version 1.4.0, configuration now uses a yaml file instead of an ini style file.  I'm using the yaml parser, yq.  This change has been made to help prevent errors in the file, or issues with double quotes and unintended whitespaces etc.
    
```
rebel: #Section header, the name of the job being run, the mount point for the remote share, and the default subfolder name when none specified.
  server: 192.168.1.2 # The server IP address of the backup location
  share: Backups # The share name on the server
  user: luke # Username - may sometime in the future add support for non password protected shares
  passwd: skywalker
  source: /src/rebel-base # Location of files to backup, in this case, the location specified in the docker volume mapping
  compress: 0 # 0 uses rsync to create a copy of the folder and file structure of the directory
  schedule: 30 1-23/2 * * * # Valid cron expression for backup schedule
  subfolder: homeassistant # Subfolder on remote share to place backup in

zips:
  server: 192.168.1.2
  share: Backups
  user: luke
  passwd: skywalker
  source: /src/training
  compress: 1
  keep: 3
  exclude:
    - yoda
    - family/lea
    - family/dad
    - "*.sock"
  schedule: 0 * * * *
  subfolder: zips

death-star:
  server: 192.168.1.2
  share: Backups
  user: luke
  passwd: skywalker
  source: /src/plans
  subfolder: configs
  compress: 0
  keep: 3
  exclude: vulnerabilities
  schedule: 0 * * * *
```

The following configuration options are required for each section

- Section header, The header for each section, also used as the subfolder on the share when no subfolderName is specified.
- `server` The IP address of the server for backing up to.
- `share` The share name of the server.
- `user` Username associated with the share.  Currently, I only offer support for password protected shares.
- `passwd` The password for the share user.
- `source` The location of the folder to backup.  Specified in the docker run command, or compose file.
- `compress` Set to 1 to compress the contents of the source folder.
- `subfolder` The subdirectory on the server share that the section will be processed to.  Will default to `[Unit-title]` if blank or not present.
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
- 1.3.0: Migrated project to github.
- 1.3.2: Setup github workflow to build and push image.
- 1.3.3: Correct typos in workflow configuration.
- 1.3.4: Update timeStamp function for logs in backup and entry scripts.
- 1.3.5: Update cron sync function in entry.sh to prevent duplicate cron configuration, and tidy up local declarations for better readability.
- 1.4.0: Switch to .yaml configuration file, rewrite backup and entry scripts to suit, rename backup script to match project title.
