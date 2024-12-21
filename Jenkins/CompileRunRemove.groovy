pipeline {
    agent any

    stages {
        stage('Create C File') {
            steps {
                script {
                    // Create a correctly formatted C file
                    def cFileContent = '''\
#include <stdio.h>

int main() {
    printf("Hello, Jenkins!\\n");
    return 0;
}
'''
                    writeFile file: 'hello.c', text: cFileContent
                }
            }
        }

        stage('Compile C File') {
            steps {
                // Compile the C file using gcc
                sh 'gcc -o hello hello.c'
            }
        }

        stage('Test Executable') {
            steps {
                script {
                    // Run the compiled program and capture the output
                    def output = sh(script: './hello', returnStdout: true).trim()
                    echo "Program output: ${output}"

                    // Check if the output is as expected
                    if (output != 'Hello, Jenkins!') {
                        error("Test failed: Unexpected output '${output}'")
                    } else {
                        echo "Test passed!"
                    }
                }
            }
        }
    }

    post {
        always {
            // Clean up generated files
            echo 'Cleaning up...'
            sh 'rm -f hello hello.c'
        }
    }
}
