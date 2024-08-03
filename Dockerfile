# Use an appropriate base image
FROM alpine:latest

# Install necessary packages
RUN apk update && \
    apk add --no-cache cifs-utils rsync dcron nano procps bash tzdata

# Copy the cron job and scripts into the container
COPY /src/backup.sh /usr/local/bin/backup.sh
COPY /src/entry.sh /usr/local/bin/entry.sh
COPY readme.txt /usr/local/bin/readme.txt
COPY config.ini /etc/config.ini

# Assign alias to crond to prevent having to modify scripts
RUN ln -s /usr/sbin/crond /usr/bin/cron

# Set bash as default shell, as scripts written to work under bash
SHELL ["/bin/bash", "-c"]

# Set nano as default editor - once finished testing, wont need
ENV EDITOR=nano

# Give execution rights on the scripts
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entry.sh

# Ensure the cron log file exists
RUN touch /var/log/cron.log

# Set the entry point to run entry.sh and start cron
ENTRYPOINT ["/usr/local/bin/entry.sh"]

