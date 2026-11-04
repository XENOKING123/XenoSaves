#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <netinet/in.h>
#include <ps5/kernel.h>

static pid_t find_pid(const char *name) {
    int mib[4] = {1, 14, 8, 0};
    size_t size;
    if (sysctl(mib, 4, NULL, &size, NULL, 0))
        return -1;
    unsigned char *buf = malloc(size);
    if (sysctl(mib, 4, buf, &size, NULL, 0)) {
        free(buf);
        return -1;
    }
    pid_t pid = -1;
    for (unsigned char *p = buf; p < buf + size;) {
        int len = *(int *)p;
        if (len <= 0)
            break;
        if (!strcmp((char *)(p + 447), name)) {
            pid = *(pid_t *)(p + 72);
            break;
        }
        p += len;
    }
    free(buf);
    return pid;
}

static int read_full(int fd, uint8_t *buf, size_t size) {
    size_t done = 0;
    while (done < size) {
        ssize_t n = read(fd, buf + done, size - done);
        if (n <= 0)
            return -1;
        done += n;
    }
    return 0;
}

static int write_full(int fd, const uint8_t *buf, size_t size) {
    size_t done = 0;
    while (done < size) {
        ssize_t n = write(fd, buf + done, size - done);
        if (n <= 0)
            return -1;
        done += n;
    }
    return 0;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    pid_t shellcore = find_pid("SceShellCore");
    pid_t self = getpid();
    if (shellcore < 0)
        return 1;
    uint8_t caps[16], attrs[32];
    uint64_t authid = kernel_get_ucred_authid(shellcore);
    kernel_get_ucred_caps(shellcore, caps);
    kernel_get_ucred_attrs(shellcore, attrs);
    kernel_set_ucred_authid(self, authid);
    kernel_set_ucred_caps(self, caps);
    kernel_set_ucred_attrs(self, attrs);

    int device = open("/dev/ncdt", O_RDWR);
    if (device < 0) {
        perror("open /dev/ncdt");
        return 1;
    }
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(9022);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        listen(listener, 1) < 0) {
        perror("bind/listen 9022");
        return 1;
    }
    puts("oracle ready on 9022");
    for (;;) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) {
            perror("accept");
            continue;
        }
        uint8_t request[0x4c] = {0};
        if (read_full(client, request, 32) < 0) {
            puts("short oracle request");
            close(client);
            continue;
        }
        int result = ioctl(device, 0xc04c4e03, request);
        printf("ioctl=%d status=0x%x\n", result, *(uint32_t *)(request + 0x48));
        if (result == 0)
            write_full(client, request + 0x20, 40);
        close(client);
    }
}
