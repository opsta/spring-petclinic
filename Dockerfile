FROM openjdk:8u171-jre-alpine3.8
WORKDIR /usr/src/myapp
COPY target/*.jar VERSION /usr/src/myapp/
# Can not use array because it needed /bin/sh -c
CMD java -jar /usr/src/myapp/*.jar
