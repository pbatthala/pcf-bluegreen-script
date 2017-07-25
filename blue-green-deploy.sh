#!/bin/sh

echo "+++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "Blue Green Deployment"
echo "https://github.com/lshannon/pcf-bluegreen-script"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++"
echo ""
echo ""

if [ "$#" -ne 3 ]; then
	    echo "Usage: blue-green-deploy.sh 'PCF Domain' 'Existing Application Name In PCF' 'Location Of Application To Deploy'";
	    echo "Hint: blue-green-deploy.sh 'cfapps.io' 'spring-music' 'green-app' ";
	    echo "Program terminating ...";
	    exit 1;
fi

# Set Up Required Variables
DOMAIN=$1
ORIGINAL_APP=$2
NEW_APP_NAME="$2-green"
NEW_APP_LOCATION="$3"
OLD_APP="$2-previous"

echo "Steps To Execute:"
echo "----------------------------"
echo "1. Check for $ORIGINAL_APP"
echo "2. Deploy The Contents of $NEW_APP_LOCATION as $NEW_APP_NAME"
echo "3. Run smoke Tests on $NEW_APP_NAME"
echo "4. Switch over traffic from $ORIGINAL_APP to $NEW_APP_NAME"
echo "5. Rename $NEW_APP_NAME to be $ORIGINAL_APP"
echo "6. Clean Up (scale down, stop, unmap)"
echo ""
echo "1. Check for $ORIGINAL_APP"
echo "---------------------------------------------------"
OUTPUT="$(cf events $ORIGINAL_APP)"
if [[ $OUTPUT == *"App $ORIGINAL_APP not found"* ]]; then
  echo "Need to do an intial CF push on $ORIGINAL_APP before doing a Blue Green Deployment"
	echo "Program Terminating..."
	exit 1;
else
	echo "$ORIGINAL_APP exists. Proceeding with the Upgrade..."
fi
echo ""

# push the application with a manifest that binds all required services
echo "2. Deploy The Contents of $NEW_APP_LOCATION as $NEW_APP_NAME"
echo ""
echo "Running: cf push -f $NEW_APP_LOCATION -p $NEW_APP_LOCATION -n $NEW_APP_NAME"
cf push -p $NEW_APP_LOCATION  -f $NEW_APP_LOCATION -n $NEW_APP_NAME
echo ""

# Run Tests on the newly deployed app check that it is okay
echo "3. Run smoke Tests on $NEW_APP_NAME"
echo ""
RESPONSE=`curl -sI http://NEW_APP_NAME.$DOMAIN/health`
echo "$RESPONSE"
if [[ $RESPONSE != *"HTTP/1.1 200 OK"* ]]
then
  echo "Service Did Not Start Up - Stopping Upgrade...";
  cf delete $NEW_APP_NAME -f;
  echo "New Service Deleted"
  echo "Upgrade Stopping"
  exit 1;
fi
echo ""

# start directing traffic to the new app instance
echo "4. Switch over traffic from $ORIGINAL_APP to $NEW_APP_NAME"
echo "cf map-route $NEW_APP_NAME $DOMAIN -n $ORIGINAL_APP"
cf map-route $NEW_APP_NAME $DOMAIN -n $ORIGINAL_APP
echo ""

# scale down the proi app instances
echo "5. Clean Up (delete temp routes)"
echo "Order of operations:"
echo "a. Scale Down"
echo "b. Unmap"
echo "c. Stop"
echo ""
echo "a. Scale Down"
echo "cf scale $ORIGINAL_APP -i 1"
cf scale $ORIGINAL_APP -i 1
echo ""

# stop taking traffic on the current prod instance
echo "b. Unmap $ORIGINAL_APP"
echo "cf unmap-route $ORIGINAL_APP $DOMAIN -n $ORIGINAL_APP"
cf unmap-route $ORIGINAL_APP $DOMAIN -n $ORIGINAL_APP
echo ""

# decommission the old app
echo "c. Stop $ORIGINAL_APP"
echo "cf stop $ORIGINAL_APP"
cf stop $ORIGINAL_APP
echo ""

# delete any version of the old app that might be lying around still
echo "Delete previous $OLD_APP"
echo "cf delete $OLD_APP -f"
cf delete $OLD_APP -f

echo "Rename $ORIGINAL_APP to $ORIGINAL_APP-old"
echo "cf rename $ORIGINAL_APP $ORIGINAL_APP-old"
cf rename $ORIGINAL_APP $ORIGINAL_APP-old
echo ""

# clean up the temp route
echo "Remove the temp route for $NEW_APP_NAME"
echo "cf unmap-route $NEW_APP_NAME $DOMAIN -n $NEW_APP_NAME"
cf unmap-route $NEW_APP_NAME $DOMAIN -n $NEW_APP_NAME
echo ""

# rename the app
echo "Rename $NEW_APP_NAME to $ORIGINAL_APP"
echo "cf rename $NEW_APP_NAME $ORIGINAL_APP"
cf rename $NEW_APP_NAME $ORIGINAL_APP
