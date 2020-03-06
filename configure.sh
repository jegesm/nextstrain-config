#!/bin/bash

MODULE_NAME=nextstrain
RF=$BUILDDIR/${MODULE_NAME}

mkdir -p $RF

NLOG=$LOG_DIR/${MODULE_NAME}
NCONF=$CONF_DIR/${MODULE_NAME}
STUDIES=$SRV/_${MODULE_NAME}-studies 

DOCKER_COMPOSE_FILE=$RF/docker-compose.yml

case $VERB in
  "build")
    echo "Building ${MODULE_NAME} image ${PREFIX}-base"

    mkdir -p $STUDIES 
    mkdir -p ${NCONF} 
    mkdir -p ${NLOG} 
    
    docker $DOCKERARGS volume create -o type=none -o device=$STUDIES -o o=bind vol-nextstrain-studies
    docker $DOCKERARGS volume create -o type=none -o device=${NLOG} -o o=bind ${PREFIX}-${MODULE_NAME}-log
    docker $DOCKERARGS volume create -o type=none -o device=${NCONF} -o o=bind ${PREFIX}-${MODULE_NAME}-conf
    
    sed -e "s/##PREFIX##/$PREFIX/" \
        -e "s/##MODULE_NAME##/${MODULE_NAME}/" \
	-e "s/##OUTERHOST##/${OUTERHOST}/" docker-compose.yml-template > $DOCKER_COMPOSE_FILE

    docker-compose $DOCKER_HOST -f $DOCKER_COMPOSE_FILE build
      echo "Generating secrets..."

  ;;
  "install")

  ;;
  "install-nginx")
    register_nginx $MODULE_NAME
  ;;
  "uninstall-nginx")
    unregister_nginx $MODULE_NAME
  ;;
  "start")
    echo "Starting container ${PREFIX}-${MODULE_NAME}"
    docker-compose $DOCKERARGS -f $DOCKER_COMPOSE_FILE up -d
    
  ;;
  "init")

    docker exec ${PREFIX}-${MODULE_NAME}-mysql bash -c "echo 'show databases' | mysql -u root --password=$CBIOPORTALDBROOT_PW -h $PREFIX-${MODULE_NAME}-mysql | grep  -q $CBIOPORTALDB" ||\
       if [ ! $? -eq 0 ];then
    docker exec ${PREFIX}-${MODULE_NAME}-mysql bash -c " echo \"CREATE DATABASE $DB; CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PW'; GRANT ALL ON $DB.* TO '$DB_USER'@'%';\" |  \
             mysql -u root --password=$DBROOT_PW  -h $PREFIX-${MODULE_NAME}-mysql"
       fi
    docker cp $RF/cgds.sql ${PREFIX}-${MODULE_NAME}-mysql:/tmp/
    docker exec ${PREFIX}-${MODULE_NAME}-mysql bash -c "mysql -u root --password=$CBIOPORTALDBROOT_PW $CBIOPORTALDB < /tmp/cgds.sql"
    docker exec ${PREFIX}-${MODULE_NAME} bash -c "python3 /cbioportal/core/src/main/scripts/migrate_db.py -y --properties-file /cbioportal/portal.properties --sql /cbioportal/db-scripts/src/main/resources/migration.sql"
    echo "${PREFIX}-${MODULE_NAME} Mysql (cbio) is setup."


    docker exec ${PREFIX}-${MODULE_NAME}-mysql bash -c "echo 'show databases' | mysql -u root --password=$CBIOPORTALDBROOT_PW -h $PREFIX-${MODULE_NAME}-mysql | grep  -q $DB" ||\
       if [ ! $? -eq 0 ];then
    docker exec ${PREFIX}-${MODULE_NAME}-mysql bash -c " echo \"CREATE DATABASE $DB; CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PW'; GRANT ALL ON $DB.* TO '$DB_USER'@'%';\" |  \
             mysql -u root --password=$DBROOT_PW  -h $PREFIX-${MODULE_NAME}-mysql"
       fi
    docker exec ${PREFIX}-${MODULE_NAME}-admin python3 /cbioportal/cbioportal/manage.py makemigrations
    docker exec ${PREFIX}-${MODULE_NAME}-admin python3 /cbioportal/cbioportal/manage.py migrate
    docker exec -it ${PREFIX}-${MODULE_NAME}-admin python3 /cbioportal/cbioportal/manage.py createsuperuser
    echo "${PREFIX}-${MODULE_NAME} Mysql (admin) is setup."

  ;;
  "stop")
      echo "Stopping container ${PREFIX}-${MODULE_NAME}"
      docker-compose $DOCKERARGS -f $DOCKER_COMPOSE_FILE down
  ;;
    
  "remove")
      echo "Removing $DOCKER_COMPOSE_FILE"
      docker-compose $DOCKERARGS -f $DOCKER_COMPOSE_FILE kill
      docker-compose $DOCKERARGS -f $DOCKER_COMPOSE_FILE rm    

  ;;
  "purge")
  echo "Cleaning cbioportal folder $SRV/${MODULE_NAME}"
  
    rm -r ${CBIOPORTAL_DIR}* $CBIOPORTAL_LOG $CBIOPORTAL_CONF
    docker $DOCKERARGS volume rm  ${PREFIX}-${MODULE_NAME}-admin ${PREFIX}-${MODULE_NAME}-ldap-etc ${PREFIX}-${MODULE_NAME}-ldap-var\
           ${PREFIX}-${MODULE_NAME}-seeddb ${PREFIX}-${MODULE_NAME}-mysqldb ${PREFIX}-${MODULE_NAME}-studies\
	   ${PREFIX}-${MODULE_NAME}-log

  ;;
  "clean")
    echo "Cleaning cbioportal image ${PREFIX}-cbioportal"
    docker $DOCKERARGS rmi ${PREFIX}-cbioportal
  ;;
esac
