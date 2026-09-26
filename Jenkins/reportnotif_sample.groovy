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
                sh 'make'
            }
        }

        stage('Test') {
            steps {
                sh 'make test'
            }
            post {
                always {
                    junit '**/test-reports/*.xml'
                }
            }
        }
    }

    post {
        success {
            mail to: 'team@example.com',
                 subject: "Successful Build: ${currentBuild.fullDisplayName}",
                 body: "The build has completed successfully. Check the build details at ${env.BUILD_URL}."
        }
        failure {
            mail to: 'team@example.com',
                 subject: "Failed Build: ${currentBuild.fullDisplayName}",
                 body: "The build has failed. Check the build details and console output at ${env.BUILD_URL}."
        }
    }
}
