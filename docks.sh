#!/bin/bash


DOCKER_LOGIN=`/var/lib/jenkins/.local/bin/aws ecr get-login --no-include-email --region ap-south-1`
${DOCKER_LOGIN}

echo "Building docker image..."
JAR=$(find /var/lib/jenkins/workspace/uat-mapp.tataskybb.com/build/libs -type f -name "AdminSpot-*.jar")
IMAGE_NAME=uat/backend
cd /var/lib/jenkins/workspace/uat-mapp.tataskybb.com
git_tag=$(git rev-parse --short HEAD)
docker_image=$IMAGE_NAME:uat-$git_tag
cp $JAR /var/lib/jenkins/workspace/uat-mapp.tataskybb.com/docker/
#cp -R /var/lib/jenkins/workspace/uat-mapp.tataskybb.com/newrelic /var/lib/jenkins/workspace/uat-mapp.tataskybb.com/docker/
cd /var/lib/jenkins/workspace/uat-mapp.tataskybb.com/docker/

docker build -t $docker_image .
if [ $? -eq 0 ]
then
  echo "Successfully image created"
else
  echo "Error in creating image"
  exit 1
fi
docker tag $docker_image 652024084351.dkr.ecr.ap-south-1.amazonaws.com/$docker_image
docker push 652024084351.dkr.ecr.ap-south-1.amazonaws.com/$docker_image

if [ $? -eq 0 ]
then
  echo "Successfully image tagged and pushed to repository"
  echo 652024084351.dkr.ecr.ap-south-1.amazonaws.com/$docker_image > $WORKSPACE/image_id
  cat $WORKSPACE/image_id
else
  echo "Error in tagging/pushing image"
  exit 1
fi


cd /var/lib/jenkins/workspace/uat-mapp.tataskybb.com

TASK_FAMILY="tsbb-uat-backend-task"
SERVICE_NAME="tsbb-uat-backend-service"
REPOSITORY_NAME=uat/backend
#Store the repositoryUri as a variable
NEW_DOCKER_IMAGE=`cat $WORKSPACE/image_id`
CLUSTER_NAME="tsbb-uat-ecs-cluster"
OLD_TASK_DEF=$(/var/lib/jenkins/.local/bin/aws ecs describe-task-definition --task-definition $TASK_FAMILY --output json --region ap-south-1)
NEW_TASK_DEF=$(echo $OLD_TASK_DEF | jq --arg NDI $NEW_DOCKER_IMAGE '.taskDefinition.containerDefinitions[0].image=$NDI')
FINAL_TASK=$(echo $NEW_TASK_DEF | jq '.taskDefinition|{family: .family, taskRoleArn: .taskRoleArn, networkMode: .networkMode, volumes: .volumes, containerDefinitions: .containerDefinitions, placementConstraints: .placementConstraints}')

TASK_OUTPUT=$(/var/lib/jenkins/.local/bin/aws ecs register-task-definition --family $TASK_FAMILY --cli-input-json "$(echo $FINAL_TASK)"  --region ap-south-1)
if [ $? -eq 0 ]
then
  echo "New task has been registered"
else
  echo "Error in task registration"
  exit 1
fi
echo "Now deploying new version..."
$(/var/lib/jenkins/.local/bin/aws ecs update-service --service $SERVICE_NAME  --desired-count 1 --task-definition $TASK_FAMILY --cluster $CLUSTER_NAME  --region ap-south-1)

NEW_TASK_ARN=$(echo $TASK_OUTPUT | jq -r '.taskDefinition.taskDefinitionArn')

for i in {1..90}
do
   SERVICE_STATUS=$(/var/lib/jenkins/.local/bin/aws ecs describe-services --cluster tsbb-uat-ecs-cluster --services tsbb-uat-backend-service  --region ap-south-1)
   RUNNING_TASK_ARN=$(echo $SERVICE_STATUS | jq -r '.services[0].deployments[0].taskDefinition')
   DEPLOYMENT_COUNT=$(echo $SERVICE_STATUS | jq -r '.services[0].deployments' | jq '. | length')
   
   if [ $DEPLOYMENT_COUNT -eq 1 ]
    then
      if [ "$NEW_TASK_ARN" == "$RUNNING_TASK_ARN" ]
       then
      	 echo "Application has been deployed successfully !!!"
      	 exit 0;
      fi
   fi
   echo "Waiting for the deployment status..."
   sleep 10;
done

if [ $i -eq 90 ]
then
  echo "Application deployment timeout..."
  exit 1
fi
