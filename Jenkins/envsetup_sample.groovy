pipeline {
    agent none

    stages {
        stage('Environment Setup') {
            agent {
                docker {
                    image 'maven:3.6.3-jdk-11'
                    args '-v $HOME/.m2:/root/.m2'
                }
            }
            steps {
                checkout scm
            }
        }
        stage('Build') {
            steps {
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
    }

    post {
        always {
            cleanWs()
        }
    }
}
