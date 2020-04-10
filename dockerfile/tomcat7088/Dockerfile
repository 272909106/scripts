FROM centos:7.2.1511

ENV JAVA_RELEASE jdk1.8.0_171

ENV JAVA_PACK_NAME jdk-8u171-linux-x64

ENV JAVA_HOME /usr/local/$JAVA_RELEASE

ENV PATH $JAVA_HOME/bin:$PATH

ENV LANG en_US.UTF-8

ENV TOMCAT_RELEASE apache-tomcat-7.0.88

ENV CATALINA_HOME /usr/local/$TOMCAT_RELEASE

ENV PATH $CATALINA_HOME/bin:$PATH

COPY $JAVA_PACK_NAME.tar.gz /tmp/

COPY $TOMCAT_RELEASE.tar.gz /tmp/

RUN cd /tmp/ ; \
	tar -xf $JAVA_PACK_NAME.tar.gz -C /usr/local ; \ 
	tar -xf $TOMCAT_RELEASE.tar.gz -C /usr/local ; \ 
	rm *.tar.gz ; \
	yum update ; \
	yum install vim telnet procps net-tools -y

WORKDIR $CATALINA_HOME

EXPOSE 8080

CMD ["catalina.sh", "run"]
