node {
    stage('Checkout') {
        git 'https://github.com/your-username/your-project.git'
    }

    stage('Build') {
        sh 'docker build -t your-image-name .'
    }

    stage('Push') {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', passwordVariable: 'DOCKERHUB_PASSWORD', usernameVariable: 'DOCKERHUB_USERNAME')]) {
            sh 'docker login -u $DOCKERHUB_USERNAME -p $DOCKERHUB_PASSWORD'
            sh 'docker push your-image-name'
        }
    }

    stage('Deploy') {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
            sh 'kubectl --kubeconfig=$KUBECONFIG set image deployment/your-deployment your-container=your-image-name'
        }
    }
}
