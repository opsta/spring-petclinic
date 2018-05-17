properties([
  gitLabConnection('gitlab-opsta'),
  parameters([
    choice(choices: 'deploy-by-branch\ntagging\ndeploy-production', description: 'Action to do', name: 'ACTION'),
    [$class: 'GitParameterDefinition', branch: '', branchFilter: '.*', defaultValue: '', description: 'Choose tag to deploy (Need to combine with ACTION = deploy-production)', name: 'TAG', quickFilterEnabled: false, selectedValue: 'NONE', sortMode: 'DESCENDING_SMART', tagFilter: 'build-*', type: 'PT_TAG']
  ])
])

def label = "petclinic-${UUID.randomUUID().toString()}"
podTemplate(label: label, cloud: 'kubernetes', containers: [
  // Don't use alpine version. It having problem with forking JVM such as running surefire and junit testing
  containerTemplate(name: 'java', image: 'openjdk:8u171-jdk-stretch', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'docker', image: 'docker', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'helm', image: 'lachlanevenson/k8s-helm', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'git', image: 'paasmule/curl-ssl-git', ttyEnabled: true, command: 'cat')
],
volumes: [
  hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
  hostPathVolume(mountPath: '/tmp', hostPath: '/tmp')
]) {
  node(label) {

    appName = 'petclinic'

    if(params.ACTION == "tagging") {

      stage('Pull UAT image and tag to production image') {
        container('docker') {
          imageTag = "registry.demo.opsta.co.th/${appName}:uat"
          imageTagProd = "registry.demo.opsta.co.th/${appName}:build-${env.BUILD_NUMBER}"
          withCredentials([usernamePassword(credentialsId: 'nexus-credential', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
            sh """
              docker login registry.demo.opsta.co.th -u $NEXUS_USERNAME -p $NEXUS_PASSWORD
              docker pull ${imageTag}
              docker tag ${imageTag} ${imageTagProd}
              docker push ${imageTagProd}
              """
          }
          // Get commit id to tag from docker image
          CODE_VERSION = sh (
            script: "docker run --rm ${imageTagProd} cat VERSION",
            returnStdout: true
          ).trim()
        }
      }

      stage('Tag commit id to version and push code') {
        container('git') {
          sshagent(credentials: ['petclinic-1-git-deploy-key']) {
            checkout scm
            checkout([$class: 'GitSCM',
              branches: [[name: CODE_VERSION ]]
            ])
            sh """
              git tag build-${env.BUILD_NUMBER}
              SSH_AUTH_SOCK=${env.SSH_AUTH_SOCK} GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" git push --tags
              """
          }
        }
      }

    } else if(params.ACTION == "deploy-production") {
      // Deploy to production
      stage('Deploy production') {
        scmVars = checkout scm
        container('helm') {
          withCredentials([file(credentialsId: 'gce-k8s-kubeconfig', variable: 'KUBECONFIG')]) {
            sh """
              mkdir -p ~/.kube/
              cat $KUBECONFIG > ~/.kube/config
              sed -i 's/tag: latest/tag: ${params.TAG}/g' k8s/values-prod.yaml
              sed -i 's/commitId: CHANGE_COMMIT_ID/value: ${scmVars.GIT_COMMIT}/g' k8s/values-prod.yaml
              helm upgrade -i --namespace prod -f k8s/values-prod.yaml --wait petclinic-prod k8s/helm
              """
          }
        }
      }

    } else if(params.ACTION == "deploy-by-branch") {
      switch (env.BRANCH_NAME) {
        case "master":
          imageTag = "registry.demo.opsta.co.th/${appName}:uat"
          break
        case "dev":
          imageTag = "registry.demo.opsta.co.th/${appName}:dev"
          break
      }

      scmVars = checkout scm

      stage('Run Unit Test') {
        container('java') {
          try {
            sh """
            ./mvnw clean test -s maven-settings.xml -e
            """
            // archiveArtifacts "target/*"
            junit "**/target/surefire-reports/*.xml"
            step([
              $class: 'JUnitResultArchiver',
              testResults: "**/target/surefire-reports/*.xml"
            ])
          } catch(err) {
            sh """
            cat target/surefire-reports/*
            """
            throw err
          }
        }
      }

      stage('SonarQube analysis') {
        container('java') {
          withSonarQubeEnv('sonarqube-opsta') {
            sh """
            ./mvnw org.sonarsource.scanner.maven:sonar-maven-plugin:3.2:sonar
            """
          }
        }
      }

      stage('Build Artifact') {
        container('java') {
          sh """
            ./mvnw clean package -Dmaven.test.skip=true -s maven-settings.xml
            """
          nexusArtifactUploader (
            nexusVersion: 'nexus3',
            protocol: 'https',
            nexusUrl: 'nexus.demo.opsta.co.th/repository/maven-releases',
            groupId: 'org.springframework.samples',
            version: "build-${env.BUILD_NUMBER}",
            repository: 'maven-releases',
            credentialsId: 'nexus-credential',
            artifacts: [
              [artifactId: 'petclinic',
              classifier: '',
              file: 'target/spring-petclinic-2.0.0.BUILD-SNAPSHOT.jar',
              type: 'jar']
            ]
          )
        }
      }

      stage('Build image') {
        container('docker') {
          withCredentials([usernamePassword(credentialsId: 'nexus-credential', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
            sh """
              # Clean target directory
              rm -rf target/
              mkdir -p target/
              echo ${scmVars.GIT_COMMIT} > VERSION
              # Need for download from HTTPS
              apk --no-cache add openssl wget
              wget -O target/petclinic-build-${env.BUILD_NUMBER}.jar --user=$NEXUS_USERNAME --password=$NEXUS_PASSWORD https://nexus.demo.opsta.co.th/repository/maven-releases/repository/maven-releases/org/springframework/samples/petclinic/build-${env.BUILD_NUMBER}/petclinic-build-${env.BUILD_NUMBER}.jar
              docker build -t ${imageTag} .
              """
          }
        }
      }

      stage('Push image to registry') {
        container('docker') {
          withCredentials([usernamePassword(credentialsId: 'nexus-credential', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
            sh """
              docker login registry.demo.opsta.co.th -u $NEXUS_USERNAME -p $NEXUS_PASSWORD
              docker push ${imageTag}
              """
          }
        }
      }

      stage("Deploy Application") {
        container('helm') {
          // Put kubeconfig file
          withCredentials([file(credentialsId: 'gce-k8s-kubeconfig', variable: 'KUBECONFIG')]) {
            sh """
              mkdir -p ~/.kube/
              cat $KUBECONFIG > ~/.kube/config
              """
          }
          switch (env.BRANCH_NAME) {
            // Roll out a UAT environment on master branch
            case "master":
              sh """
                sed -i 's/commitId: CHANGE_COMMIT_ID/value: ${scmVars.GIT_COMMIT}/g' k8s/values-uat.yaml
                helm upgrade -i --namespace uat -f k8s/values-uat.yaml --wait petclinic-uat k8s/helm
                """
              break

            // Roll out a dev environment
            case "dev":
              sh """
                sed -i 's/commitId: CHANGE_COMMIT_ID/value: ${scmVars.GIT_COMMIT}/g' k8s/values-dev.yaml
                helm upgrade -i --namespace dev -f k8s/values-dev.yaml --wait petclinic-dev k8s/helm
                """
              break
          }
        }
      }
    }
  }
}
