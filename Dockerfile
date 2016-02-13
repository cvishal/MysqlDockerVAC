FROM ubuntu:latest
MAINTAINER Vishal

ENV MYSQL_USER=mysql \
    MYSQL_DATA_DIR=/var/lib/mysql \
    MYSQL_RUN_DIR=/var/run/mysqld \
    MYSQL_LOG_DIR=/var/log/mysql

RUN groupadd --gid 1010 mysql
RUN useradd --uid 1010 --gid 1010 -m --shell /bin/false mysql
#RUN useradd --uid 1010 --gid 1010 --home-dir /nonexistent --shell /bin/false mysql

RUN apt-get update \
 && apt-get install -y mysql-server \
 && rm -rf ${MYSQL_DATA_DIR} \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3306/tcp
ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/usr/bin/mysqld_safe"]
