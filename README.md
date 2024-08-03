A simple utility for backing up configuration or other files and directories to a remote location using CIFS.  Multiple locations, and configurations can be defined, and you can either create a .tar.gz archive of the location, or mirror the directory structure using rsync.  Scheduling is performed using standard cron expressions.  https://crontab.guru/ is useful for generating valid cron expressions.  Ensure that there is no warning about the expression being Non standard, as it will not work.<p>


Docker compose...<br>
<pre>name: sample-docker-compose
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
</pre><p>

You can define as many folders to backup as you like, and you can name the container folders as you please, as these will all get defined in the configuration file.  I like to mount them as read only to ensure that there is no possibility of messing anything up, but the scripts don't do anything the the mounted directories.

<p>Here is a sample of config.ini
<pre class="MuiBox-root css-kx4s65" tabindex="0"><code class="MuiTypography-root MuiTypography-code-block language-ini css-7zauz8 hljs" data-highlighted="no">
# Backups configuration
  
[Server]
server=192.168.4.69
share=Backups
user=backup
password=backup
source=/src/backup1/folder/to/backup
compress=0
schedule=* * * * 0
<span></span>
[ZIP-Configs]
server=192.168.4.169
share=configs
user=user
password=secret
source=/src/backup2
compress=1
keep=3
<span># Excludes - must be relative to the /src/backups-folder location, for example - /src/backups2/folder-to-exclude</span>
exclude=folder-to-exlude
exclude=folder-to-exclude/subfolder
<span># Can also specify file types, or specific files to exclude</span>
exclude=*.sock
schedule=0 * 3 * *
<span></span>
<span># Backed up files will be stored in the share folder, under a subfolder of the section name</span>
[ZIP-Server]
server=192.168.4.69
share=Backups
user=backup
password=backup
source=/src/backup1/folder/to/backup
compress=1
keep=2
schedule=30 * 3 * *
</code></pre>

<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">schedule</code></pre> is not required, and can be omitted from any configuration section.  The rest of the options are required.

<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">server</code></pre> The IP address of the server for backing up to.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">share</code></pre> The share name of the server.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">user</code></pre> Username associated with the share.  Currently, I only offer support for password protected shares.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">password</code></pre> The password for the share user.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">source</code></pre> The location of the folder to backup.  Specified in the docker run command, or compose file.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">compress</code></pre> Set to 1 to compress the contents of the source folder.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">keep</code></pre> How many days to keep compressed archives, any backups older than this will be removed.
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">exclude</code></pre> And exclusions for the backup (See example above)
<p class="MuiTypography-root MuiTypography-body1 css-10elszr"><code class="MuiTypography-root MuiTypography-inline-code css-ftdxc8">schedule</code></pre> A cron expression for the schedule that the backups will run.
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
