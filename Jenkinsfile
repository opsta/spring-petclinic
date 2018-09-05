properties([
  gitLabConnection('gitlab-opsta'),
  parameters([
    choice(choices: 'deploy-by-branch\ntagging\ndeploy-production', description: 'Action to do', name: 'ACTION'),
    [$class: 'GitParameterDefinition', branch: '', branchFilter: '.*', defaultValue: '', description: 'Choose tag to deploy (Need to combine with ACTION = deploy-production)', name: 'TAG', quickFilterEnabled: false, selectedValue: 'NONE', sortMode: 'DESCENDING_SMART', tagFilter: 'build-*', type: 'PT_TAG']
  ])
])

def label = "petclinic"
podTemplate(label: label, cloud: 'kubernetes', idleMinutes: 60, containers: [
  // Don't use alpine version. It having problem with forking JVM such as running surefire and junit testing
  containerTemplate(name: 'java', image: 'openjdk:8u181-jdk-stretch', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'docker', image: 'docker:18.06.1-ce', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'helm', image: 'lachlanevenson/k8s-helm:v2.10.0', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'git', image: 'paasmule/curl-ssl-git:latest', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'jmeter', image: 'opsta/jmeter:latest', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'robot', image: 'ppodgorsek/robot-framework:3.2.0', ttyEnabled: true, command: 'cat')
],
volumes: [
  hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
  hostPathVolume(mountPath: '/root/.m2', hostPath: '/tmp/jenkins/.m2'),
  hostPathVolume(mountPath: '/home/jenkins/dependency-check-data', hostPath: '/tmp/jenkins/dependency-check-data')
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
          sshagent(credentials: ['petclinic-git-deploy-key']) {
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
              sed -i 's/commitId: CHANGE_COMMIT_ID/commitId: ${scmVars.GIT_COMMIT}/g' k8s/values-prod.yaml
              helm upgrade -i --namespace prod -f k8s/values-prod.yaml --wait petclinic-prod k8s/helm
              """
          }
        }
      }

      stage("Run User Acceptance Test") {
        container('robot') {
          sh """
          sleep 30s
          sed -i 's!/opt/robotframework/reports!target/robot/reports!g' /opt/robotframework/bin/run-tests-in-virtual-screen.sh
          sed -i 's!/opt/robotframework/tests!src/test/robotframework!g' /opt/robotframework/bin/run-tests-in-virtual-screen.sh
          sed -i 's!localhost!http://petclinic.demo.opsta.co.th!g' src/test/robotframework/test.robot
          export BROWSER=chrome
          run-tests-in-virtual-screen.sh
          """
          step([
            $class: 'RobotPublisher',
            disableArchiveOutput: false,
            logFileName: 'target/robot/reports/log.html',
            otherFiles: '',
            outputFileName: 'target/robot/reports/output.xml',
            outputPath: '.',
            passThreshold: 100,
            reportFileName: 'target/robot/reports/report.html',
            unstableThreshold: 0
          ])
        }
      }

    } else if(params.ACTION == "deploy-by-branch") {
      switch (env.BRANCH_NAME) {
        case "master":
          imageTag = "registry.demo.opsta.co.th/${appName}:uat"
          subDomain = "uat"
          break
        case "dev":
          imageTag = "registry.demo.opsta.co.th/${appName}:dev"
          subDomain = "dev"
          break
        default:
          sh """
          exit 1
          """
          break
      }

      scmVars = checkout scm

      stage('Run Unit Test') {
        container('java') {
          try {
            sh """
            ./mvnw clean test -s maven-settings.xml -e
            """
            junit "**/target/surefire-reports/*.xml"
            step([
              $class: 'JUnitResultArchiver',
              testResults: "**/target/surefire-reports/*.xml"
            ])
          } catch(err) {
            sh """
            cat target/surefire-reports/*.dump | true
            """
            junit "**/target/surefire-reports/*.xml"
            step([
              $class: 'JUnitResultArchiver',
              testResults: "**/target/surefire-reports/*.xml"
            ])
            throw err
          }
        }
      }

      stage('Run OWASP Dependency Check') {
        container('java') {
          try {
            dependencyCheckAnalyzer(
              datadir: '/home/jenkins/dependency-check-data',
              hintsFile: '',
              includeCsvReports: true,
              includeHtmlReports: true,
              includeJsonReports: true,
              includeVulnReports: true,
              isAutoupdateDisabled: false,
              outdir: '',
              scanpath: '',
              skipOnScmChange: false,
              skipOnUpstreamChange: false,
              suppressionFile: '',
              zipExtensions: ''
            )
          
            dependencyCheckPublisher(
              canComputeNew: false,
              defaultEncoding: '',
              healthy: '',
              pattern: '',
              unHealthy: '',
              failedTotalHigh: '1'
            )
          } catch (Exception e) {
            echo "Result = " + owasp_output
            echo "Result error = " + e.toString()
            def owasp_output = input(message: 'Fail to scan dependency', ok: 'Continue')
          }

        }
      }

      stage('SonarQube analysis') {
        container('java') {
          withSonarQubeEnv('sonarqube-opsta') {
            sh """
            ./mvnw org.sonarsource.scanner.maven:sonar-maven-plugin:3.2:sonar -s maven-settings.xml -e
            """
          }
        }
      }

      stage("Quality Gate"){
        timeout(time: 1, unit: 'HOURS') { // Just in case something goes wrong, pipeline will be killed after a timeout
          def qg = waitForQualityGate() // Reuse taskId previously collected by withSonarQubeEnv
          if (qg.status != 'OK') {
            error "Pipeline aborted due to quality gate failure: ${qg.status}"
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
            version: "build-${env.BRANCH_NAME}-${env.BUILD_NUMBER}",
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

      stage('Build docker image and push to registry') {
        container('docker') {
          withCredentials([usernamePassword(credentialsId: 'nexus-credential', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
            sh """
              # Clean target directory
              rm -rf target
              mkdir -p target/
              echo ${scmVars.GIT_COMMIT} > VERSION
              # Need for download from HTTPS
              apk --no-cache add openssl wget
              wget -O target/petclinic-build-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.jar --user=$NEXUS_USERNAME --password=$NEXUS_PASSWORD https://nexus.demo.opsta.co.th/repository/maven-releases/repository/maven-releases/org/springframework/samples/petclinic/build-${env.BRANCH_NAME}-${env.BUILD_NUMBER}/petclinic-build-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.jar
              docker build -t ${imageTag} .
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
                sed -i 's/commitId: CHANGE_COMMIT_ID/commitId: ${scmVars.GIT_COMMIT}/g' k8s/values-uat.yaml
                helm upgrade -i --namespace uat -f k8s/values-uat.yaml --wait petclinic-uat k8s/helm
                """
              break

            // Roll out a dev environment
            case "dev":
              sh """
                sed -i 's/commitId: CHANGE_COMMIT_ID/commitId: ${scmVars.GIT_COMMIT}/g' k8s/values-dev.yaml
                helm upgrade -i --namespace dev -f k8s/values-dev.yaml --wait petclinic-dev k8s/helm
                """
              break
          }
        }
      }

      stage("Run User Acceptance Test") {
        container('robot') {
          sh """
          sleep 30s
          sed -i 's!/opt/robotframework/reports!target/robot/reports!g' /opt/robotframework/bin/run-tests-in-virtual-screen.sh
          sed -i 's!/opt/robotframework/tests!src/test/robotframework!g' /opt/robotframework/bin/run-tests-in-virtual-screen.sh
          sed -i 's!localhost!http://petclinic.${subDomain}.demo.opsta.co.th!g' src/test/robotframework/test.robot
          export BROWSER=chrome
          run-tests-in-virtual-screen.sh
          """
          step([
            $class: 'RobotPublisher',
            disableArchiveOutput: false,
            logFileName: 'target/robot/reports/log.html',
            otherFiles: '',
            outputFileName: 'target/robot/reports/output.xml',
            outputPath: '.',
            passThreshold: 100,
            reportFileName: 'target/robot/reports/report.html',
            unstableThreshold: 0
          ])
        }
      }

      stage("Run Performance Test") {
        // TODO Use JMeter Parameter Instead
        // Wait until site is ready before do performance test
        container('jmeter') {
          sh """
          sed -i 's/localhost/petclinic.${subDomain}.demo.opsta.co.th/g' src/test/jmeter/petclinic_test_plan.jmx
          jmeter -n -t src/test/jmeter/petclinic_test_plan.jmx -l performance.jtl -Jjmeter.save.saveservice.output_format=xml
          """
          perfReport sourceDataFiles: 'performance.jtl'
        }
      }

    }
  }
}
