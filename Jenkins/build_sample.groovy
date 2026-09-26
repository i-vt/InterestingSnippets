node {
    stage('Checkout') {
        git 'https://github.com/your-username/your-project.git'
    }

    stage('Build') {
        def mvn = tool name: 'Maven', type: 'maven'
        def jdk = tool name: 'JDK 11', type: 'jdk'
        env.JAVA_HOME = "${jdk}"
        env.PATH = "${env.JAVA_HOME}/bin:${mvn}/bin:${env.PATH}"
        sh 'mvn clean package'
    }

    stage('Archive') {
        archiveArtifacts artifacts: '**/target/*.jar', fingerprint: true
    }
}
