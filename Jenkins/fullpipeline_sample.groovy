pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/your-username/your-project.git'
            }
        }

        stage('Build') {
            steps {
                script {
                    def mvn = tool name: 'Maven', type: 'maven'
                    def jdk = tool name: 'JDK 11', type: 'jdk'
                    env.JAVA_HOME = "${jdk}"
                    env.PATH = "${env.JAVA_HOME}/bin:${mvn}/bin:${env.PATH}"
                }
                sh 'mvn clean package'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn test'
            }
            post {
                always {
                    junit '**/target/surefire-reports/*.xml'
                }
            }
        }

        stage('Docker Build and Push') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'dockerhub', passwordVariable: 'DOCKERHUB_PASSWORD', usernameVariable: 'DOCKERHUB_USERNAME')]) {
                        sh 'docker login -u $DOCKERHUB_USERNAME -p $DOCKERHUB_PASSWORD'
                        sh 'docker build -t your-image-name .'
                        sh 'docker push your-image-name'
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        sh 'kubectl --kubeconfig=$KUBECONFIG set image deployment/your-deployment your-container=your-image-name'
                    }
                }
            }
        }
    }

    post {
        failure {
            mail to: 'team@example.com',
                 subject: "Failed Pipeline: ${currentBuild.fullDisplayName}",
                 body: "Something is wrong with ${env.BUILD_URL}"
        }
    }
}
