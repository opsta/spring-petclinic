FROM openjdk:8u151-jre-alpine3.7
WORKDIR /usr/src/myapp
COPY target/*.jar VERSION /usr/src/myapp/
# Can not use array because it needed /bin/sh -c
CMD java -jar /usr/src/myapp/*.jar
