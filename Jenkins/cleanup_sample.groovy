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
    }

    post {
        always {
            cleanWs()
            sh 'docker rmi your-image-name'
        }
    }
}
