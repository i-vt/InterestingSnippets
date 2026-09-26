def projectNames = ['project1', 'project2', 'project3']

projectNames.each { projectName ->
    job(projectName) {
        description "This is a job for ${projectName}"

        scm {
            git("https://github.com/your-username/${projectName}.git")
        }

        triggers {
            scm('H/15 * * * *')
        }

        steps {
            shell("echo Building ${projectName}")
        }
    }
}
