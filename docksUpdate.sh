#!/bin/bash
################THIS IS THE GENERALISED VERSION OF DOCKER IMAGING SCRIPT SCRIPT######################################
################Author for optimisation, Ankush Sharma###############################################################


##########Custom Variables###########################################################################################

IMAGE_NAME=uat/backend


middle_tag=":uat-"
Jenkins_pro_path="/var/lib/jenkins/workspace/uat-mapp.tataskybb.com"
docker_image_path="652024084351.dkr.ecr.ap-south-1.amazonaws.com"
jenkins_local_aws_path="/var/lib/jenkins/.local/bin/aws"
aws_region="ap-south-1"

TASK_FAMILY="tsbb-uat-backend-task"
SERVICE_NAME="tsbb-uat-backend-service"
REPOSITORY_NAME=uat/backend



CLUSTER_NAME="tsbb-uat-ecs-cluster"
#####################################################################################################################
function task_process(){
DOCKER_LOG=`$jenkins_local_aws_path ecr get-login --no-include-email --region $aws_region`
JARFind=`find $Jenkins_pro_path/build/libs -type f -name "AdminSpot-*.jar"`
${DOCKER_LOGIN}

echo "Building docker image..."
JAR= ${JARFind}

cd $Jenkins_pro_pathen

git_tag=$(git rev-parse --short HEAD)
docker_image=$IMAGE_NAME$middle_tag$git_tag
cp $JAR $Jenkins_pro_path
#cp -R $Jenkins_pro_path/newrelic /var/lib/jenkins/workspace/uat-mapp.tataskybb.com/docker/
cd $Jenkins_pro_path/docker/

docker build -t $docker_image .
if [ $? -eq 0 ]
then
  echo "Successfully image created"
else
  echo "Error in creating image"
  exit 1
fi
docker tag $docker_image $docker_image_path/$docker_image
docker push $docker_image_path/$docker_image

if [ $? -eq 0 ]
then
  echo "Successfully image tagged and pushed to repository"
  echo $docker_image_path/$docker_image > $WORKSPACE/image_id
  cat $WORKSPACE/image_id
else
  echo "Error in tagging/pushing image"
  exit 1
fi


cd $Jenkins_pro_path


#Store the repositoryUri as a variable
NEW_DOCKER_IMAGE=`cat $WORKSPACE/image_id`
OLD_TASK_DEF=$($jenkins_local_aws_path ecs describe-task-definition --task-definition $TASK_FAMILY --output json --region $aws_region)
NEW_TASK_DEF=$(echo $OLD_TASK_DEF | jq --arg NDI $NEW_DOCKER_IMAGE '.taskDefinition.containerDefinitions[0].image=$NDI')
FINAL_TASK=$(echo $NEW_TASK_DEF | jq '.taskDefinition|{family: .family, taskRoleArn: .taskRoleArn, networkMode: .networkMode, volumes: .volumes, containerDefinitions: .containerDefinitions, placementConstraints: .placementConstraints}')
TASK_OUTPUT=$($jenkins_local_aws_path ecs register-task-definition --family $TASK_FAMILY --cli-input-json "$(echo $FINAL_TASK)"  --region $aws_region)

if [ $? -eq 0 ]
then
  echo "New task has been registered"
else
  echo "Error in task registration"
  exit 1
fi
echo "Now deploying new version..."
$($jenkins_local_aws_path ecs update-service --service $SERVICE_NAME  --desired-count 1 --task-definition $TASK_FAMILY --cluster $CLUSTER_NAME  --region $aws_region)

NEW_TASK_ARN=$(echo $TASK_OUTPUT | jq -r '.taskDefinition.taskDefinitionArn')

for i in {1..90}
do
   SERVICE_STATUS=$($jenkins_local_aws_path ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME  --region $aws_region)
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
}


task_process