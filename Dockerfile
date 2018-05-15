# Do build
FROM openjdk:8u151-jdk-alpine3.7 as builder
ARG MVN_BUILD_OPTS=
WORKDIR /build
COPY . /build
RUN ./mvnw package -Dmaven.test.skip=true ${MVN_BUILD_OPTS}

# Copy Fat Jar
FROM openjdk:8u151-jre-alpine3.7
COPY --from=builder /build/target/*.jar /usr/src/myapp/
# Can not use array because it needed /bin/sh -c
CMD java -jar /usr/src/myapp/*.jar
