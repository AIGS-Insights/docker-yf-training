Yellowfin Training Instance
=========================

The Yellowfin Training instance image contains the Yellowfin application.
The Yellowfin App Only image contains only the Yellowfin application, and can be connected to an existing repository database. This image can be used as a single instance, or as a cluster node.
This can be used in production, data is persisted in the external repository so that no data is lost when containers are shutdown.

A prebuilt version of this image can be found on Docker Hub [here](https://hub.docker.com/r/yellowfinbi/yellowfin-app-only).

Prerequisites
--------------

A Docker installation is required to run the Yellowfin docker containers.
Please see the official [Docker installation guides](https://docs.docker.com/install)

The Application Only image requires that a Yellowfin Repository be pre-installed on an accessible host.


Starting the training instance Image
--------------------

docker run -d  --name yellowfin-training  -p 8080:8080  yellowfin:9.16.1.1

This will start the training instance image with the default settings and expose Yellowfin on port 8080 on the host.

License Deployment
----------------------

The training instance deployment will require that a license file be loaded into the web interface after startup.


Configuration Options
----------------------

|| Configuration Item -  Application Memory

|| Description -  Specify the number of megabytes of memory to be assigned to the Yellowfin application. If unset, Yellowfin will use the Java default (usually 25% of System RAM) 

|| Example -  Specify the number of megabytes of memory to be assigned to the Yellowfin application. If unset, Yellowfin will use the Java default (usually 25% of System RAM)  |  ```-e APP_MEMORY=4096 ``` |


After Starting the Container
-----------------------------

After starting a container, use a browser to connect to the docker host's TCP port that has been mapped container's application port.

For example:

docker run -d  --name yellowfin-training  -p 8080:8080  yellowfin:9.16.1.1

Connect to:

http://dockerhost:8080


There may be a slight delay before the browser responds after the docker container is started.


Diagnosing Potential Issues and Modifying Configuration
--------------------------------------------------------

You can connect to a running instance of Yellowfin with the exec command.
This allows you to access log files and system settings.

```bash
docker exec -it <docker containerid> /bin/sh
```

The docker containerid can be obtained from the command:

```bash
docker container list
```

If settings are changed in a running docker container, Yellowfin may require restarting. This can be done with the command:

```bash
docker restart <docker containerid>
```
