# 🖴 Urbackup in Docker the right way

[![Build Status](https://gitlab.com/lansible1/docker-urbackup-server/badges/master/pipeline.svg)](https://gitlab.com/lansible1/docker-urbackup-server/pipelines)
[![Docker Pulls](https://img.shields.io/docker/pulls/lansible/urbackup-server.svg)](https://hub.docker.com/r/lansible/urbackup-server)
[![Docker Version](https://images.microbadger.com/badges/version/lansible/urbackup-server:latest.svg)](https://microbadger.com/images/lansible/urbackup-server:latest)
[![Docker Size/Layers](https://images.microbadger.com/badges/image/lansible/urbackup-server:latest.svg)](https://microbadger.com/images/lansible/urbackup-server:latest)

Make sure you set the backupfolder to /backups in the webinterface on first startup!

## Test locally

Make sure these directories are created as 1000:1000 otherwise chown or run the container with --user
```console
# mkdir config backups
#  docker run --read-only -p 55414:55414 -v "$PWD/config":/urbackup -v "$PWD/backups":/backups urbackup
```

## Credits

* [uroni/urbackup_backend](https://github.com/uroni/urbackup_backend)
