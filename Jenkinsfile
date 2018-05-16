properties([
  gitLabConnection('gitlab-opsta'),
  parameters([
    choice(choices: 'deploy-by-branch\ntagging\ndeploy-production', description: 'Action to do', name: 'ACTION'),
    [$class: 'GitParameterDefinition', branch: '', branchFilter: '.*', defaultValue: '', description: 'Choose tag to deploy (Need to combine with ACTION = deploy-production)', name: 'TAG', quickFilterEnabled: false, selectedValue: 'NONE', sortMode: 'DESCENDING_SMART', tagFilter: 'build-*', type: 'PT_TAG']
  ])
])

def label = "petclinic-${UUID.randomUUID().toString()}"
podTemplate(label: label, cloud: 'kubernetes', containers: [
    containerTemplate(name: 'docker', image: 'docker', ttyEnabled: true, command: 'cat'),
    containerTemplate(name: 'helm', image: 'lachlanevenson/k8s-helm', command: 'cat', ttyEnabled: true),
    containerTemplate(name: 'git', image: 'paasmule/curl-ssl-git', command: 'cat', ttyEnabled: true)
  ],
  volumes: [
    hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
]) {
  node(label) {

    appName = 'petclinic'

    if(params.ACTION == "tagging") {

      stage('Pull UAT image and tag to production image') {
        container('docker') {
          imageTag = "registry.demo.opsta.co.th/${appName}:uat"
          imageTagProd = "registry.demo.opsta.co.th/${appName}:build-${env.BUILD_NUMBER}"
          withCredentials([usernamePassword(credentialsId: 'nexus-credential', usernameVariable: 'DOCKER_HUB_USER', passwordVariable: 'DOCKER_HUB_PASSWORD')]) {
            sh """
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
          withCredentials([file(credentialsId: 'kubeconfig-kubernetes', variable: 'KUBECONFIG')]) {
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

      stage('Build image') {
        container('docker') {
          sh """
            echo ${scmVars.GIT_COMMIT} > VERSION
            docker build -t ${imageTag} --build-arg MAVEN_OPTS="-s maven-settings.xml" .
            """
        }
      }

      stage('Push image to registry') {
        container('docker') {
          withCredentials([usernamePassword(credentialsId: 'nexus-credential', usernameVariable: 'DOCKER_HUB_USER', passwordVariable: 'DOCKER_HUB_PASSWORD')]) {
            sh """
              docker push ${imageTag}
              """
          }
        }
      }

      stage("Deploy Application") {
        container('helm') {
          // Put kubeconfig file
          withCredentials([file(credentialsId: 'kubeconfig-kubernetes', variable: 'KUBECONFIG')]) {
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
